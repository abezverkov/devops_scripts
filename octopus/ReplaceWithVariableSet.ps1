#==========================================================================================
# Loop through all the projects and if it contains variables defined in 'VariableSetId',
#   remove them and add the LibraryVariableSet
#==========================================================================================
param (
    [Parameter(Mandatory=$false)]
    [string] $OctopusAPIKey = $env:OctopusAPIKey,

    [Parameter(Mandatory=$false)]
    [string] $OctopusURL = $env:OctopusURL,

    [Parameter(Mandatory=$false)]
    [string] $VariableSetId = 'LibraryVariableSets-101',

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

[Octopus.Client.Model.LibraryVariableSetResource]$libVarset1 = $c.Repository.LibraryVariableSets.Get($VariableSetId)
if ($libVarset1 -eq $null) { Write-Host "LibraryVariableSetResource not found for $VariableSetId"; return;}

[Octopus.Client.Model.VariableSetResource]$varset1 = $c.Repository.VariableSets.Get($libVarset1.VariableSetId)
$varset1Names = $varset1.Variables | select -ExpandProperty Name -Unique

# Loop through all the projects
[Octopus.Client.Model.ProjectResource[]]$allProjects = $c.Repository.Projects.GetAll()
foreach ($project in $allProjects) 
{
    [Octopus.Client.Model.VariableSetResource]$projectVarset = $c.Repository.VariableSets.Get($project.VariableSetId) 
    $overlap = $projectVarset.Variables | where Name -in $varset1Names 
    if ($overlap.Count -gt 0)
    {
        Write-Host "Updating Project: $($project.Name)"
        if ($project.IncludedLibraryVariableSetIds -notcontains $VariableSetId) 
        { 
            Write-Host "  - Adding Varset: $($VariableSetId)"; 
            $project.IncludedLibraryVariableSetIds.Add($VariableSetId) 
            if (-not($WhatIf)) {$c.Repository.Projects.Modify($project)}
        } 
        $overlap | % { Write-Host "  - Removing Var: $($_.Name)"; $projectVarset.Variables.Remove($_) | Out-Null  } 
        if (-not($WhatIf)) {$c.Repository.VariableSets.Modify($projectVarset)}
    }
    #break;
}

