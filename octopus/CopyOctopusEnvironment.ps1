param (
    [Parameter(Mandatory=$false)]
    [string] $OctopusAPIKey = $env:OctopusAPIKey,

    [Parameter(Mandatory=$false)]
    [string] $OctopusURL = $env:OctopusURL,

    [Parameter(Mandatory=$false)]
    [string] $SourceEnvironmentName = 'TEST',

    [Parameter(Mandatory=$false)]
    [string] $TargetEnvironmentName = 'Team-M',

    [Parameter(Mandatory=$false)]
    [switch] $WhatIf = $true
)


if ($OctopusAPIKey) { $env:OctopusAPIKey = $OctopusAPIKey;  } 
if (-not $env:OctopusAPIKey) 
{
    Write-Host -ForegroundColor Red "OctopusAPIKey envinronment variable not defined"
    return
}

if ($OctopusURL) { $env:OctopusURL= $OctopusURL; }
if (-not $env:OctopusURL) 
{
    Write-Host -ForegroundColor Red "OctopusURL envinronment variable not defined"
    return
}

# connect to octopus deploy
Import-Module Octoposh
$c = New-OctopusConnection -Verbose

$dashBoard = $c.Repository.Dashboards.GetDashboard()

$SourceEnvironment = $dashBoard.Environments | where Name -eq $SourceEnvironmentName | select -First 1
if (-not $SourceEnvironment) 
{
    Write-Host -ForegroundColor Red "SourceEnvironment not found in Dashboard"
    return
}


$TargetEnvironment = $dashBoard.Environments | where Name -eq $TargetEnvironmentName | select -First 1
if (-not $TargetEnvironment) 
{
    Write-Host -ForegroundColor Red "TargetEnvironment not found in Dashboard"
    return
}

$deployGroups = $dashBoard.ProjectGroups | where Name -notlike 'z*'
$deployProjects = $dashBoard.Projects | ? { ($deployGroups).Id -contains $_.ProjectGroupId } 
#$deployProjects = $dashBoard.Projects | where Name -match 'Scheduling Service'
$deployItems = $dashBoard.Items | ? { (($deployProjects).Id -contains $_.ProjectId) -and ($_.EnvironmentId -eq $SourceEnvironment.Id) }

[int]$newReleases = 0
[int]$newDeployments = 0
[int]$existingDeployments = 0

foreach($deployItem in $deployItems) 
{
    [Octopus.Client.Model.DashboardItemResource] $deployItem    = $deployItem
    [Octopus.Client.Model.ReleaseResource]       $sourceRelease = $c.Repository.Releases.Get($deployItem.ReleaseId)
    [Octopus.Client.Model.ProjectResource]       $sourceProject = $c.Repository.Projects.Get($deployItem.ProjectId)
    [Octopus.Client.Model.ChannelResource[]]     $sourceChannels = ($c.Repository.Projects.GetChannels($sourceProject)).Items
    [Octopus.Client.Model.LifecycleResource[]]   $sourceLifecycles = $sourceChannels.LifecycleId | % { $c.Repository.Lifecycles.Get($_) }

    Write-Host ''
    Write-Host '============================================================================'
    Write-Host "Checking Project: $($sourceProject.Name)"
    Write-Host '============================================================================'

    [Octopus.Client.Model.ChannelResource] $targetChannel = $sourceChannels | ? { $_.LifecycleId -eq ($sourceLifecycles | ? { $TargetEnvironment.Id -in $_.Phases.OptionalDeploymentTargets }).Id}
    if (-not $targetChannel) { 
        Write-Host "Missing TargetChannel" -ForegroundColor Red
        continue;
    }
    $sourceReleaseSearch = $sourceRelease.Version.TrimEnd('-p')
    [Octopus.Client.Model.ReleaseResource] $targetRelease = $c.Repository.Projects.GetReleases($sourceProject,0,$null,$sourceReleaseSearch).Items | 
        where ChannelId -eq $targetChannel.Id  | 
        select -First 1

    if (-not $targetRelease)
    {        
        #Create new Release
        [Octopus.Client.Model.ReleaseResource] $targetRelease = New-Object -TypeName 'Octopus.Client.Model.ReleaseResource'
        $targetRelease.ProjectId                          = $sourceRelease.ProjectId
        $targetRelease.ProjectVariableSetSnapshotId       = $sourceRelease.ProjectVariableSetSnapshotId
        $targetRelease.LibraryVariableSetSnapshotIds      = $sourceRelease.ProjectVariableSetSnapshotId
        $targetRelease.ProjectDeploymentProcessSnapshotId = $sourceRelease.ProjectVariableSetSnapshotId
        $targetRelease.SelectedPackages                   = $sourceRelease.SelectedPackages
        $targetRelease.ChannelId                          = $targetChannel.Id
        $targetRelease.Version                            = ($sourceRelease.Version -replace '-p')+(@('-p','')[$targetChannel.Name -eq 'Default'])
        Write-Host "Creating new release for $($sourceProject.Name), Release:$($targetRelease.Version)"
        if (-not $WhatIf) {
            $targetRelease = $c.Repository.Releases.Create($targetRelease);
        }
        $newReleases += 1
    }
    else
    {
        [Octopus.Client.Model.DeploymentResource[]] $targetDeploy = $c.Repository.Releases.GetDeployments($targetRelease) | select -ExpandProperty Items | where EnvironmentId -eq $TargetEnvironment.Id
        if ($targetDeploy)
        {
            Write-Host "$($sourceProject.Name), Release:$($targetRelease.Version) already deployed to $($TargetEnvironmentName)" -ForegroundColor Yellow
            $existingDeployments += 1
            continue;
        }
    }

    #Create new Deploy
    [Octopus.Client.Model.DeploymentResource] $targetDeploy = New-Object -TypeName 'Octopus.Client.Model.DeploymentResource'
    $targetDeploy.ReleaseId = $targetRelease.Id;
    $targetDeploy.EnvironmentId = $TargetEnvironment.Id
    Write-Host "Creating new deployment for $($sourceProject.Name), Release:$($targetRelease.Version) to $($TargetEnvironmentName)"
    if (-not $WhatIf) {
        #posting the deploymen resource should kick off the task.
        try {  $targetDeploy = $c.Repository.Deployments.Create($targetDeploy); } catch { }
    }
    $newDeployments += 1
    #break;
}

Write-Host ''
Write-Host '============================================================================'
Write-Host 'Summary'
Write-Host '============================================================================'
Write-Host "NewReleases = $newReleases, NewDeployments = $newDeployments, ExistingDeployments = $existingDeployments"