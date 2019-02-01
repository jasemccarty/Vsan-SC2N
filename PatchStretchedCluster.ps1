# Patch vSAN Stretched Cluster v0.1
# Not compatible with PowerShell Core

# Variables - Enter the name of the vSAN Cluster here
$ClusterName = "vSAN"


# Retrive objects
# Get the Cluster Object
$Cluster = Get-Cluster -Name $ClusterName

# Get the vSAN Configuration
$ClusterConfiguration = Get-VsanClusterConfiguration -Cluster $Cluster

# Make certain we're working with a Stretched Cluster
If ($ClusterConfiguration.StretchedClusterEnabled -eq $true) {

    # Get the 3 Fault Domains: Preferred, Non-Preferred, & vSAN Witness Host
    # Get the Preferred Fault Domain
    $PreferredFd = Get-VsanFaultDomain -Cluster $Cluster | Where-Object {$_.Name -eq $ClusterConfiguration.PreferredFaultdomain}

    # Get the NonPreferred Fault Domain
    $SecondaryFD = Get-VsanFaultDomain -Cluster $Cluster | Where-Object {$_.Name -ne $ClusterConfiguration.PreferredFaultdomain}

    # Get the vSAN Witness Host
    $WitnessHost = $ClusterConfiguration.WitnessHost

    # Begin patching, assuming DRS is in place and set to Fully Automated
    # Write that we’re working on the Preferred FD
    Write-Host “Updating $PreferredFd”

    Foreach ($VMHost in ($PreferredFd | Get-VMHost)) {

        # Check the patch compliance of the current host
        Test-Compliance -Entity $VMHost

        # Get a list of non-compliant baselines
        $NonCompBase = Get-Compliance -Entity $VMHost | Where-Object {$_.Status -ne "Compliant"}

        # Notify that we’re not compliant with X baseline(s)
        Write-Host $VMHost "not compliant with baseline: " $NonCompBase.Baseline.Name

        # Enumerate each baseline we’re not compliant with and patch the host
        Foreach ($NonComp in $NonCompBase.BaseLine) {

            # Report which baseline is the host is being patched with
            Write-Host "Patching $VMHost with baseline:" $NonComp.Name
            $VMHost | Update-Entity -Baseline (Get-Baseline -Name $NonComp.Name) -Confirm:$False
        }
    }

    # Write that we’re working on the Preferred FD
    Write-Host $SecondaryFD

    Foreach ($VMHost in ($SecondaryFd | Get-VMHost)) {

        # Check the patch compliance of the current host
        Test-Compliance -Entity $VMHost
        
        # Get a list of non-compliant baselines
        $NonCompBase = Get-Compliance -Entity $VMHost | Where-Object {$_.Status -ne "Compliant"}
        
        # Notify that we’re not compliant with X baseline(s)
        Write-Host $VMHost "not compliant with baseline: " $NonCompBase.Baseline.Name
        
        # Enumerate each baseline we’re not compliant with and patch the host
        Foreach ($NonComp in $NonCompBase.BaseLine) {
            
            # Report which baseline the host is being patched with
            Write-Host "Patching $VMHost with baseline:" $NonComp.Name
            $VMHost | Update-Entity -Baseline (Get-Baseline -Name $NonComp.Name) -Confirm:$False
        }
    }

    # Write that we’re patching the vSAN Witness Host
    Write-Host “Updating $WitnessHost”

    # Check the patch compliance of the witness host
    Test-Compliance -Entity $WitnessHost

    # Get a list of non-compliant baselines
    $NonCompBase = Get-Compliance -Entity $WitnessHost | Where-Object {$_.Status -ne "Compliant"}

    # Notify that we’re not compliant with X baseline(s)
    Write-Host $WitnessHost "not compliant with baseline: " $NonCompBase.Baseline.Name

    # Enumerate each baseline we’re not compliant with and patch the host

    Foreach ($NonComp in $NonCompBase.BaseLine) {

        # Report which baseline the vSAN Witness host is being patched with
        Write-Host "Patching $WitnessHost with baseline:" $NonComp.Name
        $WitnessHost | Update-Entity -Baseline (Get-Baseline -Name $NonComp.Name) -Confirm:$False
    }
}
