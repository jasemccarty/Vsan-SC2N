<#==========================================================================
Script: deploy2node.ps1
Created on: 3/26/2018
Created by: Jase McCarty
Github: https://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: https://www.jasemccarty.com
===========================================================================

.SYNOPSIS Deploy a 2 Node vSAN Cluster using PowerCLI
.NOTES Author:  Jase McCarty
.NOTES Site:    www.jasemccarty.com/blog
.NOTES Requires my 2 Node / Stretched Cluster module here: https://code.vmware.com/samples/3734
.EXAMPLE
  deploy2node.ps1

#>

# Variables Section
# Remote Site **************************************************************************
    # Remote Site (2 Node) Variables for Datacenter & Cluster naming
    $DataCenterName = "RemoteSitesDC"                                           # Datacenter name for the 2 Node Cluster(s)
    $ClusterName = "RemoteCluster"                                              # Cluster name for a single cluster

    # Remote Site (2 Node) Variables for vSphere Distributed Switch
    $VdsName = "VD-DirectConnect"                                               # vSphere Distributed Switch name (common at Datacenter leve)
    $VdsMtu = "9000"                                                            # VDS MTU

    # Remote Site (2 Node) Variables for vSAN & vMotion Direct-Connect networks
    $VsanVmkVlan = "101"                                                        # vLAN for vSAN Network
    $VsanVmkSegment = "192.168.101."                                            # vSAN Network Segment
    $VsanVmkMask = "255.255.255.0"                                              # vSAN Network Subnet Mask
    $VsanVmkMtu = "9000"                                                        # vSAN Network MTU

    $VmotionVmkVlan = "102"                                                     # vLAN for vMotion Network
    $VmotionVmkSegment = "192.168.102."                                         # vMotion Network Segment
    $VmotionVmkMask = "255.255.255.0"                                           # vMotion Network Subnet Mask
    $VmotionVmkMtu = "9000"                                                     # vMotion Network MTU

    # Remote Site (2 Node) Variables for ESXi hosts already deployed to the remote site
    $Host1 = "node1.domain.local"                                               # Host 1 - Will be the Preferred Node
    $Host2 = "node2.domain.local"                                               # Host 2 - Will be the Secondary Node
    $HostPwd = "VMware1!"                                                       # Common root password for both nodes

    # Remote Site (2 Node) Variables for ESXi hosts for Witness Traffic Separation
    $UseVmk0ForWts = $false                                                     # If $false, create a VMkernel for WTS traffic. If $true, use vmk0 for WTS traffic

    # Values for dedicated WTS VMkernel Interface
    $HostWtsVmkSegment = "192.168.15."                                          # WTS VMK Network Segment
    $HostWtsVmkMask = "255.255.255.0"                                           # WTS VMK Network Subnet Mask
    $HostWtsVmkGateway = "192.168.15.1"                                         # WTS VMK Network Gateway
    $HostWtsVmkVlanId = "15"                                                    # WTS VMK Network vLAN ID
    $HostWtsVmkPrefix = "24"                                                    # WTS VMK Network Prefix (used when creating routes)

# Central DC/Main Site *******************************************************************

    # Central DC/Main Site Variables for Datacenter & Cluster for vSAN Witness Deployment
    $MainDatacenter = "Main-Office"                                             # Main Datacenter Name
    $MainCluster = "Main-DC"                                                    # Main Datacenter Cluster used to house vSAN Witness Appliances
    $MainClusterDatastore = "MainDCDatastore"                                   # Datastore to be used for housing vSAN Witness Appliances

    # Central DC/Main Site Variables for vSAN Witness Appliance
    $OVAPath = "./VMware-VirtualSAN-Witness-6.7.0-8169922.ova"                  # Filename and Path for the vSAN Witness Appliance - Must be same build as deployed ESXi hosts
    $OVAName = "WITNESS"                                                        # vSAN Witness Appliance VM Name
    $OVASize = "tiny"                                                           # vSAN Witness Appliance VM size - 'tiny','normal','large'

    # Central DC/Main Site Variables for Deployment Networks
    $OVAPg1 = "Witness-Management-Network"                                      # vSAN Witness Appliance Management Port Group on MainCluster
    $OVAPg2 = "Witness-vSAN-Network"                                            # vSAN Witness Appliance vSAN Traffic Port Group on MainCluster

    # Central DC/Main Site Variables for vSAN Witness Host Networking
    $WitnessVmk0IP = "192.168.109.23"                                           # vSAN Witness Appliance Management IP (vmk0)
    $WitnessVmk0Mask = "255.255.255.0"                                          # vSAN Witness Appliance Management Subnet Mask
    $WitnessVmk0Prefix = "24"                                                   # vSAN Witness Appliance Network Prefix (used for routing commands)
    $WitnessVmk0Gateway = "192.168.109.1"                                       # vSAN Witness Appliance Network Gateway

    $WitnessVmk1IP = "192.168.110.23"                                           # vSAN Witness Appliance WitnessPg IP (vmk1) - Cannot be the same segment as vmk0 unless $WitnessVmkVsanTraffic is set to 'vmk0'
    $WitnessVmk1Segment = "192.168.110.0"                                       # vSAN Witness Appliance WitnessPg Segment (used for routing commands)
    $WitnessVmk1Mask = "255.255.255.0"                                          # vSAN Witness Appliance WitnessPg Subnet Mask
    $WitnessVmk1Prefix = "24"                                                   # vSAN Witness Appliance WitnessPg Prefix (used for routing commands)
    $WitnessVmk1Gateway = "192.168.110.1"                                       # vSAN Witness Appliance WitnessPg Gateway

    $WitnessVmkVsanTraffic = "vmk1"                                             # Which vSAN Witness Appliance VMkernel will be used for vSAN Traffic? 'vmk0','vmk1'
    $WitnessFQDN = "witness.domain.central"                                     # FQDN of the vSAN Witness Appliance as it relates to the 2 Node Cluster
    $WitnessDNS1 = "192.168.1.1"                                                # Witness DNS 1
    $WitnessDNS2 = "192.168.1.2"                                                # Witness DNS 2

    $WitnessToDataNodeAddress = "192.168.15.0"                                  # Segment to route to for vSAN Witness Appliance VMkernel with vSAN Traffic
    $WitnessToDataNodePrefix = "24"                                             # Prefx used with $WitnessToDataNodeAddress (for routing)
    $WitnessToDataNodeGateway = "192.168.110.1"                                 # Gateway to use for vSAN Witness VMkernel (if vmk1) 

# End Variables Section *******************************************************************

# No Code Changes Required Below **********************************************************

# Check for the existance of the vSAN Witness Appliance at the destination
If (-Not (Get-Datacenter -Name $MainDatacenter | Get-Cluster -Name $MainCluster | Get-VM -Name $OVAName -ErrorAction SilentlyContinue)) {

    # Upload a Witness VM:
    Write-Host "Uploading vSAN Witness Appliance" -ForegroundColor "blue"
    New-VsanStretchedClusterWitness -Cluster $MainCluster -Datastore $MainClusterDatastore -OVAPath $OVAPath -Name $OVAName -Pass $HostPwd -Size $OVASize -PG1 $OVAPg1 -PG2 $OVAPg2

    # Configure vSAN Witness Appliance Networking Addressing:
    Write-Host "Configuring vSAN Witness Appliance Networking" -ForegroundColor "blue"
    Set-VsanWitnessNetwork -Name $OVAName -Pass $HostPwd -VMkernel vmk1 -VMkernelIp $WitnessVmk1IP -NetMask $WitnessVmk1Mask
    Set-VsanWitnessNetwork -Name $OVAName -Pass $HostPwd -VMkernel vmk0 -VMkernelIp $WitnessVmk0IP -NetMask $WitnessVmk0Mask -Gateway $WitnessVmk0Gateway -DNS1 $WitnessDNS1 -DNS2 $WitnessDNS2 -FQDN $WitnessFQDN

    # Add vSAN Witness Host to vCenter
    Write-Host "Adding the vSAN Witness Appliance to vCenter" -ForegroundColor "blue"
    Add-VMHost $WitnessFQDN -Location $MainDatacenter -user "root" -password $HostPwd -Force -RunAsync

    # Take a 2 minute pause while the vSAN Witness is being added to vCenter
    Start-Sleep -s 60

    If ($WitnessVmkVsanTraffic -ne "vmk1") {
        Write-Host "Check/Set vSAN Witness Appliance Management Network for vSAN Traffic" -ForegroundColor "blue"
        Set-VsanWitnessVMkernel -VMHost $WitnessFQDN -VsanVMkernel $WitnessVmkVsanTraffic
    }
    Write-Host "Set vSAN Witness to DataNode Routing for 2 Node" -ForegroundColor "blue"
    Set-VsanWitnessNetworkRoute -VMHost $WitnessFQDN -Destination $WitnessToDataNodeAddress -Gateway $WitnessToDataNodeGateway -Prefix $WitnessToDataNodePrefix
}

# Get/Create the Datacenter to be used
$Datacenter = Get-Datacenter | Where-Object {$_.Name -contains $DataCenterName}
While (-Not $Datacenter) {
    $Datacenter = New-Datacenter -Name $DataCenterName -Location (Get-Folder -NoRecursion)
    Start-Sleep -s 5
}

# Get/Create the Cluster to be used
$Cluster =  Get-Cluster | Where-Object {$_.Name -contains $ClusterName}
While (-Not $Cluster) {
    $Cluster = New-Cluster -Name $ClusterName -Location $Datacenter
    Start-Sleep -s 5
}


#Get the VDSwitch with the name $VdsName
$VDSwitch = Get-VDSwitch -Name $VdsName -ErrorAction SilentlyContinue
While (-Not $VDSwitch ){
    New-VDSwitch -Name $VdsName -Location $Datacenter -LinkDiscoveryProtocol "LLDP" -LinkDiscoveryProtocolOperation "Both" -NumUplinkPorts "4" -Version "6.6.0" -Mtu $VdsMtu -ErrorAction SilentlyContinue -RunAsync
    $VDSwitch = Get-VDSwitch -Name $VdsName -ErrorAction SilentlyContinue
}


# Configure a VDS for the vSAN Hosts
    # Get/Set the vSAN Port Group on the VDS
    $VsanNetwork = Get-VDPortGroup -Name "vSAN" -ErrorAction SilentlyContinue
    If (-Not $VsanNetwork) {
        New-VDPortgroup -Name "vSAN" -VDSwitch $VDSwitch.Name -NumPorts 8 -VlanId $VsanVmkVlan -ErrorAction SilentlyContinue -RunAsync
        $VsanNetwork = Get-VDPortGroup -Name "vSAN" -ErrorAction SilentlyContinue
    }

    #Get/Set the vMotion Port Group on the VDS     
    $VmotionNetwork = Get-VDPortGroup -Name "vMotion" -ErrorAction SilentlyContinue
    If (-Not $VmotionNetwork) {
        New-VDPortgroup -Name "vMotion" -VDSwitch $VDSwitch.Name -NumPorts 8 -VlanId $VmotionVmkVlan -ErrorAction SilentlyContinue -RunAsync
        $VmotionNetwork = Get-VDPortGroup -Name "vMotion" -ErrorAction SilentlyContinue
    }

# Refetch our object to pick up current configuration
$VDSwitch = Get-VDSwitch $VDSwitch

#Setting NIOC Recommendations for vSAN Configuration
Foreach ($NetworkResourcePool in $VDSwitch.ExtensionData.NetworkResourcePool) {

    Switch ($NetworkResourcePool.Key) {
        "vsan" {
            If ($NetworkResourcePool.AllocationInfo.Shares.Shares -ne "100") {
            $Shares = "100"
            $Alloc = New-Object VMware.Vim.DVSNetworkResourcePoolConfigSpec
            $Alloc.AllocationInfo = $NetworkResourcePool.AllocationInfo
            $Alloc.AllocationInfo.Shares.Shares = [long]$Shares
            $Alloc.AllocationInfo.Shares.Level = "Custom"
            $Alloc.ConfigVersion = $NetworkResourcePool.ConfigVersion
            $Alloc.Key = $NetworkResourcePool.Key
            Write-Host "Configuring NIOC Allocation for vSAN Traffic to 100 Shares" -ForegroundColor "blue"
            $VDSwitch.ExtensionData.UpdateNetworkResourcePool(@($Alloc))
            }
        }
        "vmotion" {
            $Shares = "50"
            $Alloc = New-Object VMware.Vim.DVSNetworkResourcePoolConfigSpec
            $Alloc.AllocationInfo = $NetworkResourcePool.AllocationInfo
            $Alloc.AllocationInfo.Shares.Shares = [long]$Shares
            $Alloc.AllocationInfo.Shares.Level = "Custom"
            $Alloc.ConfigVersion = $NetworkResourcePool.ConfigVersion
            $Alloc.Key = $NetworkResourcePool.Key
            Write-Host "Configuring NIOC Allocation for vMotion Traffic to 50 Shares" -ForegroundColor "blue" 
            $VDSwitch.ExtensionData.UpdateNetworkResourcePool(@($Alloc))
        }
        "virtualMachine" {
            $Shares = "30"
            $Alloc = New-Object VMware.Vim.DVSNetworkResourcePoolConfigSpec
            $Alloc.AllocationInfo = $NetworkResourcePool.AllocationInfo
            $Alloc.AllocationInfo.Shares.Shares = [long]$Shares
            $Alloc.AllocationInfo.Shares.Level = "Custom"
            $Alloc.ConfigVersion = $NetworkResourcePool.ConfigVersion
            $Alloc.Key = $NetworkResourcePool.Key
            Write-Host "Configuring NIOC Allocation for Virtual Machine Traffic to 30 Shares"  -ForegroundColor "blue"           
            $VDSwitch.ExtensionData.UpdateNetworkResourcePool(@($Alloc))
        }
        "management" {
            $Shares = "20"
            $Alloc = New-Object VMware.Vim.DVSNetworkResourcePoolConfigSpec
            $Alloc.AllocationInfo = $NetworkResourcePool.AllocationInfo
            $Alloc.AllocationInfo.Shares.Shares = [long]$Shares
            $Alloc.AllocationInfo.Shares.Level = "Custom"
            $Alloc.ConfigVersion = $NetworkResourcePool.ConfigVersion
            $Alloc.Key = $NetworkResourcePool.Key
            Write-Host "Configuring NIOC Allocation for Management Traffic to 20 Shares" -ForegroundColor "blue"            
            $VDSwitch.ExtensionData.UpdateNetworkResourcePool(@($Alloc))
        }
    }
}

# Enable NIOC
$VDSwitch.ExtensionData.EnableNetworkResourceManagement($true)


#Add vSAN Hosts:
Write-Host "Adding the 2 vSAN Nodes" -ForegroundColor "blue"

If (-Not (Get-VMHost -Name $Host1 -ErrorAction SilentlyContinue)) {
    Add-VMHost $Host1 -Location $Cluster -user "root" -password $HostPwd -Force -RunAsync
}
If (-Not (Get-VMHost -Name $Host2 -ErrorAction SilentlyContinue)) {
    Add-VMHost $Host2 -Location $Cluster -user "root" -password $HostPwd -Force -RunAsync
}

Start-Sleep -s 30
# Cycle through each ESXi Host in the cluster and 
# 1. Add the Host to the VDS
# 2. Add the Host's Physcial Adapters to the VDS
# 3. Grab the Management VMkernel IP and use the last Octect for the vSAN/vMotion Networks
# 4. Enable WTS for 2 Node Direct Connect 
# 5. Create the vSAN/vMotion VMkernel interfaces

Foreach ($ESXHost in ($Cluster | Get-VMHost)){
    
    # Add the Host to the VDS
	Write-Host "Adding $ESXHost to the VDS" -ForegroundColor "blue"
    $VDSwitch | Add-VDSwitchVMHost -VMHost $ESXHost -ErrorAction SilentlyContinue

    # Grab the pNICs with >1Gbps, we'll expect any NICs with >1Gbps to be direct connected
    $pNICs = $ESXHost | Get-VMHostNetworkAdapter | Where-Object {$_.BitRatePerSec -gt "1000"}

    If ($pNICs.Count) {
        ForEach ($pNIC in $pNICs ) {
            Write-Host "Adding pNIC to VDS" -ForegroundColor "blue"
            $VDSwitch | Add-VDSwitchPhysicalNetworkAdapter -VMHostPhysicalNic $pNIC -Confirm:$false
        }    
    } else {
        Write-Host "No physical NICs with >1Gbps found, exiting" -ForegroundColor "blue"
        exit 
    }


	# Grab the last octect of vmk0's IP
	$EsxVmk0 = $ESXHost | Get-VMHostNetwork | Select-Object Hostname, VMkernelGateway -ExpandProperty VirtualNic | Select-Object Hostname, DeviceName, IP  | Where-Object {$_.DeviceName -eq "vmk0"}
	$LastOctet = $EsxVmk0.IP.Split('.')[-1]

    # Check to see if vmk0 is being used for Witness Traffic Separation
    If ($UseVmk0ForWts -ne $true) {
        # If we're not using the Management VMkernel, create a VMkernel port for this traffic

        # Setup the WTS VMkernel IP
        $HostWtsVmkIP = $HostWtsVmkSegment+$LastOctet

        # Create a VMkernel port for WTS
        Write-Host "Creating a VMkernel port dedicated for Witness Traffic Separation" -ForegroundColor "blue"
        $VSS = Get-VMHost -Name $ESXHost | Get-VirtualSwitch -Name "vSwitch0"
        New-VMHostNetworkAdapter -VMHost $ESXHost -VirtualSwitch $VSS  -PortGroup "WTS" -IP $HostWtsVmkIP -SubnetMask $HostWtsVmkMask -Confirm:$false 

        If ($HostWtsVmkVlanId) {
            $HostWtsVmkPortGroup = Get-VMHost -Name $ESXHost | Get-VirtualPortGroup -Name "WTS"
            Write-Host "Updating the PortGroup $HostWtsVmkPortGroup to Vlan $HostWtsVmkVlanId" -ForegroundColor "blue"
            $HostWtsVmkPortGroup | Set-VirtualPortGroup -VLanId $HostWtsVmkVlanId 
        }

        Write-Host "Resting for a minute while the VMkernel port is created" -ForegroundColor "blue"
        Start-Sleep -s 30
        $HostWtsVmk = Get-VMHost -Name $ESXHost | Get-VirtualPortGroup -Name "WTS" | Get-VMHostNetworkAdapter

        # Configure Witness Traffic Separation
        Write-Host "Enabling Witness Traffic Separation for 2 Node Direct Connect" -ForegroundColor "blue"
        Write-Host "Host: $ESXHost, VMK: $HostWtsVmk" -ForegroundColor Yellow
        Set-VsanHostWitnessTrafficType -VMHost $ESXHost -Vmk $HostWtsVmk -Option "enable"
        Set-VsanWitnessNetworkRoute -VMHost $ESXHost -Destination $WitnessVmk1Segment -Gateway $HostWtsVmkGateway -Prefix $HostWtsVmkPrefix

    } else {

        # Configure Witness Traffic Separation
        Write-Host "Enabling Witness Traffic Separation for 2 Node Direct Connect on the Management VMkernel" -ForegroundColor "blue"
        Set-VsanHostWitnessTrafficType -VMHost $ESXHost -Vmk "vmk0" -Option "enable"
    }

    # Setup the vSAN VMkernel IP
    $VsanVMkIp = $VsanVmkSegment+$LastOctet


    # Setup the vMotion VMkernel IP    
    $VmotionVMkIp = $VmotionVmkSegment+$LastOctet

    Write-Host "Creating the vSAN interface" -ForegroundColor "blue"
    New-VMHostNetworkAdapter -VMHost $ESXHost -VirtualSwitch $VDSwitch -PortGroup $VsanNetwork -IP $VsanVMkIp -SubnetMask $VsanVmkMask -Mtu $VsanVmkMtu -VsanTrafficEnabled $true -Confirm:$false
    
    Write-Host "Creating the vMotion interface" -ForegroundColor "blue"
    New-VMHostNetworkAdapter -VMHost $ESXHost -PortGroup $VmotionNetwork -VirtualSwitch $VDSwitch -IP $VmotionVMkIp -SubnetMask $VmotionVmkMask -Mtu $VmotionVmkMtu -VMotionEnabled $true -Confirm:$false

}
# Enable the 2 Node Cluster
Write-Host "Enabling 2 Node vSAN" -ForegroundColor "blue"
$Cluster | Set-Cluster -VsanEnabled:$true -Confirm:$false -ErrorAction SilentlyContinue

# Cycle through each ESXi Host in the cluster and create disk groups
Foreach ($ESXHost in ($Cluster | Get-VMHost)){

	#Write-Host "Adding disk group(s) for $ESXHost"
    Add-VsanHostDiskGroup -VMHost $ESXHost -CacheMax 400 -DiskType "Flash"
}

Write-Host "Adding the vSAN Witness Appliance to the 2 Node Cluster" -ForegroundColor "blue"
New-VsanStretchedCluster -Clustername $Cluster -Witness $WitnessFQDN

Start-Sleep -s 240 

# Set the Default vSAN Storage Policy
$DefaultPolicy = Get-SpbmStoragePolicy | Where-Object {$_.Name -eq "vSAN Default Storage Policy"}

# Enable the vSAN Performance Service and set it to the Default Policy
Set-VsanClusterConfiguration -Configuration $Cluster -PerformanceServiceEnabled $true -Storagepolicy $DefaultPolicy


#Write-Host "Configuring VDS enhanced settings for use by vSAN"
# Upgrade DSwitch capabilities to 'NIOC v3' and 'Enhanced LACP Support'
#$spec = New-Object VMware.Vim.VMwareDVSConfigSpec
#$spec.networkResourceControlVersion = 'version3'
#$spec.lacpApiVersion = 'multipleLag'
#$spec.configVersion = $VDSwitch.ExtensionData.config.configVersion
#$spec.ExtensionData.NetworkResourceManagementEnable = $true
#$VDSwitch.ExtensionData.ReconfigureDvs($spec)



