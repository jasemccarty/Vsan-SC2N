<#==========================================================================
Script Name: Vsan-2NForcedCache.ps1
Created on: 4/15/2016 
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: http://www.jasemccarty.com
===========================================================================

.DESCRIPTION
This script sets DOM Owner Forced Warm Cache
https://blogs.vmware.com/virtualblocks/2016/04/18/2node-read-locality/

Syntax is:
To Set 2 Node Forced Cache
Vsan-2NForcedCache.ps1 -ClusterName <ClusterName> -ForceCache enable
To Disable 2 Node Forced Cache
Vsan-2NForcedCache.ps1 -ClusterName <ClusterName> -ForceCache disable

.Notes

#>

# Set our Parameters
[CmdletBinding()]Param(
  [Parameter(Mandatory=$True)]
  [string]$ClusterName,

  [Parameter(Mandatory = $true)]
  [ValidateSet('enable','disable')]
  [String]$ForceCache
)

# Must be connected to vCenter Server 1st
# Connect-VIServer

# Get the Cluster Name
$Cluster = Get-Cluster -Name $ClusterName

# Check to ensure we have either enable or disable, and set our values/text
Switch ($ForceCache) {
	"disable" { 
		$FORCEVALUE = "0"
		$FORCETEXT  = "Default (local) Read Caching"
		}
	"enable" {
		$FORCEVALUE = "1"
		$FORCETEXT  = "Forced Warm Cache" 
		}
	default {
		write-host "Please include the parameter -ForceCache enable or -ForceCache disabled"
		exit
		}
	}
    # Display the Cluster
    Write-Host Cluster: $($Cluster.name)
    
    # Check to make sure we only have 2 Nodes in the cluster and Virtual SAN is enabled
    $HostCount = $Cluster | Select @{n="count";e={($_ | Get-VMHost).Count}}
    If($HostCount.count -eq "2" -And $Cluster.VsanEnabled){

        # Cycle through each ESXi Host in the cluster
    	Foreach ($ESXHost in ($Cluster |Get-VMHost |Sort Name)){
		
	# Get the current setting for diskIoTimeout
	$FORCEDCACHE = Get-AdvancedSetting -Entity $ESXHost -Name "VSAN.DOMOwnerForceWarmCache"
                  
        	# By default, if the IO Timeout doesn't align with KB2135494
		# the setting may or may not be changed based on Script parameters
                If($FORCEDCACHE.value -ne $FORCEVALUE){

			# Show that host is being updated
			Write-Host "2 Node $FORCETEXT Setting for $ESXHost"
			$FORCEDCACHE | Set-AdvancedSetting -Value $FORCEVALUE -Confirm:$false

                } else {

			# Show that the host is already set for the right value
			Write-Host "$ESXHost is already configured for $FORCETEXT"

		}
	}
		            
    } else {
    	
    	# Throw and error message that this isn't a 2 Node Cluster.
	Write-Host "The cluster ($ClusterName) is not a 2 Node cluster and/or does not have Virtual SAN enabled."
    }
