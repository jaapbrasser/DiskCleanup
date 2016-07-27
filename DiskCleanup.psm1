function Get-VolumeCachesKey {
<#
.SYNOPSIS   
Returns the available keys in the VolumeCaches registry key
    
.DESCRIPTION 
Retrieves the available ChildObject from the following registry key: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches

.NOTES   
Name       : Get-VolumeCachesKey
Author     : Jaap Brasser
DateCreated: 2016-05-03
DateUpdated: 2016-05-03
Site       : http://www.jaapbrasser.com
Version    : 1.0.0
#>
    [cmdletbinding(SupportsShouldProcess)]
    param()

    process {
        if ($PSCmdlet.ShouldProcess($env:ComputerName,'Querying registry for key names')) {
            Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
        }
    }
}

function Get-VolumeCachesStateFlags {
<#
.SYNOPSIS   
Returns the defined StateFlags in the registry
    
.DESCRIPTION 
Iterates through the registry to generate a collection of custom objects containing the configuration options for the StateFlags set on the current system. These flags can be used with the cleanmgr.exe command line utility to automatically start a saved disk cleaning task.

.NOTES   
Name       : Get-VolumeCachesStateFlags
Author     : Jaap Brasser
DateCreated: 2016-05-03
DateUpdated: 2016-05-03
Site       : http://www.jaapbrasser.com
Version    : 1.0.0
#>
    [cmdletbinding(SupportsShouldProcess)]
    param()

    process {
        if ($PSCmdlet.ShouldProcess($env:ComputerName,'Querying registry for StateFlags')) {
            Get-VolumeCachesKey | ForEach-Object -Begin {
                $HashTable = @{}
            } -Process {
                $CurrentItem = $_
                ($CurrentProperty = Get-ItemProperty -Path $CurrentItem.PSPath).PSObject.Properties.Name |
                Where-Object {$_ -match '^StateFlags'} | ForEach-Object {
                    if (!$HashTable.$_) {
                        $HashTable.$_ = [ordered]@{Name=$_}
                    }
                
                    $HashTable.$_.$($CurrentItem.PSChildName) = switch ($CurrentProperty.$_) {
                                                                    0       {$false}
                                                                    2       {$true}
                                                                    default {$null}
                                                                }
                }
            }  -End {
                $HashTable.Keys | ForEach-Object {
                    New-Object -TypeName PSCustomObject -Property $Hashtable.$_
                }
            }
        }
    }
}

function Set-VolumeCachesStateFlags {
<#
.SYNOPSIS   
Set a StateFlags entry to the registry
    
.DESCRIPTION 
Creates a Stateflags entry for the specified switch parameters in order to automate the StateFlags creation. This function allows you to set this without using the GUI.

.NOTES   
Name       : Set-VolumeCachesStateFlags
Author     : Jaap Brasser
DateCreated: 2016-05-03
DateUpdated: 2016-05-03
Site       : http://www.jaapbrasser.com
Version    : 1.0.0
#>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory,
                   Position=0
        )]
        [ValidateRange(0,9999)]
        [int] $StateFlags
    )

    DynamicParam {
        $Attributes = New-Object System.Management.Automation.ParameterAttribute -Property @{
            ParameterSetName = '__AllParameterSets'
            Mandatory        = $false
        }
        $AttributeCollection = New-Object -Type System.Collections.ObjectModel.Collection[System.Attribute]
        $AttributeCollection.Add($Attributes)
        Get-VolumeCachesKey | Select-Object -ExpandProperty PSChildName | 
        Where-Object {$_ -notcontains @('Content Indexer Cleaner',
                                        'Delivery Optimization Files',
                                        'Device Driver Packages',
                                        'GameNewsFiles',
                                        'GameStatisticsFiles',
                                        'GameUpdateFiles',
                                        'Temporary Sync Files')
        } | ForEach-Object -Begin {
            $ParamDictionary = New-Object -Type System.Management.Automation.RuntimeDefinedParameterDictionary
        } -Process {
            $CurrentParameter = $_ -replace '\s'
            $DynParam1 = New-Object -Type System.Management.Automation.RuntimeDefinedParameter($CurrentParameter, [switch], $AttributeCollection)
            $ParamDictionary.Add($CurrentParameter, $DynParam1)
        } -End {
            $ParamDictionary -as [System.Management.Automation.RuntimeDefinedParameterDictionary]
        }        
    }

    begin {
        $StateFlagsName = 'StateFlags{0:D4}' -f $StateFlags
    }

    process {
        Get-VolumeCachesKey | Select-Object -ExpandProperty PSChildName | 
        Where-Object {$_ -notcontains @('Content Indexer Cleaner',
                                        'Delivery Optimization Files',
                                        'Device Driver Packages',
                                        'GameNewsFiles',
                                        'GameStatisticsFiles',
                                        'GameUpdateFiles',
                                        'Temporary Sync Files')
        } | ForEach-Object {
            $HashSplat = @{
                Path         = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\{0}' -f $_
                PropertyType = 'DWORD'
                Force        = $true
                Name         = $StateFlagsName
            }
            if ($PSBoundParameters.ContainsKey(($_ -replace '\s'))) {
                $HashSplat.Value = 0x2
                if ($PSCmdlet.ShouldProcess($_,"Setting registry REG_DWORD '$StateFlagsName' to enabled ")) {
                    $null = New-ItemProperty @HashSplat
                }
            } else {
                $HashSplat.Value = 0x0
                if ($PSCmdlet.ShouldProcess($_,"Setting registry REG_DWORD '$StateFlagsName' to disabled")) {
                    $null = New-ItemProperty @HashSplat
                }
            }
        }
    }
}

function Remove-WindowsUpgradeFiles {
<#
.SYNOPSIS   
Removes Temporary Setup Files and Previous Installations of Windows to reclaim diskspace
    
.DESCRIPTION 
Creates a Stateflags entry for and runs this afterwards. A GUI popup might still occur.

.NOTES   
Name       : Remove-WindowsUpgradeFiles
Author     : Jaap Brasser
DateCreated: 2016-05-03
DateUpdated: 2016-05-03
Site       : http://www.jaapbrasser.com
Version    : 1.1.0
#>
    [cmdletbinding(SupportsShouldProcess,
                   ConfirmImpact = 'High'
    )]
    param(
        [switch] $Force
    )

    begin {
        $Before = Get-CimInstance -Query "Select DeviceID,Size,FreeSpace FROM Win32_LogicalDisk WHERE DeviceID='$($env:SystemDrive)'"
        Write-Verbose -Message ('Cleaning the System Drive {0}' -f $Before.DeviceID)
        if ($Force) {
            $ConfirmPreference = 'None'
        }
    }
    
    process {
        Set-VolumeCachesStateFlags -TemporarySetupFiles -PreviousInstallations -StateFlags 1337

        $ProcessInfo             = New-Object System.Diagnostics.ProcessStartInfo
        $Process                 = New-Object System.Diagnostics.Process

        $ProcessInfo.FileName    = "$($env:SystemRoot)\system32\cleanmgr.exe"
        $ProcessInfo.Arguments   = '/SAGERUN:1337'
        $ProcessInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Normal
        $Process.StartInfo       = $ProcessInfo
        if ($PSCmdlet.ShouldProcess($env:ComputerName,'Removing Windows installation files and old version of Windows')) {
            $null = $Process.Start()
        }
    }

    end {
        $Process = Get-Process cleanmgr
        while ($($Process.Refresh();$Process.ProcessName)) {
            Start-Sleep -Milliseconds 500
        }
        $After = Get-CimInstance -Query "Select FreeSpace FROM Win32_LogicalDisk WHERE DeviceID='$($env:SystemDrive)'"
        [PSCustomObject]@{
            'DiskDeviceID'       = $Before.DeviceID
            'DiskSize'           = $Before.Size
            'FreeSpaceBefore'    = $Before.FreeSpace
            'FreeSpaceAfter'     = $After.FreeSpace
            'TotalCleanedUp'     = $After.FreeSpace - $Before.FreeSpace
            'TotalCleanedUp(GB)' = '{0:N2}' -f (($After.FreeSpace - $Before.FreeSpace)/1GB)
        }
    }
}