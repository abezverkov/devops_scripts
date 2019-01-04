param (
    [Parameter(Mandatory=$false)]
    [string] $OctopusAPIKey = $env:OctopusAPIKey,

    [Parameter(Mandatory=$false)]
    [string] $OctopusURL = $env:OctopusURL,

    [Parameter(Mandatory=$false)]
    #[string] $AggregateVarSetId ='LibraryVariableSets-121',  #AssureSign
    [string] $AggregateVarSetId ='LibraryVariableSets-101',  #Mongo

    [Parameter(Mandatory=$false)]
    #[string] $Match ='AssureSign',
    [string] $Match ='SmsRepositoryConnectionString',

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

Write-Host 'Collecting Octopus Projects'
$octoProjects = Get-OctopusProject -Verbose -ResourceOnly 
$roleKey = 'Role'

Write-Host "Collecting LibraryVariableSets: $AggregateVarSetId"
[Octopus.Client.Model.LibraryVariableSetResource]$matchingLibVarSet = $c.Repository.LibraryVariableSets.Get($AggregateVarSetId)

Write-Host "Collecting VariableSets: $($matchingLibVarSet.Name), $AggregateVarSetId"
[Octopus.Client.Model.VariableSetResource]$matchingLibVarSet = $c.Repository.VariableSets.Get($matchingLibVarSet.VariableSetId)
[Octopus.Client.Model.VariableResource[]]$matchingLibVars = $matchingLibVarSet.Variables

foreach ($octoProject in $octoProjects)
{
    [Octopus.Client.Model.ProjectResource]$octoProject = $octoProject
    $projectName = $octoProject.Name
    Write-Host "Checking Project: $projectName"

    # Get the variable from the variable set for the project
    [Octopus.Client.Model.VariableSetResource]$projectVarset = (Get-OctopusVariableSet -Projectname $projectName -ResourceOnly -Verbose)
    [Octopus.Client.Model.VariableResource[]]$projectVars = $projectVarset.Variables
    
    $matchingVars  = $null
    $matchingVars = ($projectVars | ? { $_.Name -match $Match } )
    if ($matchingVars)
    {
        Write-Host ""
        Write-Host "======================================================="
        write-host "Found $Match vars in $projectName"
        Write-Host "======================================================="
    }
    foreach ($matchingVar in $matchingVars)
    {
        $key = $matchingVar.Name
        $value = $matchingVar.Value
        $varScope = $matchingVar.Scope[$roleKey]

        $matchingLibVar =  ($matchingLibVars | ? { ($_.Name -eq $key)  -and ($_.Value -eq $value) -and ($_.Scope[$roleKey] -eq $matchingVar.Scope[$roleKey]) })
        if (-not $matchingLibVar)
        {
            # If the variable doesnt exist in Octopus, create a new one with the environemt scope
            Write-Host "Adding NEW from $projectName : $key, $value, $varScope"
            [Octopus.Client.Model.ScopeSpecification]$newScope = New-Object -TypeName 'Octopus.Client.Model.ScopeSpecification'
            $newScope.Add($roleKey, $varScope);
                 
            [Octopus.Client.Model.VariableResource]$obj = New-Object -TypeName 'Octopus.Client.Model.VariableResource'
            $obj.Name =$key
            $obj.Value = $value
            $obj.Scope = $newScope
                
           $matchingLibVars += $obj
        }
    }
}

    $matchingLibVarSet.Variables = $matchingLibVars
    if (-not($WhatIf)) {
        Write-Host "Updating varset $matchingLibVarSetId" -ForegroundColor Green
        $c.Repository.VariableSets.Modify($matchingLibVarSet)
    }
