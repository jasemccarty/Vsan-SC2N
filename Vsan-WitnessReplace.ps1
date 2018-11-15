<#==========================================================================
Script Name: Vsan-WitnessReplace.ps1
Created on: 12/18/2016 
Updated on: 11/14/2018
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: http://www.jasemccarty.com
===========================================================================

.DESCRIPTION
This script removes a Witness host for 2 Node and Stretched Cluster vSAN & replaces it.

Syntax is:
Vsan-ReplaceWitness.ps1 -ClusterName <ClusterName> -NewWitness <WitnessFQDN>

.Notes

#>

# Set our Parameters
[CmdletBinding()]Param(
[Parameter(Mandatory=$True)][string]$ClusterName,
[Parameter(Mandatory = $true)][String]$NewWitness
)
	
# Check to see the cluster exists
Try {
	# Check to make sure the New Witness Host has already been added to vCenter
	$Cluster = Get-Cluster -Name $ClusterName -ErrorAction Stop
}
	Catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.VimException]
{
	Write-Host "The cluster, $Clustername, was not found.               " -foregroundcolor red -backgroundcolor white
	Write-Host "Please enter a valid cluster name and rerun this script."  -foregroundcolor black -backgroundcolor white
	Exit
}		

# Check to make sure we are dealing with a vSAN cluster
If($Cluster.VsanEnabled){
	
	# Determine whether this is a 2 Node or Stretched Cluster
	$HostCount = $Cluster | Select @{n="count";e={($_ | Get-VMHost).Count}}
	Switch($HostCount.count){
		"2" {$SCTYPE = "2 Node"}
		default {$SCTYPE = "Stretched"}
	}
		
	# Let's go grab the vSAN Cluster's Configuration
	$VsanConfig = Get-VsanClusterConfiguration -Cluster $Cluster

	# If we're dealing with a Stretched Cluster architecture, then we can proceed
	If($VsanConfig.StretchedClusterEnabled) {

		# We'll need to get the Preferred Fault Domain, and be sure to set it as Preferred when setting up the new Witness
		$PFD = $VsanConfig.PreferredFaultDomain

		# We'll need to see what the name of the current witness is.
		$CWH = $VsanConfig.WitnessHost
				
			# If the Old & New Witness are named the same, no need to perform a replacement
			If ($NewWitness -ne $CWH.Name) {
			
				# Check to make sure the New Witness Host has already been added to vCenter
				Try {		
					# Get the Witness Host
					$NewWitnessHost = Get-VMHost -Name $NewWitness -ErrorAction Stop

					# See if it is the VMware vSAN Witness Appliance
					$IsVsanWitnessAppliance = Get-AdvancedSetting -Entity $NewWitnessHost -Name Misc.vsanWitnessVirtualAppliance
					
					# If it is the VMware vSAN Witness Appliance, then proceed
					If ($IsVsanWitnessAppliance.Value -eq "1"){
						Write-Host "$NewWitness is a vSAN Witness Appliance." -foregroundcolor black -backgroundcolor green
						
						# Check to make sure a VMKernel port is tagged for vSAN Traffic, otherwise exit. Could possibly tag a VMkernel next time
						If ( Get-VMHost $NewWitness | Get-VMHostNetworkAdapter | Where{$_.VsanTrafficEnabled}) {
							Write-Host "$NewWitness has a VMKernel port setup for vSAN Traffic. Proceeding."  -foregroundcolor black -backgroundcolor green
						} else {
							Write-Host "$NewWitness does not have a VMKernel port setup for vSAN Traffic. Exiting" -foregroundcolor red -backgroundcolor white
							Exit 
						}
					} else {
						# The Witness isn't a vSAN Witness Appliance, so exit 
						Write-Host "$NewWitness is not a vSAN Witness Appliance, stopping" -foregroundcolor red -backgroundcolor white
						Write-Host "This script only supports using the vSAN Witness Appliance"  -foregroundcolor red -backgroundcolor white
						Exit
					}
				}
				
				# If the NewWitness isn't present in vCenter, suggest deploying one and rerun this script
				Catch [VMware.VimAutomation.Sdk.Types.V1.ErrorHandling.VimException.VimException]{
					Write-Host "The New Witness, $NewWitness, was not found.         " -foregroundcolor red -backgroundcolor white
					Write-Host "Please deploy a vSAN Witness Appliance and rerun this script."  -foregroundcolor black -backgroundcolor white
					Exit
					}					
			
				Write-Host "$Cluster is a $SCTYPE Cluster"
				#Write-Host "The Preferred Fault Domain is ""$PFD"""
				Write-Host "Current Witness:  ""$CWH"" New Witness: ""$NewWitness"""
				
				# If the Existing Witness is connected or in maintenance mode, go ahead and cleanly unmount the disk group
				# We will assume that if it isn't connected, it has failed, and we just need to replace it.
				If ($CWH.ConnectionState -eq "Connected" -or $CWH.ConnectionState -eq "Maintenance") {
				
					# Get the disk group of the existing vSAN Witness
					$CWHDG = Get-VsanDiskGroup | Where-Object {$_.VMHost -like $CWH} -ErrorAction SilentlyContinue
				
					# Remove the existing disk group, so this Witness could be used later
					Write-Host "Removing vSAN Disk Group from $CWH so it can be easily reused later" -foregroundcolor black -backgroundcolor white
				    Remove-VsanDiskGroup -VsanDiskGroup $CWHDG -DataMigrationMode "NoDataMigration" -Confirm:$False 

				}
				
				# Set the cluster configuration to false - Necessary to swap Witness Appliances
				Write-Host "Removing Witness $CWH from the vSAN cluster" -foregroundcolor black -backgroundcolor white
				Set-VsanClusterConfiguration -Configuration $Cluster -StretchedClusterEnabled $false 

				# Set the cluster configuration to Stretched/2 Node, with the new witness and the previously preferred fault domain
				Write-Host "Adding Witness $NewWitness and reenabling the $SCTYPE Cluster" -foregroundcolor black -backgroundcolor white
				Set-VsanClusterConfiguration -Configuration $Cluster -StretchedClusterEnabled $True -PreferredFaultDomain $PFD -WitnessHost $NewWitness -WitnessHostCacheDisk mpx.vmhba1:C0:T2:L0 -WitnessHostCapacityDisk mpx.vmhba1:C0:T1:L0

				# Let's hang around while we wait for the Disk Group to be created on the Witness
				While (-Not(Get-VsanDiskGroup -VMHost $NewWitness)) {
					Get-VsanDisk -VMHost $NewWitness
				}

				# Fix all obects operation
				# Load the vSAN vC Cluster Health System View
				$VVCHS = Get-VsanView -Id "VsanVcClusterHealthSystem-vsan-cluster-health-system"

				# Invoke the Fix for all objects
				Write-Host "Issuing a repair all objects command"
				$RepairTask = $VVCHS.VsanHealthRepairClusterObjectsImmediate($Cluster.ExtensionData.MoRef,$null) 

			} else {
				# Don't let an admin remove the existing witness and re-add it
				Write-Host "$NewWitness is already the Witness for the $ClusterName Cluster"   -foregroundcolor black -backgroundcolor white
			}
			
		} else {

			# Show that the host is already set for the right value
			Write-Host "$Cluster.Name is not a Stretched Cluster " -foregroundcolor black -backgroundcolor green
			
		}
		            
    }
