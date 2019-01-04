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

$allProjects = $c.Repository.Projects.GetAll();
Write-Host "Projects: $($allProjects.Count)"
$allUsers = $c.Repository.Users.GetAll();
Write-Host "Users: $($allUsers.Count)"
$allMachines = $c.Repository.Machines.GetAll();
Write-Host "Machines: $($allMachines.Count)"

$totalCount = $allProjects.Count + $allUsers.Count + $allMachines.Count
Write-Host "Total: $($totalCount)"
