﻿<###################################################
 #                                                 #
 #  Copyright (c) Microsoft. All rights reserved.  #
 #                                                 #
 ##################################################>

<# 
    .SYNOPSIS 
       Report on Storage Cluster Health

    .DESCRIPTION 
       Show Storage Cluster Health information for major cluster and storage objects.
       Run from one of the nodes of the Storage Cluster or specify a cluster name.
       Results are saved to a folder (default C:\Users\<user>\HealthTest) for later review and replay.

    .LINK 
        To provide feedback and contribute visit https://github.com/PowerShell/Cloud.Health

    .EXAMPLE 
       Test-StorageHealth
 
       Reports on overall storage cluster health, capacity, performance and events.
       Uses the default temporary working folder at C:\Users\<user>\HealthTest
       Saves the zipped results at C:\Users\<user>\HealthTest-<cluster>-<date>.ZIP

    .EXAMPLE 
       Test-StorageHealth -WriteToPath C:\Test
 
       Reports on overall storage cluster health, capacity, performance and events.
       Uses the specified folder as the temporary working folder

    .EXAMPLE 
       Test-StorageHealth -ClusterName Cluster1
 
       Reports on overall storage cluster health, capacity, performance and events.
       Targets the storage cluster specified.

    .EXAMPLE 
       Test-StorageHealth -ReadFromPath C:\Test
 
       Reports on overall storage cluster health, capacity, performance and events.
       Results are obtained from the specified folder, not from a live cluster.

#> 

function Test-StorageHealth
{
[CmdletBinding(DefaultParameterSetName="Write")]

param(
    [parameter(ParameterSetName="Write", Position=0, Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string] $WriteToPath = $($env:userprofile + "\HealthTest\"),

    [parameter(ParameterSetName="Write", Position=1, Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string] $ClusterName = ".",

    [parameter(ParameterSetName="Write", Position=2, Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [string] $ZipPrefix = $($env:userprofile + "\HealthTest"),

    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [bool] $IncludeEvents = $true,
    
    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [bool] $IncludePerformance = $true,

    [parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [switch] $MonitoringMode,

    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int] $ExpectedNodes = 4,

    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int] $ExpectedNetworks = 2,

    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int] $ExpectedVolumes = 33,

    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int] $ExpectedDedupVolumes = 16,

    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int] $ExpectedPhysicalDisks = 240,

    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int] $ExpectedPools = 3,
    
    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int] $ExpectedEnclosures = 4,

    [parameter(ParameterSetName="Write", Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [int] $HoursOfEvents = 24,

    [parameter(ParameterSetName="Read", Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string] $ReadFromPath = ""
)

    #
    # Set strict mode to check typos on variable and property names
    #

    Set-StrictMode -Version Latest

    #
    # Shows error, cancels script
    #

    Function ShowError { 
    Param ([string] $Message)
        $Message = $Message + “ – cmdlet was cancelled”
        Write-Error $Message -ErrorAction Stop
    }
 
    #
    # Shows warning, script continues
    #

    Function ShowWarning { 
        Param ([string] $Message) 
        Write-Warning $Message 
    }

    #
    # Count number of elements in an array, including checks for $null or single object
    #

    Function NCount { 
        Param ([object] $Item) 
        If ($null -eq $Item) {
            $Result = 0
        } else {
            If ($Item.GetType().BaseType.Name -eq "Array") {
                $Result = ($Item).Count
            } Else { 
                $Result = 1
            }
        }
        Return $Result
    }

    Function VolumeToPath {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.VolumeID -eq $Volume) { $Result = $_.CSVPath }
             }
        Return $Result
    }

    Function VolumeToCSV {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.VolumeID -eq $Volume) { $Result = $_.CSVVolume }
    }
        Return $Result
    }

    Function VolumeToShare {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.VolumeID -eq $Volume) { $Result = $_.ShareName }
        }
        Return $Result
    }

    Function VolumeToResiliency {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.VolumeID -eq $Volume) { 
                $Result = $_.VDResiliency+","+$_.VDCopies
                If ($_.VDEAware) { 
                    $Result += ",E"
                } else {
                    $Result += ",NE"
                }
            }
        }
        Return $Result
    }

    Function VolumeToColumns {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.VolumeID -eq $Volume) { $Result = $_.VDColumns }
        }
        Return $Result
    }

    Function CSVToShare {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.CSVVolume -eq $Volume) { $Result = $_.ShareName }
        }
        Return $Result
    }

    Function CSVToPool {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.CSVVolume -eq $Volume) { $Result = $_.PoolName }
        }
        Return $Result
    }

    Function CSVToVD {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.CSVVolume -eq $Volume) { $Result = $_.FriendlyName }
        }
        Return $Result
    }

    Function CSVToNode {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.CSVVolume -eq $Volume) { $Result = $_.CSVNode }
        }
        Return $Result
    }

    Function CSVToName {
        Param ([String] $Volume) 
        if ($null -eq $Associations) { ShowError("No device associations present.") }
        $Result = ""
        $Associations | Foreach-Object {
            If ($_.CSVVolume -eq $Volume) { $Result = $_.CSVName }
        }
        Return $Result
    }

    Function PoolOperationalStatus {
        Param ([String] $PoolName)
        $poolOpStatus = ""
        If ($PoolName) {
            $poolOpStatus = (Get-StoragePool -FriendlyName $PoolName -CimSession $ClusterName).OperationalStatus
        }
        else {
            ShowError("No storage pool specified")
        }
        return $poolOpStatus
    }

    Function PoolHealthStatus {
        Param ([String] $PoolName)
        $poolHealthStatus = ""
        If ($PoolName) {
            $poolHealthStatus = (Get-StoragePool -FriendlyName $PoolName -CimSession $ClusterName).HealthStatus
        }
        else {
            ShowError("No storage pool specified")
        }
        return $poolHealthStatus    
    }

    Function PoolHealthyPDs {
        Param ([String] $PoolName)
        $healthyPDs = ""
        If ($PoolName) {
            $totalPDs = (Get-StoragePool -FriendlyName $PoolName -CimSession $ClusterName | Get-PhysicalDisk).Count
            $healthyPDs = (Get-StoragePool -FriendlyName $PoolName -CimSession $ClusterName | Get-PhysicalDisk | Where-Object HealthStatus -eq "Healthy" ).Count
        }
        else {
            ShowError("No storage pool specified")
        }
        return "$totalPDs/$healthyPDs"
    }

    Function VDOperationalStatus {
        Param ([String] $VDName)
        $VDOpStatus = ""
        If ($VDName) {
            $VDOpStatus = (Get-VirtualDisk -FriendlyName $VDName -CimSession $ClusterName).OperationalStatus
        }
        else {
            ShowError("No virtual disk specified")
        }
        return $VDOpStatus   
    }

    Function VDHealthStatus {
        Param ([String] $VDName)
        $VDHealthStatus = ""
        If ($VDName) {
            $VDHealthStatus = (Get-VirtualDisk -FriendlyName $VDName -CimSession $ClusterName).HealthStatus
        }
        else {
            ShowError("No virtual disk specified")
        }
        return $VDHealthStatus      
    }

    #
    # Veriyfing basic prerequisites on script node.
    #

    $OS = Get-CimInstance -ClassName Win32_OperatingSystem
    If ([uint64]$OS.BuildNumber -lt 9600) { 
        ShowError("Wrong OS Version - Need at least Windows Server 2012 R2 or Windows 8.1. You are running '" + $OS.Name + "'”) 
    }
 
    If (-not (Get-Command -Module FailoverClusters)) { 
        ShowError("Cluster PowerShell not available. Download the Windows Failover Clustering RSAT tools.") 
    }

    Function StartMonitoring {
        Write-Output "Entered continuous monitoring mode. Storage Infrastucture information will be refreshed every 3-6 minutes" -ForegroundColor Yellow    
        Write-Output "Press Ctrl + C to stop monitoring" -ForegroundColor Yellow

        Try { $ClusterName = (Get-Cluster -Name $ClusterName).Name }
        Catch { ShowError("Cluster could not be contacted. `nError="+$_.Exception.Message) }

        $AccessNode = (Get-ClusterNode -Cluster $ClusterName | Where-Object State -like "Up")[0].Name + "." + (Get-Cluster -Name $ClusterName).Domain

        Try { $Volumes = Get-Volume -CimSession $AccessNode  }
        Catch { ShowError("Unable to get Volumes. `nError="+$_.Exception.Message) }

        $AssocJob = Start-Job -ArgumentList $AccessNode,$ClusterName {

            param($AccessNode,$ClusterName)

            $SmbShares = Get-SmbShare -CimSession $AccessNode
            $Associations = Get-VirtualDisk -CimSession $AccessNode |Foreach-Object {

                $o = $_ | Select-Object FriendlyName, CSVName, CSVNode, CSVPath, CSVVolume, 
                ShareName, SharePath, VolumeID, PoolName, VDResiliency, VDCopies, VDColumns, VDEAware

                $AssocCSV = $_ | Get-ClusterSharedVolume -Cluster $ClusterName

	            If ($AssocCSV) {
                    $o.CSVName = $AssocCSV.Name
                    $o.CSVNode = $AssocCSV.OwnerNode.Name
                    $o.CSVPath = $AssocCSV.SharedVolumeInfo.FriendlyVolumeName
                    if ($o.CSVPath.Length -ne 0) {
                        $o.CSVVolume = $o.CSVPath.Split(“\”)[2]
                    }     
	                $AssocLike = $o.CSVPath+”\*”
	                $AssocShares = $SmbShares | Where-Object Path –like $AssocLike 
                    $AssocShare = $AssocShares | Select-Object -First 1
                    If ($AssocShare) {
	                    $o.ShareName = $AssocShare.Name
	                    $o.SharePath = $AssocShare.Path
	                    $o.VolumeID = $AssocShare.Volume
                        If ($AssocShares.Count -gt 1) { $o.ShareName += "*" }
                    }
                }

                Write-Output $o
            }

            $AssocPool = Get-StoragePool -CimSession $AccessNode
            $AssocPool | Foreach-Object {
	            $AssocPName = $_.FriendlyName
	            Get-StoragePool -CimSession $AccessNode –FriendlyName $AssocPName | 
                Get-VirtualDisk -CimSession $AccessNode | Foreach-Object {
		            $AssocVD = $_
		            $Associations | Foreach-Object {
                        If ($_.FriendlyName –eq $AssocVD.FriendlyName) { 
                            $_.PoolName = $AssocPName 
                            $_.VDResiliency = $AssocVD.ResiliencySettingName
                            $_.VDCopies = $AssocVD.NumberofDataCopies
                            $_.VDColumns = $AssocVD.NumberofColumns
                            $_.VDEAware = $AssocVD.IsEnclosureAware
                        }
                    }
                }
            }

            Write-Output $Associations
        }

        $Associations = $AssocJob | Wait-Job | Receive-Job
        $AssocJob | Remove-Job

        [System.Console]::Clear()

        $Volumes | Where-Object FileSystem -eq CSVFS | Sort-Object SizeRemaining | 
        Format-Table -AutoSize @{Expression={$poolName = CSVToPool(VolumeToCSV($_.Path)); $poolName + " [$(PoolOperationalStatus($poolName))/$(PoolHealthStatus($poolName))]"};Label="Pool [Op Status/Health Status]"}, 
        @{Expression={(PoolHealthyPDs(CSVToPool(VolumeToCSV($_.Path)))) + " Healthy"};Label="Pool PDs"}, 
        @{Expression={$vd = CSVToVD(VolumeToCSV($_.Path)); $vd + " [$(VDOperationalStatus($vd))/$(VDHealthStatus($vd))]"};Label="VirtualDisk [Op Status/Health Status]"}, 
        @{Expression={VolumeToCSV($_.Path)};Label="CSV Volume"},
        @{Expression={$csvName = CSVToName(VolumeToCSV($_.Path)); $csvStatus = (Get-ClusterSharedVolume -Name $csvName -Cluster $ClusterName).State; $csvName + " [$csvStatus]"};Label="CSV Name [Status]"}, 
        @{Expression={$csvOwner = CSVToNode(VolumeToCSV($_.Path)); $ownerState = (Get-ClusterNode -Name $csvOwner -Cluster $ClusterName).State;$csvOwner + " [$ownerState]"};Label="Volume Owner [State]"},  
        @{Expression={$_.HealthStatus};Label="Volume Health"}, 
        @{Expression={VolumeToShare($_.Path)};Label="Share Name"},    
        @{Expression={VolumeToResiliency($_.Path)};Label="Resiliency"}, 
        @{Expression={VolumeToColumns($_.Path)};Label="Cols"}, 
        @{Expression={"{0:N2}" -f ($_.Size/1GB)};Label="Total Size";Width=11;Align="Right"}, 
        @{Expression={"{0:N2}" -f ($_.SizeRemaining/1GB)};Label="Available";Width=11;Align="Right"}, 
        @{Expression={"{0:N2}" -f ($_.SizeRemaining/$_.Size*100)};Label="Avail%";Width=11;Align="Right"} 
        
        StartMonitoring
    }
    If ($MonitoringMode) {
        StartMonitoring 
    }

    #
    # Veriyfing path
    #

    If ($ReadFromPath -ne "") {
        $Path = $ReadFromPath
        $Read = $true
    } else {
        $Path = $WriteToPath
        $Read = $false
    }

    $PathOK = Test-Path $Path -ErrorAction SilentlyContinue
    If ($Read -and -not $PathOK) { ShowError ("Path not found: $Path") }
    If (-not $Read) {
        Remove-Item -Path $Path -ErrorAction SilentlyContinue -Recurse | Out-Null
        MKDIR -ErrorAction SilentlyContinue $Path | Out-Null
    } 
    $PathObject = Get-Item $Path
    If ($null -eq $PathObject) { ShowError ("Invalid Path: $Path") }
    $Path = $PathObject.FullName

    If ($Path.ToUpper().EndsWith(".ZIP")) {
        [Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
        $ExtractToPath = $Path.Substring(0, $Path.Length - 4)

        Try { [System.IO.Compression.ZipFile]::ExtractToDirectory($Path, $ExtractToPath) }
        Catch { ShowError("Can't extract results as Zip file from '$Path' to '$ExtractToPath'") }

        $Path = $ExtractToPath
    }

    If (-not $Path.EndsWith("\")) { $Path = $Path + "\" }

    # Start Transcript
    $transcriptFile = $Path + "0_CloudHealthSummary.log"
    Start-Transcript -Path $transcriptFile -Force

    If ($Read) { 
        "Reading from path : $Path"
    } else { 
        "Writing to path : $Path"
    }

<#
    If ($Read) {
        Try { $SavedVersion = Import-Clixml ($Path + "GetVersion.XML") }
        Catch { $SavedVersion = 1.1 }

        If ($SavedVersion -ne $ScriptVersion) 
        {ShowError("Files are from script version $SavedVersion, but the script is version $ScriptVersion")};
    } else {
        $ScriptVersion | Export-Clixml ($Path + "GetVersion.XML")
    }
#>
    #
    # Handle parameters
    #

    If ($Read) {
        $Parameters = Import-Clixml ($Path + "GetParameters.XML")
        $TodayDate = $Parameters.TodayDate
        $ExpectedNodes = $Parameters.ExpectedNodes
        $ExpectedNetworks = $Parameters.ExpectedNetworks
        $ExpectedVolumes = $Parameters.ExpectedVolumes
        $ExpectedPhysicalDisks = $Parameters.ExpectedPhysicalDisks
        $ExpectedPools = $Parameters.ExpectedPools
        $ExpectedEnclosures = $Parameters.ExpectedEnclosures
        $HoursOfEvents = $Parameters.HoursOfEvents

    } else {
        $Parameters = "" | Select-Object TodayDate, ExpectedNodes, ExpectedNetworks, ExpectedVolumes, 
        ExpectedPhysicalDisks, ExpectedPools, ExpectedEnclosures, HoursOfEvents
        $TodayDate = Get-Date
        $Parameters.TodayDate = $TodayDate
        $Parameters.ExpectedNodes = $ExpectedNodes
        $Parameters.ExpectedNetworks = $ExpectedNetworks 
        $Parameters.ExpectedVolumes = $ExpectedVolumes 
        $Parameters.ExpectedPhysicalDisks = $ExpectedPhysicalDisks
        $Parameters.ExpectedPools = $ExpectedPools
        $Parameters.ExpectedEnclosures = $ExpectedEnclosures
        $Parameters.HoursOfEvents = $HoursOfEvents
        $Parameters | Export-Clixml ($Path + "GetParameters.XML")
    }
    "Date of capture : " + $TodayDate

    #
    # Phase 1
    #

    "`n<<< Phase 1 - Storage Health Overview >>>`n"

    #
    # Get-Cluster
    #

    If ($Read) {
        $Cluster = Import-Clixml ($Path + "GetCluster.XML")
    } else {
        Try { $Cluster = Get-Cluster -Name $ClusterName }
        Catch { ShowError("Cluster could not be contacted. `nError="+$_.Exception.Message) }
        If ($null -eq $Cluster) { ShowError("Server is not in a cluster") }
        $Cluster | Export-Clixml ($Path + "GetCluster.XML")
    }

    $ClusterName = $Cluster.Name + "." + $Cluster.Domain
    "Cluster Name               : $ClusterName"
    
    #
    # Test if it's a scale-out file server
    #

    If ($Read) {
        $ClusterGroups = Import-Clixml ($Path + "GetClusterGroup.XML")
    } else {
        Try { $ClusterGroups = Get-ClusterGroup -Cluster $ClusterName }
        Catch { ShowError("Unable to get Cluster Groups. `nError="+$_.Exception.Message) }
        $ClusterGroups | Export-Clixml ($Path + "GetClusterGroup.XML")
    }

    $ScaleOutServers = $ClusterGroups | Where-Object GroupType -like "ScaleOut*"
    If ($null -eq $ScaleOutServers) { ShowError("No Scale-Out File Server cluster roles found") }
    $ScaleOutName = $ScaleOutServers[0].Name+"."+$Cluster.Domain
    "Scale-Out File Server Name : $ScaleOutName"

    #
    # Show health
    #

    # Cluster Nodes

    If ($Read) {
        $ClusterNodes = Import-Clixml ($Path + "GetClusterNode.XML")
    } else {
        Try { $ClusterNodes = Get-ClusterNode -Cluster $ClusterName }
        Catch { ShowError("Unable to get Cluster Nodes. `nError="+$_.Exception.Message) }
        $ClusterNodes | Export-Clixml ($Path + "GetClusterNode.XML")
    }

    # Select an access node, which will be used to query the cluster

    $AccessNode = ($ClusterNodes | Where-Object State -like "Up")[0].Name + "." + $Cluster.Domain
    "Access node                : $AccessNode `n"
    
    #
    # Verify deduplication prerequisites on access node, if in Write mode.
    #

    $DedupEnabled = $true
    if (-not $Read) {
        if ($(Invoke-Command -ComputerName $AccessNode {(-not (Get-Command -Module Deduplication))} )) { 
            $DedupEnabled = $false
            ShowWarning("Deduplication PowerShell not installed on cluster node.")
        }
    }

    # Gather association between pool, virtualdisk, volume, share.
    # This is first used at Phase 4 and is run asynchronously since
    # it can take some time to gather for large numbers of devices.

    If (-not $Read) {

        $AssocJob = Start-Job -ArgumentList $AccessNode,$ClusterName {

            param($AccessNode,$ClusterName)

            $SmbShares = Get-SmbShare -CimSession $AccessNode
            $Associations = Get-VirtualDisk -CimSession $AccessNode |Foreach-Object {

                $o = $_ | Select-Object FriendlyName, CSVName, CSVNode, CSVPath, CSVVolume, 
                ShareName, SharePath, VolumeID, PoolName, VDResiliency, VDCopies, VDColumns, VDEAware

                $AssocCSV = $_ | Get-ClusterSharedVolume -Cluster $ClusterName

	            If ($AssocCSV) {
                    $o.CSVName = $AssocCSV.Name
                    $o.CSVNode = $AssocCSV.OwnerNode.Name
                    $o.CSVPath = $AssocCSV.SharedVolumeInfo.FriendlyVolumeName
                    if ($o.CSVPath.Length -ne 0) {
                        $o.CSVVolume = $o.CSVPath.Split(“\”)[2]
                    }     
	                $AssocLike = $o.CSVPath+”\*”
	                $AssocShares = $SmbShares | Where-Object Path –like $AssocLike 
                    $AssocShare = $AssocShares | Select-Object -First 1
                    If ($AssocShare) {
	                    $o.ShareName = $AssocShare.Name
	                    $o.SharePath = $AssocShare.Path
	                    $o.VolumeID = $AssocShare.Volume
                        If ($AssocShares.Count -gt 1) { $o.ShareName += "*" }
                    }
                }

                Write-Output $o
            }

            $AssocPool = Get-StoragePool -CimSession $AccessNode
            $AssocPool | Foreach-Object {
	            $AssocPName = $_.FriendlyName
	            Get-StoragePool -CimSession $AccessNode –FriendlyName $AssocPName | 
                Get-VirtualDisk -CimSession $AccessNode | Foreach-Object {
		            $AssocVD = $_
		            $Associations | Foreach-Object {
                        If ($_.FriendlyName –eq $AssocVD.FriendlyName) { 
                            $_.PoolName = $AssocPName 
                            $_.VDResiliency = $AssocVD.ResiliencySettingName
                            $_.VDCopies = $AssocVD.NumberofDataCopies
                            $_.VDColumns = $AssocVD.NumberofColumns
                            $_.VDEAware = $AssocVD.IsEnclosureAware
                        }
                    }
                }
            }

            Write-Output $Associations
        }
    }

    # Cluster node health

    $NodesTotal = NCount($ClusterNodes)
    $NodesHealthy = NCount($ClusterNodes | Where-Object State -like "Up")
    "Cluster Nodes up              : $NodesHealthy / $NodesTotal"

    If ($NodesTotal -lt $ExpectedNodes) { ShowWarning("Fewer nodes than the $ExpectedNodes expected") }
    If ($NodesHealthy -lt $NodesTotal) { ShowWarning("Unhealthy nodes detected") }

    If ($Read) {
        $ClusterNetworks = Import-Clixml ($Path + "GetClusterNetwork.XML")
    } else {
        Try { $ClusterNetworks = Get-ClusterNetwork -Cluster $ClusterName }
        Catch { ShowError("Could not get Cluster Nodes. `nError="+$_.Exception.Message) }
        $ClusterNetworks | Export-Clixml ($Path + "GetClusterNetwork.XML")
    }

    # Cluster network health

    $NetsTotal = NCount($ClusterNetworks)
    $NetsHealthy = NCount($ClusterNetworks | Where-Object State -like "Up")
    "Cluster Networks up           : $NetsHealthy / $NetsTotal"
    

    If ($NetsTotal -lt $ExpectedNetworks) { ShowWarning("Fewer cluster networks than the $ExpectedNetworks expected") }
    If ($NetsHealthy -lt $NetsTotal) { ShowWarning("Unhealthy cluster networks detected") }

    If ($Read) {
        $ClusterResources = Import-Clixml ($Path + "GetClusterResource.XML")
    } else {
        Try { $ClusterResources = Get-ClusterResource -Cluster $ClusterName }
        Catch { ShowError("Unable to get Cluster Resources.  `nError="+$_.Exception.Message) }
        $ClusterResources | Export-Clixml ($Path + "GetClusterResource.XML")
    }

    # Cluster resource health

    $ResTotal = NCount($ClusterResources)
    $ResHealthy = NCount($ClusterResources | Where-Object State -like "Online")
    "Cluster Resources Online      : $ResHealthy / $ResTotal "
    If ($ResHealthy -lt $ResTotal) { ShowWarning("Unhealthy cluster resources detected") }

    If ($Read) {
        $CSV = Import-Clixml ($Path + "GetClusterSharedVolume.XML")
    } else {
        Try { $CSV = Get-ClusterSharedVolume -Cluster $ClusterName }
        Catch { ShowError("Unable to get Cluster Shared Volumes.  `nError="+$_.Exception.Message) }
        $CSV | Export-Clixml ($Path + "GetClusterSharedVolume.XML")
    }

    # Cluster shared volume health

    $CSVTotal = NCount($CSV)
    $CSVHealthy = NCount($CSV | Where-Object State -like "Online")
    "Cluster Shared Volumes Online : $CSVHealthy / $CSVTotal"
    If ($CSVHealthy -lt $CSVTotal) { ShowWarning("Unhealthy cluster shared volumes detected") }

    "`nHealthy Components count: [SMBShare -> CSV -> VirtualDisk -> StoragePool -> PhysicalDisk -> StorageEnclosure]"

    # SMB share health

    If ($Read) {
        $SmbShares = Import-Clixml ($Path + "GetSmbShare.XML")
        $ShareStatus = Import-Clixml ($Path + "ShareStatus.XML")
    } else {
        Try { $SmbShares = Get-SmbShare -CimSession $AccessNode }
        Catch { ShowError("Unable to get SMB Shares. `nError="+$_.Exception.Message) }

        $ShareStatus = $SmbShares | Where-Object ContinuouslyAvailable | Select-Object ScopeName, Name, SharePath, Health
        $Count1 = 0
        $Total1 = NCount($ShareStatus)

        If ($Total1 -gt 0)
        {
            $ShareStatus | Foreach-Object {
                $Progress = $Count1 / $Total1 * 100
                $Count1++
                Write-Progress -Activity "Testing file share access" -PercentComplete $Progress

                $_.SharePath = "\\"+$_.ScopeName+"."+$Cluster.Domain+"\"+$_.Name
                Try { If (Test-Path -Path $_.SharePath  -ErrorAction SilentlyContinue) {
                            $_.Health = "Accessible"
                        } else {
                            $_.Health = "Inaccessible" 
                    } 
                }
                Catch { $_.Health = "Accessible: "+$_.Exception.Message }
            }
            Write-Progress -Activity "Testing file share access" -Completed
        }

        #$SmbShares | Export-Clixml ($Path + "GetSmbShare.XML")
        $ShareStatus | Export-Clixml ($Path + "ShareStatus.XML")

    }

    $ShTotal = NCount($ShareStatus)
    $ShHealthy = NCount($ShareStatus | Where-Object Health -like "Accessible")
    "SMB CA Shares Accessible      : $ShHealthy / $ShTotal"
    If ($ShHealthy -lt $ShTotal) { ShowWarning("Inaccessible CA shares detected") }

    # Open files 

    If ($Read) {
        $SmbOpenFiles = Import-Clixml ($Path + "GetSmbOpenFile.XML")
    } else {
        Try { $SmbOpenFiles = Get-SmbOpenFile -CimSession $AccessNode }
        Catch { ShowError("Unable to get Open Files. `nError="+$_.Exception.Message) }
        $SmbOpenFiles | Export-Clixml ($Path + "GetSmbOpenFile.XML")
    }

    $FileTotal = NCount( $SmbOpenFiles | Group-Object ClientComputerName)
    "Users with Open Files         : $FileTotal"
    If ($FileTotal -eq 0) { ShowWarning("No users with open files") }

    # SMB witness

    If ($Read) {
        $SmbWitness = Import-Clixml ($Path + "GetSmbWitness.XML")
    } else {
        Try { $SmbWitness = Get-SmbWitnessClient -CimSession $AccessNode }
        Catch { ShowError("Unable to get Open Files. `nError="+$_.Exception.Message) }
        $SmbWitness | Export-Clixml ($Path + "GetSmbWitness.XML")
    }

    $WitTotal = NCount($SmbWitness | Where-Object State -eq RequestedNotifications | Group-Object ClientName)
    "sers with a Witness           : $WitTotal"
    If ($WitTotal -eq 0) { ShowWarning("No users with a Witness") }

    # Volume health

    If ($Read) {
        $Volumes = Import-Clixml ($Path + "GetVolume.XML")
    } else {
        Try { $Volumes = Get-Volume -CimSession $AccessNode  }
        Catch { ShowError("Unable to get Volumes. `nError="+$_.Exception.Message) }
        $Volumes | Export-Clixml ($Path + "GetVolume.XML")
    }

    $VolsTotal = NCount($Volumes | Where-Object FileSystem -eq CSVFS )
    $VolsHealthy = NCount($Volumes  | Where-Object FileSystem -eq CSVFS | Where-Object { ($_.HealthStatus -like "Healthy") -or ($_.HealthStatus -eq 0) })
    "Cluster Shared Volumes Healthy: $VolsHealthy / $VolsTotal "

    # Deduplicated volume health

    If ($DedupEnabled)
    {
        If ($Read) {
            $DedupVolumes = Import-Clixml ($Path + "GetDedupVolume.XML")
        } else {
            Try { $DedupVolumes = Invoke-Command -ComputerName $AccessNode { Get-DedupStatus }}
            Catch { ShowError("Unable to get Dedup Volumes. `nError="+$_.Exception.Message) }
            $DedupVolumes | Export-Clixml ($Path + "GetDedupVolume.XML")
        }

        $DedupTotal = NCount($DedupVolumes)
        $DedupHealthy = NCount($DedupVolumes | Where-Object LastOptimizationResult -eq 0 )
        "Dedup Volumes Healthy         : $DedupHealthy / $DedupTotal "

        If ($DedupTotal -lt $ExpectedDedupVolumes) { ShowWarning("Fewer Dedup volumes than the $ExpectedDedupVolumes expected") }
        If ($DedupHealthy -lt $DedupTotal) { ShowWarning("Unhealthy Dedup volumes detected") }
    } else {
        $DedupVolumes = @()
        $DedupTotal = 0
        $DedupHealthy = 0
        If (-not $Read) { $DedupVolumes | Export-Clixml ($Path + "GetDedupVolume.XML") }
    }

    # Virtual disk health

    If ($Read) {
        $VirtualDisks = Import-Clixml ($Path + "GetVirtualDisk.XML")
    } else {
        Try { $SubSystem = Get-StorageSubsystem Cluster* -CimSession $AccessNode
              $VirtualDisks = Get-VirtualDisk -CimSession $AccessNode -StorageSubSystem $SubSystem }
        Catch { ShowError("Unable to get Virtual Disks. `nError="+$_.Exception.Message) }
        $VirtualDisks | Export-Clixml ($Path + "GetVirtualDisk.XML")
    }

    $VDsTotal = NCount($VirtualDisks)
    $VDsHealthy = NCount($VirtualDisks | Where-Object { ($_.HealthStatus -like "Healthy") -or ($_.HealthStatus -eq 0) } )
    "Virtual Disks Healthy         : $VDsHealthy / $VDsTotal"

    If ($VDsHealthy -lt $VDsTotal) { ShowWarning("Unhealthy virtual disks detected") }

    # Storage pool health

    If ($Read) {
        $StoragePools = Import-Clixml ($Path + "GetStoragePool.XML")
    } else {
        Try { $SubSystem = Get-StorageSubsystem Cluster* -CimSession $AccessNode
              $StoragePools =Get-StoragePool -IsPrimordial $False -CimSession $AccessNode -StorageSubSystem $SubSystem }
        Catch { ShowError("Unable to get Storage Pools. `nError="+$_.Exception.Message) }
        $StoragePools | Export-Clixml ($Path + "GetStoragePool.XML")
    }

    $PoolsTotal = NCount($StoragePools)
    $PoolsHealthy = NCount($StoragePools | Where-Object { ($_.HealthStatus -like "Healthy") -or ($_.HealthStatus -eq 0) } )
    "Storage Pools Healthy         : $PoolsHealthy / $PoolsTotal "

    If ($PoolsTotal -lt $ExpectedPools) { ShowWarning("Fewer storage pools than the $ExpectedPools expected") }
    If ($PoolsHealthy -lt $PoolsTotal) { ShowWarning("Unhealthy storage pools detected") }

    # Physical disk health

    If ($Read) {
        $PhysicalDisks = Import-Clixml ($Path + "GetPhysicalDisk.XML")
    } else {
        Try { $SubSystem = Get-StorageSubsystem Cluster* -CimSession $AccessNode
              $PhysicalDisks = Get-PhysicalDisk -CimSession $AccessNode -StorageSubSystem $SubSystem }
        Catch { ShowError("Unable to get Physical Disks. `nError="+$_.Exception.Message) }
        $PhysicalDisks | Export-Clixml ($Path + "GetPhysicalDisk.XML")
    }

    $PDsTotal = NCount($PhysicalDisks)
    $PDsHealthy = NCount($PhysicalDisks | Where-Object { ($_.HealthStatus -like "Healthy") -or ($_.HealthStatus -eq 0) } )
    "Physical Disks Healthy        : $PDsHealthy / $PDsTotal"

    If ($PDsTotal -lt $ExpectedPhysicalDisks) { ShowWarning("Fewer physical disks than the $ExpectedPhysicalDisks expected") }
    If ($PDsHealthy -lt $PDsTotal) { ShowWarning("Unhealthy physical disks detected") }

    # Reliability counters

    If ($Read) {
        $ReliabilityCounters = Import-Clixml ($Path + "GetReliabilityCounter.XML")
    } else {
        Try { $SubSystem = Get-StorageSubsystem Cluster* -CimSession $AccessNode
              $ReliabilityCounters = $PhysicalDisks | Get-StorageReliabilityCounter -CimSession $AccessNode }
        Catch { ShowError("Unable to get Storage Reliability Counters. `nError="+$_.Exception.Message) }
        $ReliabilityCounters | Export-Clixml ($Path + "GetReliabilityCounter.XML")
    }

    # Storage enclosure health - only performed if the required KB is present

    If (-not (Get-Command *StorageEnclosure*)) {
        ShowWarning("Storage Enclosure commands not available. See http://support.microsoft.com/kb/2913766/en-us")
    } else {
        If ($Read) {
            If (Test-Path ($Path + "GetStorageEnclosure.XML") -ErrorAction SilentlyContinue ) {
               $StorageEnclosures = Import-Clixml ($Path + "GetStorageEnclosure.XML")
            } Else {
               $StorageEnclosures = ""
            }
        } else {
            Try { $SubSystem = Get-StorageSubsystem Cluster* -CimSession $AccessNode
                  $StorageEnclosures = Get-StorageEnclosure -CimSession $AccessNode -StorageSubSystem $SubSystem }
            Catch { ShowError("Unable to get Enclosures. `nError="+$_.Exception.Message) }
            $StorageEnclosures | Export-Clixml ($Path + "GetStorageEnclosure.XML")
        }

        $EncsTotal = NCount($StorageEnclosures)
        $EncsHealthy = NCount($StorageEnclosures | Where-Object { ($_.HealthStatus -like "Healthy") -or ($_.HealthStatus -eq 0) } )
        "Storage Enclosures Healthy    : $EncsHealthy / $EncsTotal "

        If ($EncsTotal -lt $ExpectedEnclosures) { ShowWarning("Fewer storage enclosures than the $ExpectedEnclosures expected") }
        If ($EncsHealthy -lt $EncsTotal) { ShowWarning("Unhealthy storage enclosures detected") }
    }   

    #
    # Phase 2
    #

    "`n<<< Phase 2 - details on unhealthy components >>>`n"

    $Failed = $False

    If ($NodesTotal -ne $NodesHealthy) { 
        $Failed = $true; 
        "Cluster Nodes:"; 
        $ClusterNodes | Where-Object State -ne "Up" | Format-Table -AutoSize 
    }

    If ($NetsTotal -ne $NetsHealthy) { 
        $Failed = $true; 
        "Cluster Networks:"; 
        $ClusterNetworks | Where-Object State -ne "Up" | Format-Table -AutoSize 
    }

    If ($ResTotal -ne $ResHealthy) { 
        $Failed = $true; 
        "Cluster Resources:"; 
        $ClusterResources | Where-Object State -notlike "Online" | Format-Table -AutoSize 
    }

    If ($CSVTotal -ne $CSVHealthy) { 
        $Failed = $true; 
        "Cluster Shared Volumes:"; 
        $CSV | Where-Object State -ne "Online" | Format-Table -AutoSize 
    }

    If ($VolsTotal -ne $VolsHealthy) { 
        $Failed = $true; 
        "Volumes:"; 
        $Volumes | Where-Object { ($_.HealthStatus -notlike "Healthy") -and ($_.HealthStatus -ne 0) }  | 
        Format-Table Path, HealthStatus  -AutoSize
    }

    If ($DedupTotal -ne $DedupHealthy) { 
        $Failed = $true; 
        "Volumes:"; 
        $DedupVolumes | Where-Object LastOptimizationResult -eq 0 | 
        Format-Table Volume, Capacity, SavingsRate, LastOptimizationResultMessage -AutoSize
    }

    If ($VDsTotal -ne $VDsHealthy) { 
        $Failed = $true; 
        "Virtual Disks:"; 
        $VirtualDisks | Where-Object { ($_.HealthStatus -notlike "Healthy") -and ($_.HealthStatus -ne 0) } | 
        Format-Table FriendlyName, HealthStatus, OperationalStatus, ResiliencySettingName, IsManualAttach  -AutoSize 
    }

    If ($PoolsTotal -ne $PoolsHealthy) { 
        $Failed = $true; 
        "Storage Pools:"; 
        $StoragePools | Where-Object { ($_.HealthStatus -notlike "Healthy") -and ($_.HealthStatus -ne 0) } | 
        Format-Table FriendlyName, HealthStatus, OperationalStatus, IsReadOnly -AutoSize 
    }

    If ($PDsTotal -ne $PDsHealthy) { 
        $Failed = $true; 
        "Physical Disks:"; 
        $PhysicalDisks | Where-Object { ($_.HealthStatus -notlike "Healthy") -and ($_.HealthStatus -ne 0) } | 
        Format-Table FriendlyName, EnclosureNumber, SlotNumber, HealthStatus, OperationalStatus, Usage -AutoSize
    }

    If (Get-Command *StorageEnclosure*)
    {
        If ($EncsTotal -ne $EncsHealthy) { 
            $Failed = $true; "Enclosures:";
            $StorageEnclosures | Where-Object { ($_.HealthStatus -notlike "Healthy") -and ($_.HealthStatus -ne 0) } | 
            Format-Table FriendlyName, HealthStatus, ElementTypesInError -AutoSize 
        }
    }

    If ($ShTotal -ne $ShHealthy) { 
        $Failed = $true; 
        "CA Shares:";
        $ShareStatus | Where-Object Health -notlike "Healthy" | Format-Table -AutoSize
    }

    If (-not $Failed) { 
        "`nNo unhealthy components" 
    }

    #
    # Phase 3
    #

    "`n<<< Phase 3 - Firmware and drivers >>>`n"

    "Devices and drivers by Model and Driver Version per cluster node" 

    If ($Read) {
        $Drivers = Import-Clixml ($Path + "GetDrivers.XML") 
    } else {
        $clusterNodeNames = (Get-ClusterNode -Cluster $ClusterName).Name
        foreach ($node in $clusterNodeNames) { 
            "`nCluster Node: $node"
            Try { $Drivers = Get-CimInstance -ClassName Win32_PnPSignedDriver -ComputerName $node }
            Catch { ShowError("Unable to get Drivers on node $nod. `nError="+$_.Exception.Message) }
            $Drivers | Export-Clixml ($Path + $node + "_GetDrivers.XML")
            $RelevantDrivers = $Drivers | Where-Object { ($_.DeviceName -like "LSI*") -or ($_.DeviceName -like "Mellanox*") -or ($_.DeviceName -like "Chelsio*") } | 
            Group-Object DeviceName, DriverVersion | 
            Select-Object @{Expression={$_.Name};Label="Device Name, Driver Version"}
            $RelevantDrivers
        }
    }

    "`nPhysical disks by Media Type, Model and Firmware Version" 
    $PhysicalDisks | Group-Object MediaType, Model, FirmwareVersion | Format-Table Count, @{Expression={$_.Name};Label="Media Type, Model, Firmware Version"} –AutoSize

 
    If ( -not (Get-Command *StorageEnclosure*) ) {
        ShowWarning("Storage Enclosure commands not available. See http://support.microsoft.com/kb/2913766/en-us")
    } else {
        "Storage Enclosures by Model and Firmware Version"
        $StorageEnclosures | Group-Object Model, FirmwareVersion | Format-Table Count, @{Expression={$_.Name};Label="Model, Firmware Version"} –AutoSize
    }
    
    #
    # Phase 4 Prep
    #

    "`n<<< Phase 4 - Pool, Physical Disk and Volume Details >>>"

    if ($Read) {
        $Associations = Import-Clixml ($Path + "GetAssociations.XML")
    } else {

        "`nCollecting device associations..."

        $Associations = $AssocJob | Wait-Job | Receive-Job
        $AssocJob | Remove-Job

        if ($null -eq $Associations) {
            ShowError("Unable to get object associations")
        }

        $Associations | Export-Clixml ($Path + "GetAssociations.XML")
    }

    #
    # Phase 4
    #

    "`n[Health Report]"
    "Volumes with status, total size and available size, sorted by Available Size" 
    "Notes: Sizes shown in gigabytes (GB). * means multiple shares on that volume"

    $Volumes | Where-Object FileSystem -eq CSVFS | Sort-Object SizeRemaining | 
    Format-Table -AutoSize @{Expression={$poolName = CSVToPool(VolumeToCSV($_.Path)); "[$(PoolOperationalStatus($poolName))/$(PoolHealthStatus($poolName))] " + $poolName};Label="[OpStatus/Health] Pool"}, 
    @{Expression={(PoolHealthyPDs(CSVToPool(VolumeToCSV($_.Path))))};Label="HealthyPhysicalDisks"}, 
    @{Expression={$vd = CSVToVD(VolumeToCSV($_.Path));  "[$(VDOperationalStatus($vd))/$(VDHealthStatus($vd))] "+$vd};Label="[OpStatus/Health] VirtualDisk"}, 
    @{Expression={$csvVolume = VolumeToCSV($_.Path); "[" + $_.HealthStatus + "} " + $csvVolume};Label="[Health] CSV Volume"},
    @{Expression={$csvName = CSVToName(VolumeToCSV($_.Path)); $csvStatus = (Get-ClusterSharedVolume -Name $csvName -Cluster $ClusterName).State;  " [$csvStatus] " + $csvName};Label="[Status] CSV Name"}, 
    @{Expression={$csvOwner = CSVToNode(VolumeToCSV($_.Path)); $ownerState = (Get-ClusterNode -Name $csvOwner -Cluster $ClusterName).State; " [$ownerState] " + $csvOwner};Label="[State] Volume Owner"},   
    @{Expression={VolumeToShare($_.Path)};Label="Share Name"}, 
    @{Expression={$VolResiliency = VolumeToResiliency($_.Path); $volColumns = VolumeToColumns($_.Path); "$VolResiliency,$volColumns" +"Col" };Label="Volume Configuration"},        
    @{Expression={"{0:N2}" -f ($_.Size/1GB)};Label="Total Size";Width=11;Align="Right"},  
    @{Expression={"{0:N2}" -f ($_.SizeRemaining/$_.Size*100)};Label="Avail%";Width=11;Align="Right"} 

    If ($DedupEnabled -and ($DedupTotal -gt 0))
    {
        "Dedup Volumes with status, total size and available size, sorted by Savings %" 
        "Notes: Sizes shown in gigabytes (GB). * means multiple shares on that volume"

        $DedupVolumes | Sort-Object SavingsRate -Descending | 
        Format-Table -AutoSize @{Expression={$poolName = CSVToPool(VolumeToCSV($_.VolumeId)); "[$(PoolOperationalStatus($poolName))/$(PoolHealthStatus($poolName))] " + $poolName};Label="[OpStatus/Health] Pool"}, 
        @{Expression={$healthyPDS = (PoolHealthyPDs(CSVToPool(VolumeToCSV($_.VolumeId)))); $healthyPDS};Label="HealthyPhysicalDisks"}, 
        @{Expression={$vd = CSVToVD(VolumeToCSV($_.VolumeId)); "[$(VDOperationalStatus($vd))/$(VDHealthStatus($vd))] " + $vd};Label="[OpStatus/Health] VirtualDisk"}, 
        @{Expression={VolumeToCSV($_.VolumeId)};Label="Volume "},
        @{Expression={VolumeToShare($_.VolumeId)};Label="Share"},
        @{Expression={"{0:N2}" -f ($_.Capacity/1GB)};Label="Capacity";Width=11;Align="Left"}, 
        @{Expression={"{0:N2}" -f ($_.UnoptimizedSize/1GB)};Label="Before";Width=11;Align="Right"}, 
        @{Expression={"{0:N2}" -f ($_.UsedSpace/1GB)};Label="After";Width=11;Align="Right"}, 
        @{Expression={"{0:N2}" -f ($_.SavingsRate)};Label="Savings%";Width=11;Align="Right"}, 
        @{Expression={"{0:N2}" -f ($_.FreeSpace/1GB)};Label="Free";Width=11;Align="Right"}, 
        @{Expression={"{0:N2}" -f ($_.FreeSpace/$_.Capacity*100)};Label="Free%";Width=11;Align="Right"},
        @{Expression={"{0:N0}" -f ($_.InPolicyFilesCount)};Label="Files";Width=11;Align="Right"}
    }


    "`n[Capacity Report]"
    "Physical disks by Enclosure, Media Type and Health Status, with total and unallocated space" 
    "Note: Sizes shown in gigabytes (GB)"

    $PDStatus = $PhysicalDisks | Where-Object EnclosureNumber –ne $null | 
    Sort-Object EnclosureNumber, MediaType, HealthStatus |  
    Group-Object EnclosureNumber, MediaType, HealthStatus | 
    Select-Object Count, TotalSize, Unalloc, 
    @{Expression={$_.Name.Split(",")[0].Trim().TrimEnd()}; Label="Enc"},
    @{Expression={$_.Name.Split(",")[1].Trim().TrimEnd()}; Label="Media"},
    @{Expression={$_.Name.Split(",")[2].Trim().TrimEnd()}; Label="Health"}

    $PDStatus | Foreach-Object {
        $Current = $_
        $TotalSize = 0
        $Unalloc = 0
        $PDCurrent = $PhysicalDisks | Where-Object { ($_.EnclosureNumber -eq $Current.Enc) -and ($_.MediaType -eq $Current.Media) -and ($_.HealthStatus -eq $Current.Health) }
        $PDCurrent | Foreach-Object {
            $Unalloc += $_.Size - $_.AllocatedSize
            $TotalSize +=$_.Size
        }
        
        $Current.Unalloc = $Unalloc
        $Current.TotalSize = $TotalSize
    }

    $PDStatus | Format-Table -AutoSize Enc, Media, Health, Count, 
    @{Expression={"{0:N2}" -f ($_.TotalSize/$_.Count/1GB)};Label="Avg Size";Width=11;Align="Right"}, 
    @{Expression={"{0:N2}" -f ($_.TotalSize/1GB)};Label="Total Size";Width=11;Align="Right"}, 
    @{Expression={"{0:N2}" -f ($_.Unalloc/1GB)};Label="Unallocated";Width=11;Align="Right"},
    @{Expression={"{0:N2}" -f ($_.Unalloc/$_.TotalSize*100)};Label="Unalloc %";Width=11;Align="Right"} 

    "Pools with health, total size and unallocated space" 
    "Note: Sizes shown in gigabytes (GB)"

    $StoragePools | Sort-Object FriendlyName | 
    Format-Table -AutoSize @{Expression={$_.FriendlyName};Label="Name"}, 
    @{Expression={$_.HealthStatus};Label="Health"}, 
    @{Expression={"{0:N2}" -f ($_.Size/1GB)};Label="Total Size";Width=11;Align="Right"}, 
    @{Expression={"{0:N2}" -f (($_.Size-$_.AllocatedSize)/1GB)};Label="Unallocated";Width=11;Align="Right"}, 
    @{Expression={"{0:N2}" -f (($_.Size-$_.AllocatedSize)/$_.Size*100)};Label="Unalloc%";Width=11;Align="Right"} 

    #
    # Phase 5
    #

    "<<< Phase 5 - Storage Performance >>>`n"

    If ((-not $Read) -and (-not $IncludePerformance)) {
       "Performance was excluded by a parameter`n"
    }

    If ((-not $Read) -and $IncludePerformance) {

        $PerfSamples = 60 
        "Please wait for $PerfSamples seconds while performance samples are collected."

        $PerfNodes = $ClusterNodes | Where-Object State -like "Up" | Foreach-Object {$_.Name}
        $PerfCounters = “reads/sec”, “writes/sec” , “read latency”, “write latency” 
        $PerfItems = $PerfNodes | Foreach-Object { $Node=$_; $PerfCounters | Foreach-Object { (”\\”+$Node+”\Cluster CSV File System(*)\”+$_) } }
        $PerfRaw = Get-Counter -Counter $PerfItems -SampleInterval 1 -MaxSamples $PerfSamples

        "Collected $PerfSamples seconds of raw performance counters. Processing...`n"

        $Count1 = 0
        $Total1 = $PerfRaw.Count

        If ($Total1 -gt 0) {

            $PerfDetail = $PerfRaw | Foreach-Object { 
                $TimeStamp = $_.TimeStamp
        
                $Progress = $Count1 / $Total1 * 45
                $Count1++
                Write-Progress -Activity "Processing performance samples" -PercentComplete $Progress

                $_.CounterSamples | Foreach-Object { 
                    $DetailRow = “” | Select-Object Time, Pool, Owner, Node, Volume, Share, Counter, Value
                    $Split = $_.Path.Split(“\”)
                    $DetailRow.Time = $TimeStamp
                    $DetailRow.Node = $Split[2]
                    $DetailRow.Volume = $_.InstanceName
                    $DetailRow.Counter = $Split[4]
                    $DetailRow.Value = $_.CookedValue
                    $DetailRow
                } 
            }

            Write-Progress -Activity "Processing performance samples" -PercentComplete 50
            $PerfDetail = $PerfDetail | Sort-Object Volume

            $Last = $PerfDetail.Count - 1
            $Volume = “”
    
            $PerfVolume = 0 .. $Last | Foreach-Object {

                If ($Volume –ne $PerfDetail[$_].Volume) {
                    $Volume = $PerfDetail[$_].Volume
                    $Pool = CSVToPool ($Volume)
                    $Owner = CSVToNode ($Volume)
                    $Share = CSVToShare ($Volume)
                    $ReadIOPS = 0
                    $WriteIOPS = 0
                    $ReadLatency = 0
                    $WriteLatency = 0
                    $NonZeroRL = 0
                    $NonZeroWL = 0

                    $Progress = 55 + ($_ / $Last * 45 )
                    Write-Progress -Activity "Processing performance samples" -PercentComplete $Progress
                }

                $PerfDetail[$_].Pool = $Pool
                $PerfDetail[$_].Owner = $Owner
                $PerfDetail[$_].Share = $Share

                $Value = $PerfDetail[$_].Value

                Switch ($PerfDetail[$_].Counter) {
                    “reads/sec” { $ReadIOPS += $Value }
                    “writes/sec” { $WriteIOPS += $Value }
                    “read latency” { $ReadLatency += $Value; If ($Value -gt 0) {$NonZeroRL++} }
                    “write latency” { $WriteLatency += $Value; If ($Value -gt 0) {$NonZeroWL++} }
                    default { Write-Warning “Invalid counter” }
                }

                If ($_ -eq $Last) { 
                    $EndofVolume = $true 
                } else { 
                    If ($Volume –ne $PerfDetail[$_+1].Volume) { 
                        $EndofVolume = $true 
                    } else { 
                        $EndofVolume = $false 
                    }
                }

                If ($EndofVolume) {
                    $VolumeRow = “” | Select-Object Pool, Volume, Share, ReadIOPS, WriteIOPS, TotalIOPS, ReadLatency, WriteLatency, TotalLatency
                    $VolumeRow.Pool = $Pool
                    $VolumeRow.Volume = $Volume
                    $VolumeRow.Share = $Share
                    $VolumeRow.ReadIOPS = [int] ($ReadIOPS / $PerfSamples *  10) / 10
                    $VolumeRow.WriteIOPS = [int] ($WriteIOPS / $PerfSamples * 10) / 10
                    $VolumeRow.TotalIOPS = $VolumeRow.ReadIOPS + $VolumeRow.WriteIOPS
                    If ($NonZeroRL -eq 0) {$NonZeroRL = 1}
                    $VolumeRow.ReadLatency = [int] ($ReadLatency / $NonZeroRL * 1000000 ) / 1000 
                    If ($NonZeroWL -eq 0) {$NonZeroWL = 1}
                    $VolumeRow.WriteLatency = [int] ($WriteLatency / $NonZeroWL * 1000000 ) / 1000
                    $VolumeRow.TotalLatency = [int] (($ReadLatency + $WriteLatency) / ($NonZeroRL + $NonZeroWL) * 1000000) / 1000
                    $VolumeRow
                 }
            }
    
        } else {
            ShowWarning("Unable to collect performance information")
            $PerfVolume = @()
            $PerfDetail = @()
        }

        $PerfVolume | Export-Clixml ($Path + "GetVolumePerf.XML")
        $PerfDetail | Export-Csv ($Path + "VolumePerformanceDetails.TXT")
    }

    If ($Read) { 
        Try { $PerfVolume = Import-Clixml ($Path + "GetVolumePerf.XML") }
        Catch { $PerfVolume = @() }
    }

    If ($Read -or $IncludePerformance) {

        If (-not $PerfVolume) {
            "No storage performance information found" 
        } Else { 
        
            "Storage Performance per Volume, sorted by Latency"
            "Notes: Latencies in milliseconds (ms). * means multiple shares on that volume`n"

            $PerfVolume | Sort-Object TotalLatency -Descending | Select-Object * -ExcludeProperty TotalL* | Format-Table –AutoSize 
        }
    }

    #
    # Phase 6
    #

    "<<< Phase 6 - Recent Error events >>>`n"

    If ((-not $Read) -and (-not $IncludeEvents)) {
       "Events were excluded by a parameter`n"
    }

    If ((-not $Read) -and $IncludeEvents) {

        "Starting Export of Cluster Logs..." 

        # Cluster log collection will take some time. 
        # Using Start-Job to run them in the background, while we collect events and other diagnostic information

        $ClusterLogJob = Start-Job -ArgumentList $ClusterName,$Path { 
            param($c,$p) Get-ClusterLog -Cluster $c -Destination $p 
        }

        "Exporting Event Logs..." 

        $AllErrors = @();
        $Logs = Invoke-Command -ArgumentList $HoursOfEvents -ComputerName $($ClusterNodes | Where-Object State -like "Up") {

            Param([int] $Hours)
            # Calculate number of milliseconds and prepare the WEvtUtil parameter to filter based on date/time
            $MSecs = $Hours * 60 * 60 * 1000
            $QParameter = "*[System[(Level=2) and TimeCreated[timediff(@SystemTime) <= "+$MSecs+"]]]"
            $QParameterUnfiltered = "*[System[TimeCreated[timediff(@SystemTime) <= "+$MSecs+"]]]"

            $Node = $env:COMPUTERNAME
            $NodePath = [System.IO.Path]::GetTempPath()
            $RPath = "\\"+$Node+"\"+$NodePath.Substring(0,1)+"$\"+$NodePath.Substring(3,$NodePath.Length-3)

            $LogPatterns = 'Storage','SMB','Failover','VHDMP','Hyper-V','ResumeKeyFilter','Witness','PnP','Space','NTFS','storport','disk','Kernel' | Foreach-Object { "*$_*" }
            $LogPatterns += 'System','Application'

            $Logs = Get-WinEvent -ListLog $LogPatterns -ComputerName $Node | Where-Object LogName -NotLike "*Diag*" 
            $Logs | Foreach-Object {
        
                $FileSuffix = $Node+"_Event_"+$_.LogName.Replace("/","-")+".EVTX"
                $NodeFile = $NodePath+$FileSuffix
                $RFile = $RPath+$FileSuffix

                # Export filtered log file using the WEvtUtil command-line tool
                # This includes filtering the events to errors (Level=2) that happened in recent hours.

                WEvtUtil.exe epl $_.LogName $NodeFile /q:$QParameter /ow:true
                Write-Output $RFile
            }

            $Logs | Foreach-Object {
        
                $UnfilteredFileSuffix = $Node+"_UnfilteredEvent_"+$_.LogName.Replace("/","-")+".EVTX"
                $UnfilteredNodeFile = $NodePath+$UnfilteredFileSuffix
                $UnfilteredRFile = $RPath+$UnfilteredFileSuffix

                # Export unfiltered log file using the WEvtUtil command-line tool
            
                WEvtUtil.exe epl $_.LogName $UnfilteredNodeFile /q:$QParameterUnfiltered /ow:true
                Write-Output $UnfilteredRFile
            }
        }

        "Copying Event Logs...."

        $Logs |Foreach-Object {
            # Copy event log files and remove them from the source
            Copy-Item $_ $Path -Force -ErrorAction SilentlyContinue
            Remove-Item $_ -Force -ErrorAction SilentlyContinue
        }

        "Processing Event Logs..." 

        $Files = Get-ChildItem ($Path+"\*_Event_*.EVTX") | Sort-Object Name

        If ($Files) {

            $Total1 = $Files.Count
            #$E = "" | Select-Object MachineName, LogName, EventID, Count
            $ErrorFound = $false
            $Count1 = 0

            $Files | Foreach-Object {
                Write-Progress -Activity "Processing Event Logs - Reading in" -PercentComplete ($Count1 / $Total1 * 100)
                $Count1++

                $ErrorEvents = Get-WinEvent -Path $_ -ErrorAction SilentlyContinue | 
                Sort-Object MachineName, LogName, Id | Group-Object MachineName, LogName, Id 

                If ($ErrorEvents) {
                     $ErrorEvents | Foreach-Object { $AllErrors += $_ }
                     $ErrorFound = $true 
                }
            } 

            Write-Progress -Activity "Processing Event Logs - Reading in" -Completed
        }


        #
        # Find the node name prefix, so we can trim the node name if possible
        #

        $NodeCount = $ClusterNodes.Count
        If ($NodeCount -gt 1) { 
    
            # Find the length of the shortest node name
            $NodeShort = $ClusterNodes[0].Name.Length
            1..($NodeCount-1) | Foreach-Object {
                If ($NodeShort -gt $ClusterNodes[$_].Name.Length) {
                    $NodeShort = $ClusterNodes[$_].Name.Length
                }
            }

            # Find the first character that's different in a node name (end of prefix)
            $Current = 0
            $Done = $false
            While (-not $Done) {

                1..($NodeCount-1) | Foreach-Object {
                    If ($ClusterNodes[0].Name[$Current] -ne $ClusterNodes[$_].Name[$Current]) {
                        $Done = $true
                    }
                }
                $Current++
                If ($Current -eq $NodeShort) {
                    $Done = $true
                }
            }
            # The last character was the end of the prefix
            $NodeSame = $Current-1
        } 


        #
        # Trim the node name by removing the node name prefix
        #
        Function TrimNode {
            Param ([String] $Node) 
            $Result = $Node.Split(".")[0].Trim().TrimEnd()
            If ($NodeSame -gt 0) { $Result = $Result.Substring($NodeSame, $Result.Length-$NodeSame) }
            Return $Result
        }

        # 
        # Trim the log name by removing some common log name prefixes
        #
        Function TrimLogName {
            Param ([String] $LogName) 
            $Result = $LogName.Split(",")[1].Trim().TrimEnd()
            $Result = $Result.Replace("Microsoft-Windows-","")
            $Result = $Result.Replace("Hyper-V-Shared-VHDX","Shared-VHDX")
            $Result = $Result.Replace("Hyper-V-High-Availability","Hyper-V-HA")
            $Result = $Result.Replace("FailoverClustering","Clustering")
            Return $Result
        }

        #
        # Convert the grouped table into a table with the fields we need
        #
        $Errors = $AllErrors | Select-Object @{Expression={TrimLogName($_.Name)};Label="LogName"},
        @{Expression={[int] $_.Name.Split(",")[2].Trim().TrimEnd()};Label="EventId"},
        @{Expression={TrimNode($_.Name)};Label="Node"}, Count, 
        @{Expression={$_.Group[0].Message};Label="Message"} | 
        Sort-Object LogName, EventId, Node

        #
        # Prepare to summarize events by LogName/EventId
        #

        If ($Errors) {

            $Last = $Errors.Count -1
            $LogName = ""
            $EventID = 0

            $ErrorSummary = 0 .. $Last | Foreach-Object {

                #
                # Top of row, initialize the totals
                #

                If (($LogName -ne $Errors[$_].LogName) -or ($EventId -ne $Errors[$_].EventId)) {
                    Write-Progress -Activity "Processing Event Logs - Summary" -PercentComplete ($_ / ($Last+1) * 100)
                    $LogName = $Errors[$_].LogName
                    $EventId = $Errors[$_].EventId
                    $Message = $Errors[$_].Message

                    # Zero out the node hash table
                    $NodeData = @{}
                    $ClusterNodes | Foreach-Object { 
                        $Node = TrimNode($_.Name)
                        $NodeData.Add( $Node, 0) 
                    }
                }

                # Add the error count to the node hash table
                $Node = $Errors[$_].Node
                $NodeData[$Node] += $Errors[$_].Count

                #
                # Is it the end of row?
                #
                If ($_ -eq $Last) { 
                    $EndofRow = $true 
                } else { 
                    If (($LogName -ne $Errors[$_+1].LogName) -or ($EventId -ne $Errors[$_+1].EventId)) { 
                        $EndofRow = $true 
                    } else { 
                        $EndofRow = $false 
                    }
                }

                # 
                # End of row, generate the row with the totals per Logname, EventId
                #
                If ($EndofRow) {
                    $ErrorRow = "" | Select-Object LogName, EventId
                    $ErrorRow.LogName = $LogName
                    $ErrorRow.EventId = "<" + $EventId + ">"
                    $TotalErrors = 0
                    $ClusterNodes | Sort-Object Name | Foreach-Object { 
                        $Node = TrimNode($_.Name)
                        $NNode = "N"+$Node
                        $ErrorRow | Add-Member -NotePropertyName $NNode -NotePropertyValue $NodeData[$Node]
                        $TotalErrors += $NodeData[$Node]
                    }
                    $ErrorRow | Add-Member -NotePropertyName "Total" -NotePropertyValue $TotalErrors
                    $ErrorRow | Add-Member -NotePropertyName "Message" -NotePropertyValue $Message
                    $ErrorRow
                }
            }
        } else {
            $ErrorSummary = @()
        }

        $ErrorSummary | Export-Clixml ($Path + "GetAllErrors.XML")
        Write-Progress -Activity "Processing Event Logs - Summary" -Completed

        "Gathering System Info and Minidump files ..." 

        $Count1 = 0
        $Total1 = NCount($ClusterNodes | Where-Object State -like "Up")
    
        If ($Total1 -gt 0) {
    
            $ClusterNodes | Where-Object State -like "Up" | Foreach-Object {

                $Progress = ( $Count1 / $Total1 ) * 100
                Write-Progress -Activity "Gathering System Info and Minidump files" -PercentComplete $Progress
                $Node = $_.Name + "." + $Cluster.Domain

                # Gather SYSTEMINFO.EXE output for a given node

                $LocalFile = $Path+$Node+"_SystemInfo.TXT"
                SystemInfo.exe /S $Node >$LocalFile

                # Gather Network Adapter information for a given node

                $LocalFile = $Path+"GetNetAdapter_"+$Node+".XML"
                Try { Get-NetAdapter -CimSession $Node >$LocalFile }
                Catch { ShowWarning("Unable to get a list of network adapters for node $Node") }

                # Gather SMB Network information for a given node

                $LocalFile = $Path+"GetSmbServerNetworkInterface_"+$Node+".XML"
                Try { Get-SmbServerNetworkInterface -CimSession $Node >$LocalFile } 
                Catch { ShowWarning("Unable to get a list of SMB network interfaces for node $Node") }

                # Enumerate minidump files for a given node

                Try { $NodePath = Invoke-Command -ComputerName $Node { Get-Content Env:\SystemRoot }
                      $RPath = "\\"+$Node+"\"+$NodePath.Substring(0,1)+"$\"+$NodePath.Substring(3,$NodePath.Length-3)+"\Minidump\*.dmp"
                      $DmpFiles = Get-ChildItem -Path $RPath -Recurse -ErrorAction SilentlyContinue }                       
                Catch { $DmpFiles = ""; ShowWarning("Unable to get minidump files for node $Node") }

                # Copy minidump files from the node

                $DmpFiles | Foreach-Object {
                    $LocalFile = $Path + $Node + "_" + $_.Name 
                    Try { Copy-Item $_.FullName $LocalFile } 
                    Catch { ShowWarning("Could not copy minidump file $_.FullName") }
                }        

                $Count1++
            }
        }

        Write-Progress -Activity "Gathering System Info and Minidump files" -Completed

        "Receiving Cluster Logs..."
        $ClusterLogJob | Wait-Job | Receive-Job
        $ClusterLogJob | Remove-Job        
    
        $errorFilePath = $Path + "\*"
        Remove-Item -Path $errorFilePath -Include "*_Event_*.EVTX" -Recurse -Force -ErrorAction SilentlyContinue

        "All Logs Received`n"
    }

    If ($Read) { 
        Try { $ErrorSummary = Import-Clixml ($Path + "GetAllErrors.XML") }
        Catch { $ErrorSummary = @() }
    }

    If ($Read -or $IncludeEvents) {
        If (-not $ErrorSummary) {
            "No errors found`n" 
        } Else { 

            #
            # Output the final error summary
            #
            "Summary of Error Events (in the last $HoursOfEvents hours) by LogName and EventId"
            $ErrorSummary | Sort-Object Total -Descending | Select-Object * -ExcludeProperty Group, Values | Format-Table  -AutoSize
        }
    }
    
    #
    # Phase 7
    #

    #
    # Force GC so that any pending file references are
    # torn down. If they live, they will block removal
    # of content.
    #

    [System.GC]::Collect()

    If (-not $read) {

        "<<< Phase 7 - Compacting files for transport >>>`n"

        $ZipSuffix = '-{0}{1:00}{2:00}-{3:00}{4:00}' -f $TodayDate.Year,$TodayDate.Month,$TodayDate.Day,$TodayDate.Hour,$TodayDate.Minute
        $ZipSuffix = "-" + $Cluster.Name + $ZipSuffix
        $ZipPath = $ZipPrefix+$ZipSuffix+".ZIP"

        Try {
            "Creating zip file with objects, logs and events."

            [Reflection.Assembly]::LoadWithPartialName("System.IO.Compression.FileSystem") | Out-Null
            $ZipLevel = [System.IO.Compression.CompressionLevel]::Optimal
            [System.IO.Compression.ZipFile]::CreateFromDirectory($Path, $ZipPath, $ZipLevel, $false)

            "Cleaning up temporary directory $Path"
            Remove-Item -Path $Path -ErrorAction SilentlyContinue -Recurse
            "Zip File Name : $ZipPath `n" 
        } Catch {
            ShowError("Error creating the ZIP file!`nContent remains available at $Path") 
        }
    }
    # Stop Transcript
    Stop-Transcript
}

New-Alias -Name TestSH -Value Test-StorageHealth -Description "Report on Storage Cluster Health"
