<#==========================================================================
Script Name: Vsan-WitnessDeploy.ps1 (v3)
Created on: 1/5/2017 
Updated on: 10/31/2019
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: http://www.jasemccarty.com
===========================================================================

Using runGuestOpInVM from VirtuallyGhetto

.DESCRIPTION
This script deploys a vSAN 6.0/6.5/6.7 & 6.7 P01 Witness Appliance.
It: Configures networking, 
    Adds it to vCenter
    Sets static routes 
    Makes the Witness Host available for use in a vSAN Stretched or 2 Node Cluster

Syntax is: Vsan-WitnessDeploy.ps1 

.Notes
#>

# vCenter Server to deploy the Witness Appliance
$VIServer          = "vcsa.demo.local"              # vCenter Server we're using
$VIUsername        = "administrator@vsphere.local"  # user for vCenter
$VIPassword        = "VMware1!"                     # password for vCenter user

# Full Path to the vSAN Witness Appliance & Cluster
$vSANWitnessOVA    = "/Users/jase/Desktop/VMware-vSAN-Witness-6.5.0.update03-13932383.ova"
$targetcluster     = "Cluster" 	                    # Cluster the OVA will be deployed to
$ntp1              = "ntp0.eng.vmware.com"          # NTP Host 1
$ntp2              = "ntp1.eng.vmware.com"          # NTP Host 2
$datastore 	   = "DATASTORENAME"                # Name of the Target Datastore

# Management Network Properties
$vmname            = "WITNESS"                      # Name of the Witness VM
$passwd            = "VMware1!"                     # Witness VM root password
$dns1              = "10.198.16.1"                  # DNS Server1
$dns2              = "10.198.16.2"                  # DNS Server2
$hostname          = "witness.satm.eng.vmware.com"  # DNS Address of the Witness VM
$dnsdomain         = "satm.eng.vmware.com"          # DNS Search Domain
$ipaddress0        = "10.198.7.200"                 # IP address of VMK0, the Management VMK
$netmask0          = "255.255.253.0"                # Netmask of VMK0
$gateway0          = "10.198.7.253"                 # Default System Gateway
$network0          = "Cloud"                        # The network name that the Managment VMK will reside on

# Witness Network Properties
$ipaddress1        = "172.16.1.12"                  # IP address of VMK1, the WitnessPg VMK
$netmask1          = "255.255.255.0"                # Netmask of VMK1
$network1          = "Cloud"                        # The network name that the Witness VMK will reside on
$deploymentsize    = "tiny"                         # The OVA deployment size. Options are "tiny","normal", and "large"
$witnessdatacenter = "Witness"                      # The Datacenter that the Witness Host will be added to 

# Witness Static Routes
$route1ip          = "172.16.2.0"                   # IP/Range of Site A vSAN IP addresses
$route1gw          = "172.16.1.1"                   # Gateway to Site A that VMK1 will use
$route1pfx         = "24"                           # Network Prefix

$route2ip          = "172.16.3.0"                   # IP/Range of Site B vSAN IP addresses
$route2gw          = "172.16.1.1"                   # Gateway to Site B that VMK1 will use
$route2pfx         = "24"                           # Network Prefix

# vSAN Traffic Tagged NIC Selection 
$vsannetwork       = "Secondary"                    # 'Management' or 'Secondary' NIC

# Credit William Lam
# Using PowerCLI to invoke Guest Operations API to a Nested ESXi VM
# http://www.virtuallyghetto.com/2015/07/using-powercli-to-invoke-guest-operations-api-to-a-nested-esxi-vm.html
 
Function runGuestOpInESXiVM() {
	param(
		$vm_moref,
		$guest_username, 
		$guest_password,
		$guest_command_path,
		$guest_command_args
	)
	
	# Guest Ops Managers
	$guestOpMgr = Get-View $session.ExtensionData.Content.GuestOperationsManager
	$authMgr = Get-View $guestOpMgr.AuthManager
	$procMgr = Get-View $guestOpMgr.processManager
	
	# Create Auth Session Object
	$auth = New-Object VMware.Vim.NamePasswordAuthentication
	$auth.username = $guest_username
	$auth.password = $guest_password
	$auth.InteractiveSession = $false
	
	# Program Spec
	$progSpec = New-Object VMware.Vim.GuestProgramSpec
	# Full path to the command to run inside the guest
	$progSpec.programPath = "$guest_command_path"
	$progSpec.workingDirectory = "/tmp"
	# Arguments to the command path, must include "++goup=host/vim/tmp" as part of the arguments
	$progSpec.arguments = "++group=host/vim/tmp $guest_command_args"
	
	# Issue guest op command
	$cmd_pid = $procMgr.StartProgramInGuest($vm_moref,$auth,$progSpec)
}
		
# Start a session and connect to vCenter Server
$session = Connect-VIServer -Server $VIServer -User $VIUsername -Password $VIPassword

# Get the vCenter Object
$vCenter = $global:DefaultVIServer

# Grab the OVA properties from the vSAN Witness Appliance OVA
$ovfConfig = Get-OvfConfiguration -Ovf $vSANWitnessOVA

# Set the Network Port Groups to use, the deployment size, and the root password for the vSAN Witness Appliance
if ($ovfConfig.vsan) {
	$ovfconfig.vsan.witness.root.passwd.value = $passwd
	$ovfconfig.NetworkMapping.Management_Network.value = $network0
	$ovfconfig.NetworkMapping.Witness_Network.value = $network1
	$ovfConfig.DeploymentOption.Value = $deploymentsize
	$WitnessGen = 0
} else {
	$ovfConfig.Common.guestinfo.passwd.value = $passwd
	$ovfConfig.Common.guestinfo.ipaddress0.value = $ipaddress0
	$ovfConfig.Common.guestinfo.netmask0.value = $netmask0
	$ovfConfig.Common.guestinfo.gateway0.value = $gateway0
	$ovfConfig.Common.guestinfo.hostname.value = $hostname
	$ovfConfig.Common.guestinfo.dnsDomain.value = $dnsdomain
	$ovfConfig.Common.guestinfo.dns.value = $dns1 + "," + $dns2
	$ovfConfig.Common.guestinfo.ntp.value = $ntp1 + "," + $ntp2
	$ovfConfig.Common.guestinfo.ipaddress1.value = $ipaddress1
	$ovfConfig.Common.guestinfo.netmask1.value = $netmask1
	$ovfConfig.Common.guestinfo.gateway1.value = $gateway1
	$ovfConfig.Common.guestinfo.vsannetwork.value = $vsannetwork
	$ovfconfig.NetworkMapping.Management_Network.value = $network0
	$ovfconfig.NetworkMapping.Secondary_Network.value = $network1
	$ovfConfig.DeploymentOption.Value = $deploymentsize    
	$WitnessGen = 1
}

# VCSA 6.7 Workaround for tiny/large profiles
If ($vCenter.Version -eq "6.7.0") {
	$ovfconfig.DeploymentOption.Value = 'normal'
} else {
	$ovfconfig.DeploymentOption.Value = $deploymentsize
}

# Grab a random host in the cluster to deploy to
If ($TargetHost) {
	Write-Host "TargetHost:"$TargetHost 
	$DestHost = Get-VMHost -Name $TargetHost
} else {
	$DestHost = Get-Cluster $TargetCluster | Get-VMHost | Where-Object {$_.PowerState -eq "PoweredOn" -and $_.ConnectionState -eq "Connected"} |Get-Random
}

# Grab a random datastore if the datastore is not specified
If ($TargetDatastore) {
	Write-Host "Using $TargetDatastore"
	$DestDatastore = $TargetDatastore
} else {
	$DestDatastore = $DestHost | Get-Datastore | Get-Random
}

# Import the vSAN Witness Appliance 
Import-VApp -Source $vSANWitnessOVA -OvfConfiguration $ovfConfig -Name $vmname -VMHost $DestHost -Datastore $DestDatastore -DiskStorageFormat Thin

# Workaround for VCSA handling of tiny/large Profiles (tiny only)
$WitnessVm = Get-VM -Name $vmname

If (($vCenter.Version -eq "6.7.0") -and (($deploymentsize -eq 'tiny') -or ($deploymentsize -eq 'large'))) {
	# We're going to overcome the InstanceID issue in VCSA 6.7 for tiny/large profile selections
	Write-Host "Adjusting the deployment process for VCSA 6.7 for the $deploymentsize deployment size"
	Switch ($deploymentsize) {
		# If it is tiny, lets 86 the 350GB drive and replace it with a 15GB drive (thin of course)
		# And set the RAM to 8GB
		"tiny" { 
			If ((Get-HardDisk -VM $WitnessVm | Where-Object {$_.CapacityGB -eq '350'})) {
				Write-Host "Adjusting the capacity disk for use with the $deploymentsize profile"
				Remove-Harddisk -HardDisk ($WitnessVm | Get-HardDisk | Where-Object {$_.CapacityGB -eq "350"}) -Confirm:$false | Out-Null
				New-HardDisk -CapacityGB "15" -VM $WitnessVm -StorageFormat "Thin" -Confirm:$False | Out-Null
			}
			If ((Get-VM -Name $WitnessVm).MemoryGB -ne 8) {
				Write-Host "Adjusting the RAM allocation for the $deploymentsize profile"
				Set-VM -VM $WitnessVm -MemoryGB "8" -Confirm:$False | Out-Null 
			}
		}
		# If it is large, lets add 2 more 350GB drives (thin of course)
		# And set the RAM to 32GB
		"large" {
			# Add drives
			If ((Get-HardDisk -VM $WitnessVm | Where-Object {$_.CapacityGB -eq '350'}).Count -ne 3) {
				Write-Host "Adjusting the capacity disk for use with the $deploymentsize profile"
				New-HardDisk -CapacityGB "350" -VM $WitnessVm -StorageFormat "Thin" -Confirm:$False | Out-Null
				New-HardDisk -CapacityGB "350" -VM $WitnessVm -StorageFormat "Thin" -Confirm:$False | Out-Null
			}
			# Modify RAM configuration
			If ((Get-VM -Name $WitnessVm).MemoryGB -ne 32) {
				Write-Host "Adjusting the RAM allocation for the $deploymentsize profile"
				Set-VM -VM $WitnessVm -MemoryGB "32" -Confirm:$False | Out-Null 
			}
		}
	}
		# If we're still using the LSI Logic SCSI controller, let's change it to ParaVirtual like the 6.7U3 Witness Appliance
		If (($WitnessVm |Get-ScsiController).Type -ne 'ParaVirtual') {
			$WitnessVm | Get-ScsiController | Set-ScsiController -Type "Paravirtual" -Confirm:$False | Out-Null 
		}
} else {
	# If we're deploying a Normal profile, we still need to change the SCSI controller to ParaVirtual 
	If (($WitnessVm |Get-ScsiController).Type -ne 'ParaVirtual') {
		$WitnessVm | Get-ScsiController | Set-ScsiController -Type "Paravirtual" -Confirm:$False | Out-Null 
	}
}	

sleep 30

# Power on the vSAN Witness Appliance
$WitnessVm | Start-VM 

# Set the $WitnessVM guestos credentials
$esxi_username = "root"
$esxi_password = $passwd

        # Wait until the tools are running because we'll need them to set the IP
        Write-host "Waiting for VM Tools to Start"
        do {
            $toolsStatus = (Get-VM $vmname | Get-View).Guest.ToolsStatus
            write-host "." -NoNewLine  #$toolsStatus
            sleep 5
        } until ( $toolsStatus -eq 'toolsOk' )
		Write-Host ""
		Write-Host "VM Tools have started"

        sleep 20

    If ($WitnessGen -eq 0) {

        # Setup our commands to set IP/Gateway information
        $Command_Path = '/bin/python'

        # CMD to set Management Network Settings
        $CMD_MGMT = '/bin/esxcli.py network ip interface ipv4 set -i vmk0 -I ' + $ipaddress0 + ' -N ' + $netmask0  + ' -t static;/bin/esxcli.py network ip route ipv4 add -N defaultTcpipStack -n default -g ' + $gateway0
        # CMD to set DNS & Hostname Settings
        $CMD_DNS = '/bin/esxcli.py network ip dns server add --server=' + $dns2 + ';/bin/esxcli.py network ip dns server add --server=' + $dns1 + ';/bin/esxcli.py system hostname set --fqdn=' + $hostname + ';/bin/esxcli.py network ip dns search add -d ' + $dnsdomain

        # CMD to set the IP address of VMK1
        $CMD_VMK1_IP = '/bin/esxcli.py network ip interface ipv4 set -i vmk1 -I ' + $ipaddress1 + ' -N ' + $netmask1  + ' -t static'

        # CMD to set the Gateway of VMK1
        $CMD_VMK1_GW = '/bin/esxcli.py network ip route ipv4 add -N defaultTcpipStack -n default -g ' + $gateway1
        
	# Setup the Management Network
        Write-Host "Setting the Management Network"
        Write-Host
        runGuestOpInESXiVM -vm_moref $WitnessVm.ExtensionData.MoRef -guest_username $esxi_username -guest_password $esxi_password -guest_command_path $command_path -guest_command_args $CMD_MGMT
        runGuestOpInESXiVM -vm_moref $WitnessVm.ExtensionData.MoRef -guest_username $esxi_username -guest_password $esxi_password -guest_command_path $command_path -guest_command_args $CMD_DNS

	# Setup the Witness Portgroup
        Write-Host "Setting the WitnessPg Network"
        runGuestOpInESXiVM -vm_moref $WitnessVm.ExtensionData.MoRef -guest_username $esxi_username -guest_password $esxi_password -guest_command_path $command_path -guest_command_args $CMD_VMK1_IP
}

# For good measure, we'll wait before trying to add the guest to vCenter
Write-Host "Going to wait for the host to become available before attempting to add it to vCenter"


# Wait until the vSAN Witness Host is up and running before proceeding
Write-Host "Pinging $ipaddress0"
Do {Write-Host "." -NoNewline} Until (!(Test-Connection $ipaddress0 -Quiet -Count 4 |Out-Null))		

# Grab the DNS entry for the guest if possible
Try {$DnsName = [System.Net.Dns]::GetHostEntry($ipaddress0)}
Catch {Write-Host "Couldn't retrieve DNS Entry for $hostname";$DnsName=$ipaddress0}

# If the DNS names match, add by DNS, if they don't add by IP
if ($DnsName.HostName -eq $hostname){
		Write-Host "Witness Hostname & DNS Entry Match"
		$NewWitnessName = $hostname 
	} else {
		Write-Host "Witness Hostname & DNS Entry Don't Match"
		$NewWitnessName = $ipaddress0
}

# Add the new Witness host to vCenter 
Write-Host "Adding $NewWitnessName to the $witnessdatacenter Datacenter"
Add-VMHost $NewWitnessName -Location $witnessdatacenter -user root -password $passwd -Force | Out-Null

# Grab the host, so we can set NTP & Static Routes (if exist & vsannetwork is not Management)
$WitnessHost = Get-VMhost -Name $NewWitnessName

If ($vsannetwork -eq "Management") {
	If ($WitnessGen -eq 0) {
		# When set to Management, this uses vmk0 for vSAN Traffic
		Get-VMHostNetworkAdapter -VMHost $WitnessHost | Where-Object {$_.DeviceName -eq "vmk1"} | Set-VMHostNetworkAdapter -VsanTrafficEnabled $false -Confirm:$False | Out-Null
		Get-VMHostNetworkAdapter -VMHost $WitnessHost | Where-Object {$_.DeviceName -eq "vmk0"} | Set-VMHostNetworkAdapter -VsanTrafficEnabled $true -Confirm:$False | Out-Null		
	}
} else {
	If ($route1ip -and $route2ip) {
		# Set Static Routes
		Write-Host "Setting Static Routes for the Witness Network"
		$WitnessRoute1 = New-VMHostRoute $WitnessHost -Destination $route1ip -Gateway $route1gw -PrefixLength $route1pfx -Confirm:$False | Out-Null
		$WitnessRoute2 = New-VMHostRoute $WitnessHost -Destination $route2ip -Gateway $route2gw -PrefixLength $route2pfx -Confirm:$False | Out-Null
	}
}

# Set the NTP Server for Gen0 vSAN Witness Appliances (take care of in vSAN 6.7 P01 Witness Appliances
If ($WitnessGen -eq 0) {
	Add-VMHostNtpServer -NtpServer $ntp2 -VMHost $WitnessHost -Confirm:$False | Out-Null
	Add-VMHostNtpServer -NtpServer $ntp1 -VMHost $WitnessHost -Confirm:$False | Out-Null
}

Write-Host "Starting NTP Client"
#Start NTP client service and set to automatic
Get-VmHostService -VMHost $WitnessHost | Where-Object {$_.key -eq "ntpd"} | Start-VMHostService | Out-Null
Get-VmHostService -VMHost $WitnessHost | Where-Object {$_.key -eq "ntpd"} | Set-VMHostService -policy "on" | Out-Null 

# Disconnect from vCenter
Disconnect-VIServer -Server $session -Confirm:$false
