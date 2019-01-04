param (
    [Parameter(Position=0, Mandatory=$false, ValueFromPipeline=$True)]
    [string] $SourceProjectName =  'Web API Template', #

    [Parameter(Mandatory=$false)]
    [string[]] $SourceStepNames,

    [Parameter(Mandatory=$false)]
    [string] $TargetProjectName,

    [Parameter(Mandatory=$false)]
    [string] $TargetProjectGroup,

    [Parameter(Mandatory=$false)]
    [string] $OctopusAPIKey = $env:OctopusAPIKey,

    [Parameter(Mandatory=$false)]
    [string] $OctopusURL = $env:OctopusURL,

    [Parameter(Mandatory=$false)]
    [switch] $DeleteMatching, # Clear out named steps

    [Parameter(Mandatory=$false)]
    [switch] $ReplaceTarget,

    [Parameter(Mandatory=$false)]
    [switch] $DeleteTargetOnly  = $true,

    [Parameter(Mandatory=$false)]
    [switch] $WhatIf = $true
)

$UpdateOnly = $false
cls

if ( -not ($TargetProjectName -or $TargetProjectGroup))
{
    Write-Host "$TargetProjectName -or $TargetProjectGroup"
    Write-Host -ForegroundColor Red "Must specificy either TargetProjectName or TargetProjectGroup"
    return
}

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

$roleKey = 'Role'

# connect to octopus deploy
Import-Module Octoposh
$c = New-OctopusConnection -Verbose

Write-Host 'Collecting Octopus Projects'
[Octopus.Client.Model.ProjectResource[]]$allprojects =  Get-OctopusProject -ResourceOnly

[Octopus.Client.Model.ProjectResource[]]$targetProjects = @()
if ($TargetProjectName)
{
    [Octopus.Client.Model.ProjectResource[]] $targetProjects = $allprojects |  ? { $_.Name -eq $TargetProjectName};
    if ($targetProjects.Count -lt 1)
    {
        Write-Host "TargetProjectName is invalid: $TargetProjectName"
        return
    }
}
else
{
    $projectGroup = $c.repository.ProjectGroups.FindByName($TargetProjectGroup)
    if ($projectGroup -eq $null)
    {
        Write-Host "TargetProjectGroup is invalid: $TargetProjectGroup"
        return
    }
    [Octopus.Client.Model.ProjectResource[]]$targetProjects = $allprojects | where { $_.ProjectGroupId -eq $projectGroup.Id };
}


[Octopus.Client.Model.ProjectResource] $sourceProject = $allprojects |  ? { $_.Name -eq $SourceProjectName};
if ($sourceProject -eq $null)
{
    Write-Host "SourceProjectName is invalid: $SourceProjectName"
    return
}
else 
{
    [Octopus.Client.Model.DeploymentProcessResource]$sourceDeployProcess = $c.repository.DeploymentProcesses.Get($sourceProject.DeploymentProcessId);
    if ($sourceDeployProcess -eq $null)
    {
        Write-Host "Didn't find a deploy process for '$($SourceProjectName)'"
        return
    }
    $sourceDeploySteps = $sourceDeployProcess.Steps
    if ($SourceStepNames.Length -gt 0)
    {
        $sourceDeploySteps = $sourceDeployProcess.Steps | ?  { $SourceStepNames -contains $_.Name } 
    }

    $sourceChannels = $c.repository.Projects.GetChannels($sourceProject).Items;
}

foreach ($project in $targetProjects) 
{
    if ($project.Id -eq $sourceProject.Id) {
        continue;
    }

    Write-Host ''
    Write-Host -ForegroundColor Cyan "=========================================================================="
    Write-Host -ForegroundColor Cyan "Configuring Project:$($project.Name)  Id:$($project.Id)"
    Write-Host -ForegroundColor Cyan "=========================================================================="
    $projectUpdated = $false

    $targetVarSet = $c.Repository.VariableSets.Get($project.VariableSetId)
    $targetTemplateName = $targetVarSet.Variables | where Name -eq 'Octopus.TemplateName' | select -ExpandProperty Value -ErrorAction SilentlyContinue
    if ($targetTemplateName -ne $SourceProjectName)
    {
        Write-Host "Target does not contain matching TemplateName variable"
        continue;
    }

    # Add any missing channels so that steps will scope correctly
    [Octopus.Client.Model.ChannelResource[]]$targetChannels = $c.repository.Projects.GetChannels($project).Items
    [Octopus.Client.Model.ChannelResource[]]$missingChannels = $sourceChannels | ? { $targetChannels.Name -notcontains $_.Name }
    if ($missingChannels.Count -gt 0)
    {        
        Write-Host ''
        Write-Host -ForegroundColor Cyan "Channels"
        Write-Host -ForegroundColor Cyan "========"
        foreach ($channel in $missingChannels)
        {
            Write-Host "Adding missing channel: $($channel.Name)"
            [Octopus.Client.Model.ChannelResource]$channel = $channel
            [Octopus.Client.Model.ChannelResource]$newChannel = New-Object -TypeName 'Octopus.Client.Model.ChannelResource'
            $newChannel.Name = $channel.Name
            $newChannel.Description = $channel.Description
            $newChannel.ProjectId = $project.Id
            $newChannel.Rules = $channel.Rules
            $newChannel.LifecycleId = $channel.LifecycleId 
            ############################################################### TODO:copy channel rules ###############################################################
            if (-not $WhatIf)
            {
                $c.repository.Channels.Create($newChannel) | Out-Null
                Write-Host -ForegroundColor Green "New channel added"
            }
        }
    }
    # Re-pull channels for id later
    [Octopus.Client.Model.ChannelResource[]]$targetChannels = $c.repository.Projects.GetChannels($project).Items

    # Add any missing variable sets
    $missingVariableSets = $sourceProject.IncludedLibraryVariableSetIds | ? { $_ -notin $project.IncludedLibraryVariableSetIds }
    if ($missingChannels.Count -gt 0)
    {        
        Write-Host ''
        Write-Host -ForegroundColor Cyan "VariableSets"
        Write-Host -ForegroundColor Cyan "============"
        foreach($missingVariableSet in $missingVariableSets)        
        {
            Write-Host "Adding VariableSet:$missingVariableSet"
            $project.IncludedLibraryVariableSetIds.Add($missingVariableSet)
            $projectUpdated = $true
        }
    }

    # Find the deployment process for the project
    [Octopus.Client.Model.DeploymentProcessResource]$deployProcess = $c.repository.DeploymentProcesses.Get($project.DeploymentProcessId);
    $targetDeploySteps = $deployProcess.Steps
    if ($SourceStepNames.Length -gt 0)
    {
        $targetDeploySteps = $targetDeploySteps | ?  { $SourceStepNames -contains $_.Name } 
    }

    $missingSteps = @($sourceDeploySteps | ? { ($targetDeploySteps | % {$_.Name}) -notcontains $_.Name } )
    $matchingSteps = @($sourceDeploySteps | ? { ($targetDeploySteps | % {$_.Name}) -contains $_.Name } )
    $childOnlySteps = @( $targetDeploySteps | ? { ($sourceDeploySteps | % {$_.Name}) -notcontains $_.Name } )
    
    if ($missingSteps.Count -eq 0 -and $matchingSteps.Count -eq 0 -and $childOnlySteps.Count -eq 0) { continue }

    if ($missingSteps.Count -gt 0 -and -not $UpdateOnly) 
    {
        Write-Host ''
        Write-Host -ForegroundColor Cyan "DeploymentProcess - Add Missing Steps"
        Write-Host -ForegroundColor Cyan "====================================="
        foreach ($missing in $missingSteps)
        {
            # Add new step
            [Octopus.Client.Model.DeploymentStepResource]$newStep = New-Object -TypeName 'Octopus.Client.Model.DeploymentStepResource'
            $newStep.Name = $missing.Name;
            $newStep.RequiresPackagesToBeAcquired = $missing.RequiresPackagesToBeAcquired;
            $newStep.Condition = $missing.Condition;
            $newStep.StartTrigger = $missing.StartTrigger;
            foreach($prop in $missing.Properties.GetEnumerator()) 
            {
                $newStep.Properties.Add($prop.Key, $prop.Value) | Out-Null
            }
            foreach($matchingAction in $missing.Actions.GetEnumerator()) 
            {
                [Octopus.Client.Model.DeploymentActionResource]$matchingAction = $matchingAction;
                [Octopus.Client.Model.DeploymentActionResource]$newAction = New-Object -TypeName 'Octopus.Client.Model.DeploymentActionResource'
                $newAction.Name = $matchingAction.Name;
                $newAction.ActionType = $matchingAction.ActionType;
                #$newAction.IsDisabled = $matchingAction.IsDisabled;
                $matchingAction.Environments | % { $newAction.Environments.Add($_) }  | Out-Null
                $matchingAction.ExcludedEnvironments | % { $newAction.ExcludedEnvironments.Add($_) }  | Out-Null
                $targetChannels | ? { $_.Name -in ($sourceChannels |  ? { $_.Id -in $matchingAction.Channels }).Name } | select -ExpandProperty Id | % { $newAction.Channels.Add($_) } | Out-Null
                #$newAction.TenantTags = $matchingAction.TenantTags;
                foreach($prop in $matchingAction.Properties.GetEnumerator()) 
                {
                    $newAction.Properties.Add($prop.Key, $prop.Value) | Out-Null
                }
                $newStep.Actions.Add($newAction) | Out-Null
            }
            $idx = $sourceDeployProcess.Steps.IndexOf($missing);
            if (-not $UpdateOnly) {
                Write-Host "Adding step $($newStep.Name) at index $idx"
                if ($deployProcess.Steps.Count -eq 0) 
                {
                    $deployProcess.Steps.Add($newStep) | Out-Null
                }
                else 
                {
                    $deployProcess.Steps.Insert($idx, $newStep) | Out-Null
                }
                $projectUpdated = $true
            }
        }
    }

    if ($matchingSteps.Count -gt 0)
    {
        Write-Host ''
        Write-Host -ForegroundColor Cyan "DeploymentProcess - Update Matching Steps"
        Write-Host -ForegroundColor Cyan "========================================="
        foreach ($matchingSourceStep in $matchingSteps)
        {
            # Find and loop through all the actions in the matching target deploy step
            $matchingTargetStep = $deployProcess.Steps | ? { $_.Name -eq $matchingSourceStep.Name }        
            if ($DeleteMatching)
            {
                Write-Host "Removing step: $($matchingTargetStep.Name)"
                if ($deployProcess.Steps.Remove($matching2)) { $projectUpdated = $true } 
            }
            else
            {
                foreach($matchingAction in $matchingTargetStep.Actions.GetEnumerator()) 
                {
                    $origAction = $matchingSourceStep.Actions.GetEnumerator() | where Name -eq $matchingAction.Name
                    
                    if ($matchingAction.IsDisabled -ne $origAction.IsDisabled)
                    {
                        $matchingAction.IsDisabled = $origAction.IsDisabled;
                        $projectUpdated = $true
                    }
                    $matchingAction.IsDisabled = $origAction.IsDisabled;
                    if (Compare-Object $matchingAction.Environments $origAction.Environments)
                    {
                        Write-Host "Updating Environments for: $($matchingAction.Name)"
                        $matchingAction.Environments.Clear() | Out-Null
                        $origAction.Environments | % { $matchingAction.Environments.Add($_) }  | Out-Null 
                        $projectUpdated = $true
                    }
                    if (Compare-Object $matchingAction.ExcludedEnvironments $origAction.ExcludedEnvironments)
                    {
                        Write-Host "Updating ExcludedEnvironments for: $($matchingAction.Name)"
                        $matchingAction.ExcludedEnvironments.Clear() | Out-Null
                        $origAction.ExcludedEnvironments | % { $matchingAction.ExcludedEnvironments.Add($_) } | Out-Null 
                        $projectUpdated = $true
                    }

                    # Convert old style service deploy steps
                    if ($matchingAction.ActionType  -eq 'Octopus.WindowsService')
                    {
                        Write-Host 'Converting Octopus.WindowsService to Octopus.TentaclePackage'
                        $matchingAction.ActionType = 'Octopus.TentaclePackage'
                        $projectUpdated = $true
                    }

                    if ($matchingAction.ActionType  -in @('Octopus.Manual'))
                    {
                        Write-Host "Update Manual Action: $($matchingAction.Name)"
                        $origActionChannels = $targetChannels | ? { $_.Name -in  ($sourceChannels |  ? { $_.Id -in $origAction.Channels }).Name } | select -ExpandProperty Id 
                        $missingActionChannels = $origActionChannels | ? { $_ -notin $matchingAction.Channels }
                        if ($missingActionChannels.Count -gt 0)
                        {
                            Write-Host "--- Replacing Channel values"
                            $matchingAction.Channels.Clear() | Out-Null
                            $origActionChannels | %{ $matchingAction.Channels.Add($_) } | Out-Null
                            $projectUpdated = $true
                        }
                    }

                    if ($matchingAction.ActionType  -in @('Octopus.TentaclePackage', 'Octopus.WindowsService', 'Octopus.IIS', 'Octopus.Script'))
                    {
                        Write-Host "Update Package Action: $($matchingAction.Name)"
                        # If there is a matching action in the original
                        if ($origAction) 
                        {
                            $ignoreProperties = @('Octopus.Action.Package.FeedId','Octopus.Action.Package.PackageId')
                            $origProperties = $origAction.Properties.GetEnumerator() | where Key -notin $ignoreProperties
                            foreach( $origProperty in $origProperties)
                            {
                                if ($matchingAction.Properties[$origProperty.Key].Value -ne $origProperty.Value.Value)
                                {
                                    Write-Host "--- Replacing property:$($origProperty.Key) on action:$($matchingAction.Name)  new value:$($origProperty.Value.Value)"
                                    $matchingAction.Properties[$origProperty.Key] = $origProperty.Value
                                    $projectUpdated = $true
                                }
                            }
                            $deleteProperties = $matchingAction.Properties.GetEnumerator() | where Key -notin $ignoreProperties
                            foreach( $deleteProperty in ($deleteProperties | ? { $_.Key -notin $origProperties.Key } ))
                            {
                                Write-Host "--- Removing property$($deleteProperty.Key)"
                                $matchingAction.Properties.Remove($deleteProperty.Key) | Out-Null
                                $projectUpdated = $true
                            }
                        }
                    }
                }
            }
        }
    }

    if ($childOnlySteps.Count -gt 0)
    {
        Write-Host ''
        Write-Host -ForegroundColor Cyan "DeploymentProcess - Child Only Steps"
        Write-Host -ForegroundColor Cyan "===================================="
        foreach ($childStep in $childOnlySteps)
        {
            if ($DeleteTargetOnly)
            {
                Write-Host "Removing step: $($childStep.Name)"
                if ($deployProcess.Steps.Remove($childStep)) { $projectUpdated = $true } 
            }
        }
    }

    if ($projectUpdated -and -not $WhatIf) { 
        $response = $c.repository.DeploymentProcesses.Modify($deployProcess)
        Write-Host -ForegroundColor Green "Project Updated"
    } 
    
    #---------------------------------------------------------------------
    continue
    #---------------------------------------------------------------------

    Write-Host "Seaching Variables for $($project.Id)"
    $projectUpdated = $false
    [Octopus.Client.Model.VariableSetResource]$projectVars = $c.repository.VariableSets.Get($project.VariableSetId)
    for ($i =  0; $i -lt $projectVars.Variables.Count; $i++)
    {
        if ($projectVars.Variables[$i].Scope[$roleKey] -contains $oldRole)
        {
            $projectVars.Variables[$i].Scope[$roleKey].Add($newrole)
            $projectVars.Variables[$i].Scope[$roleKey].Remove($oldrole)
            $projectUpdated = $true
        }
    }
    if ($projectUpdated) { 
        #$c.repository.VariableSets.Modify($projectVars)
    } 
}


