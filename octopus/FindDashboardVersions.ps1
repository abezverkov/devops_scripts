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

$env = $c.Repository.Environments.FindByName('STAGE')
$deployments = $c.Repository.Dashboards.GetDashboard().Items | where EnvironmentId -eq $env.Id
$list = @()
foreach ($deployment in  $deployments)
{
    $release = $c.Repository.Releases.Get($deployment.ReleaseId)
    $project = $c.Repository.Projects.Get($release.ProjectId)
    $list += New-Object -TypeName PSObject -Property @{"Project"=$project.Name;"Version"=$release.Version.Replace("-p","");"Completed"=$deployment.CompletedTime} 
}
@($list | where Version -match '4.17.9' | %{ "$($_.Project)`t$($_.Version)`t$($_.Completed)"  }) | Out-ClipBoard
