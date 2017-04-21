<#==========================================================================
Script Name: Vsan-StretchedClusterDrsOnTag.ps1
Created on: 4/20/2017 
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: http://www.jasemccarty.com
===========================================================================

.DESCRIPTION
This script will go through each host in a designated cluster and 
set /VSAN/SwapThickProvisionDisabled to either Thin or Space Reserved (Thick)

This requires PowerCLI 6.5.1 and has been tested on vSAN 6.6

.SYNTAX
Vsan-StretchedClusterDrsOnTag.ps1 -VCENTER <VCENTER> -CLUSTER <CusterName>

#>

# Set our Parameters
[CmdletBinding()]Param(
  [Parameter(Mandatory=$True)]
  [string]$VCENTER,

  [Parameter(Mandatory = $True)]
  [String]$ClusterName,

  [Parameter(Mandatory = $False)]
  [String]$User,

  [Parameter(Mandatory = $False)]
  [String]$Password
  
)

Connect-VIServer $VCENTER -user $User -password $Password

$Cluster = Get-Cluster -Name $ClusterName

$VsanCluster = Get-VsanClusterConfiguration -Cluster $Cluster

If($VsanCluster.StretchedClusterEnabled){

	Write-Host "*******************************************"
	Write-Host "Sites:"
	Write-Host " Getting Names "
	$PreferredFaultDomain = $VsanCluster.PreferredFaultDomain.Name
	$SecondaryFaultDomain = Get-VsanFaultDomain | Where {$_.Name -ne $PreferredFaultDomain}
	
	Write-Host " Getting Hosts in Each"
	$PreferredFaultDomainHostList = Get-VsanFaultDomain | Where {$_.Name -eq $PreferredFaultDomain} |Get-VMHost
	$SecondaryFaultDomainHostList = Get-VsanFaultDomain | Where {$_.Name -eq $SecondaryFaultDomain} |Get-VMHost
	
	Write-Host " Get VM Assignment based on VM Tags"
	$PreferredTag = Get-Cluster | Get-VM | Get-TagAssignment |Where{$_.Tag -like $PreferredFaultDomain}
	$SecondaryTag = Get-Cluster | Get-VM | Get-TagAssignment |Where{$_.Tag -like $SecondaryFaultDomain} 
	
	Write-Host " Setting the Host Group Name for each Site"
	$PreferredVMHostGroupName = "Hosts-" + $PreferredFaultDomain
	$SecondaryVMHostGroupName  = "Hosts-" + $SecondaryFaultDomain

	Write-Host " Setting the VM Group Name for each Site"
	$PreferredVMGroupName = "VMs-" + $PreferredFaultDomain
    $SecondaryVMGroupName = "VMs-" + $SecondaryFaultDomain

	Write-Host " Setting the VMtoHost Rule Name for each Site"
	$PreferredVMtoHostGroupName = "Assigned-" + $PreferredFaultDomain
	$SecondaryVMtoHostGroupName = "Assigned-" + $SecondaryFaultDomain

	Write-Host ""
	Write-Host "*******************************************"
	Write-Host "Groups" 
	Write-Host " Creating the Site Host Groups"
	$PreferredVMHostGroup = New-DrsClusterGroup -Cluster $Cluster -Name $PreferredVMHostGroupName -VMHost $PreferredFaultDomainHostList
	$SecondaryVMHostGroup = New-DrsClusterGroup -Cluster $Cluster -Name $SecondaryVMHostGroupName -VMHost $SecondaryFaultDomainHostList

	Write-Host " Creating the Site VM Groups"
	$PreferredVMGroup = New-DrsClusterGroup -Cluster $Cluster -Name $PreferredVMGroupName -VM $PreferredTag.Entity
	$SecondaryVMGroup = New-DrsClusterGroup -Cluster $Cluster -Name $SecondaryVMGroupName -VM $SecondaryTag.Entity
	
	Write-Host " Setting the VM to Host Group Names"
	$PreferredVMtoHostRule = "VMtoSite" + $PreferredFaultDomain
	$SecondaryVMtoHostRule = "VMtoSite" + $SecondaryFaultDomain

	Write-Host ""
	Write-Host "*******************************************"
	Write-Host "Rules:"
	Write-Host " Creating/Assigning VM Groups to Host Groups"
	$PreferredRule = New-DrsVMHostRule -Name $PreferredVMtoHostRule -Cluster $Cluster -VMGroup $PreferredVMGroup -VMHostGroup $PreferredVMHostGroup -Type "ShouldRunOn" -Enabled $True
	$SecondaryRule = New-DrsVMHostRule -Name $SecondaryVMtoHostRule -Cluster $Cluster -VMGroup $SecondaryVMGroup -VMHostGroup $SecondaryVMHostGroup -Type "ShouldRunOn" -Enabled $True

	Write-Host ""
	Write-Host "*******************************************"
	Write-Host "Checking for vSAN 6.6 Site Affinity Rule Capability"
	$Affinity = (Get-SpbmCapability |Where {$_.Name -eq 'VSAN.locality'}).FriendlyName
	
	If($Affinity -eq "Affinity"){
		
		Write-Host "Site Affinity Rule Capabilites Present, Checking for VM's with Site Affinity Policies"
		Foreach ($ClusterVM in (Get-Cluster |Get-VM)){

		Write-Host "Getting Affinty Rule for $ClusterVM"
		$AffinitySite =  ((Get-VM -Name $ClusterVM |Get-SpbmEntityConfiguration).StoragePolicy.AnyofRuleSets.AllOfRules | Where {$_.Capability -like "VSAN.locality"}).Value
		
		Switch ($AffinitySite) {
				"Preferred Fault Domain" {
											Write-Host "Ensuring $ClusterVM doesn't reside in the alternate group"
											$Remove = Get-DrsClusterGroup $SecondaryVMGroup  | Set-DrsClusterGroup -VM $ClusterVM -Remove
											Write-Host "Assigning $ClusterVM to the proper group"
											$Add = Get-DrsClusterGroup $PreferredVMGroup  | Set-DrsClusterGroup -VM $ClusterVM -Add
										}
				"Secondary Fault Domain" {
											Write-Host "Ensuring $ClusterVM doesn't reside in the alternate group"
											$Remove = Get-DrsClusterGroup $PreferredVMGroup  | Set-DrsClusterGroup -VM $ClusterVM -Remove
											Write-Host "Assigning $ClusterVM to the proper group"
											$Add = Get-DrsClusterGroup $SecondaryVMGroup  | Set-DrsClusterGroup -VM $ClusterVM -Add										} 
				}
		
		
		}
	
	}
}

