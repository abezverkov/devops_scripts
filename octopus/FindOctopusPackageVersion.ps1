param (
    [Parameter(Mandatory=$false)]
    [string] $OctopusAPIKey = $env:OctopusAPIKey,

    [Parameter(Mandatory=$false)]
    [string] $OctopusURL = $env:OctopusURL,

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

# connect to octopus deploy
Write-Host 'Collecting Octopus Projects'
$requestedVersion = '4.18.6.29629'
$requestedChannelName = 'Production'
[string[]]$requestedProjectGroupNames = @()
[string[]]$excludedProjectGroupNames = @('Playground')

[Octopus.Client.Model.ProjectResource[]]$octoProjects = Get-OctopusProject -Verbose -ResourceOnly

# if current env is TEST 
## check for existing release '-p'
### create release '-p'

# all 
## check for deployment of releases in current env
### deploy release in current evn if not blocked or failed

[Octopus.Client.Model.ProjectGroupResource[]]$projectGroups = $c.repository.ProjectGroups.GetAll();
[Octopus.Client.Model.ProjectGroupResource[]]$requestedProjectGroups = $projectGroups
if ($requestedProjectGroupNames.Count -gt 0)
{
    $requestedProjectGroups = $projectGroups | ? { $_.Name -in $requestedProjectGroupNames } 
}
if ($excludedProjectGroupNames.Count -gt 0)
{
    $requestedProjectGroups = $requestedProjectGroups | ? { $_.Name -notin $excludedProjectGroupNames }
}
$octoProjects = $octoProjects | ? { $_.ProjectGroupId -in $requestedProjectGroups.Id }

Write-Host ''
Write-Host -ForegroundColor Cyan "=========================================================================="
Write-Host -ForegroundColor Cyan "Pulling Releases for version:$requestedVersion  Channel:$requestedChannelName"
Write-Host -ForegroundColor Cyan "=========================================================================="
[Octopus.Client.Model.ReleaseResource[]]$releases = $c.repository.Releases.FindMany({param($r) $r.Version -match $requestedVersion}) 

[Octopus.Client.Model.ReleaseResource[]]$deploymentReleases = @();
foreach ($project in $octoProjects) 
{
    Write-Host ''
    Write-Host -ForegroundColor Cyan "=========================================================================="
    Write-Host -ForegroundColor Cyan "Searching Project:$($project.Name)  Id:$($project.Id)"
    Write-Host -ForegroundColor Cyan "=========================================================================="

    [Octopus.Client.Model.ChannelResource]$requestedChannel = $c.repository.Channels.FindByName($project, 'Production') | select -First 1
    if (-not $requestedChannel)
    {
        Write-Host "Requested Channel does not exist for project" -ForegroundColor Red
        continue
    }

    # Find the deployment process for the project
    [Octopus.Client.Model.DeploymentProcessResource]$deployProcess = $c.repository.DeploymentProcesses.Get($project.DeploymentProcessId);
    $packageSteps  = $deployProcess.Steps | Where Name -match '^Deploy'

    $packagePropertyKeys  = @('Octopus.Action.Package.FeedId','Octopus.Action.Package.PackageId')
    foreach ($step in $packageSteps)
    {
        $packageProperties = $step.Actions.Properties.GetEnumerator() | ? { $_.Key -in $packagePropertyKeys }    
        if ($packageProperties.Count -gt 0)
        {
            $feedId = $packageProperties | ? { $_.Key -eq 'Octopus.Action.Package.FeedId' }  | % { $_.Value.Value }
            if (-not $feedId -or $feedId -ne 'feeds-builtin')
            {
                Write-Host "Only BuiltIn Feed Supported" -ForegroundColor Red
                continue;
            }

            $packageId = $packageProperties | ? { $_.Key -eq 'Octopus.Action.Package.PackageId' }  | % { $_.Value.Value }
            if (-not $packageId)
            {
                continue;
            }

            Write-Host "Checking feed:$feedId for package:$packageId  version:$requestedVersion"
            [Octopus.Client.Model.NuGetFeedResource]$feed = $c.repository.Feeds.Get($feedId)   
            if ($feed -ne $null)
            {
                [Octopus.Client.Model.PackageResource[]]$packages = $c.repository.BuiltInPackageRepository.ListPackages($packageId,0,100).Items
            }
            else
            {
                Write-Host "Could not fetch feed:$feedId" -ForegroundColor Red
                continue;
            }

            [Octopus.Client.Model.PackageResource[]]$requestedPackages  = $packages | where { $_.Version -eq $requestedVersion }
            if ($requestedPackages.count -gt 0) 
            { 
                
                Write-Host "Found Package!!! Looking for release on channel:$requestedChannelName " -ForegroundColor Green 
                #$c.repository.Releases.FindMany({param($r) $r.ProjectId -eq $project.Id -and $r.Version -eq $requestedVersion -and $r.ChannelId -eq 'Channels-143'}) | select -First 1
                $release = $releases | ? { $_.ProjectId -eq $project.Id } | ? { $_.SelectedPackages.Version -contains $requestedVersion } | ? { $_.ChannelId -eq $requestedChannel.Id }
                if (-not $release)
                {
                    Write-Host "Creating Release" -ForegroundColor DarkMagenta
                    $newRelease = New-Object -Type 'Octopus.Client.Model.ReleaseResource'
                    $deploymentReleases += $newRelease
                    $newRelease.ChannelId = $requestedChannel.Id
                    $newRelease.ProjectId = $project.Id
                    $newRelease.Version = "$requestedVersion-p"
                    # create new release 
                }
                else
                {
                    $deploymentReleases += $release
                }

            }


        }
    }
      
}