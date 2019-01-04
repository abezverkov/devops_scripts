param (
    [Parameter(Mandatory=$false)]
    [string] $OctopusAPIKey = $env:OctopusAPIKey,

    [Parameter(Mandatory=$false)]
    [string] $OctopusURL = $env:OctopusURL,

    [Parameter(Mandatory=$false)]
    [string] $VarSet ='variableset-LibraryVariableSets-1',

    [Parameter(Mandatory=$false)]
    [switch] $WhatIf = $false
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
$groups = $c.Repository.ProjectGroups.GetAll()
$playgroundId = ( $groups | where Name -eq Playground)[0].Id
$projects = $c.Repository.Projects.GetAll() | where ProjectGroupID -ne $playgroundId
foreach ($project in $projects)
{
    $group = ($groups | where Id -eq $project.ProjectGroupId)[0]
    Write-Host "$($project.Name)"
}