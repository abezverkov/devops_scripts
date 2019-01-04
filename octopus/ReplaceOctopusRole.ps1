param (
    [Parameter(Mandatory=$false)]
    [string] $OctopusAPIKey = $env:OctopusAPIKey,

    [Parameter(Mandatory=$false)]
    [string] $OctopusURL = $env:OctopusURL,

    [Parameter(Mandatory=$false)]
    [string] $OldRole = 'serivces',

    [Parameter(Mandatory=$false)]
    [string] $NewRole = 'services',

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
Set-OctopusConnectionInfo -URL $env:OctopusURL -APIKey $OctopusAPIKey
$c = New-OctopusConnection -Verbose

$roleKey = 'Role'

Write-Host 'Collecting Octopus Projects'
[Octopus.Client.Model.ProjectResource[]]$octoProjects = Get-OctopusProject -ResourceOnly
foreach ($project in $octoProjects) 
{
    # Find the deployment process for the project
    Write-Host "Seaching Deploy Steps for $($project.Id)"
    [Octopus.Client.Model.DeploymentProcessResource]$deployProcess = $c.repository.DeploymentProcesses.Get($project.DeploymentProcessId);
    $projectUpdated = $false
    for ($i =  0; $i -lt $deployProcess.Steps.Count; $i++)
    {
       $key = 'Octopus.Action.TargetRoles'
       if ($deployProcess.Steps[$i].Properties[$key].Value -eq $OldRole)
       {
           $deployProcess.Steps[$i].Properties.Remove($key)
           $deployProcess.Steps[$i].Properties.Add($key, $NewRole) 
           $projectUpdated = $true
       }
    }
    if ($projectUpdated) { 
        $c.repository.DeploymentProcesses.Modify($deployProcess)
    } 

    Write-Host "Seaching Variables for $($project.Id)"
    $projectUpdated = $false
    [Octopus.Client.Model.VariableSetResource]$projectVars = $c.repository.VariableSets.Get($project.VariableSetId)
    for ($i =  0; $i -lt $projectVars.Variables.Count; $i++)
    {
        if ($projectVars.Variables[$i].Scope[$roleKey] -contains $OldRole)
        {
            $projectVars.Variables[$i].Scope[$roleKey].Add($NewRole)
            $projectVars.Variables[$i].Scope[$roleKey].Remove($OldRole)
            $projectUpdated = $true
        }
    }
    if ($projectUpdated) { 
        $c.repository.VariableSets.Modify($projectVars)
    } 
}

Write-Host "Collecting LibraryVariableSets"
[Octopus.Client.Model.LibraryVariableSetResource[]]$libVarSets = $c.repository.LibraryVariableSets.GetAll()
foreach ($rdi in $libVarSets)
{
    Write-Host "Seaching LibrarySets for $($rdi.Id)  $($rdi.Name)"
    [Octopus.Client.Model.LibraryVariableSetResource]$libVarSet = $c.repository.LibraryVariableSets.Get($rdi.Id)
    [Octopus.Client.Model.VariableSetResource]$varSet = $c.repository.VariableSets.Get($libVarSet.VariableSetId)
    $varSetUpdated = $false
    for ($i =  0; $i -lt $varSet.Variables.Count; $i++)
    {
        if ($varSet.Variables[$i].Scope[$roleKey] -contains $OldRole)
        {
            $varSet.Variables[$i].Scope[$roleKey].Add($NewRole)
            $varSet.Variables[$i].Scope[$roleKey].Remove($OldRole)
            $varSetUpdated = $true
        }
    }
    if ($varSetUpdated) { 
        $c.repository.VariableSets.Modify($varSet)
    } 

}

Write-Host "Collecting Machines"
[Octopus.Client.Model.MachineResource[]]$octoMachines = Get-OctopusMachine -ResourceOnly
$octoMachines = $octoMachines | ? { $_.Roles -contains $OldRole }
foreach ($machine in $octoMachines) 
{
    Write-Host "Updating Machine for $($machine.Id)"
    $machine.Roles.Add($NewRole) | Out-Null
    $machine.Roles.Remove($OldRole) | Out-Null
    #Update-OctopusResource $machine -Force
}
