param (
    [Parameter(Mandatory=$true)]
    [string] $TeamCityUser,

    [Parameter(Mandatory=$true)]
    [string] $TeamCityPassword,

    [Parameter(Mandatory=$true)]
    [string] $ProjectName
)

Add-Type -Path "C:\Webcetera\Source\TeamCitySharp\src\TeamCitySharp\bin\Debug\TeamCitySharp.dll"
$WhatIf = $false

function GetParam([string]$Name, $build)  
{
    $buildParam = $build.Parameters.Property | where Name -eq $Name | select -First 1
    return $buildParam
}

function GetAddParam([string]$Name, $build)  
{
    $buildParam = GetParam $Name $build
    if (-not $buildParam) 
    { 
        $buildParam = New-Object TeamCitySharp.DomainEntities.Property; 
        $buildParam.Name = $Name;
        $build.Parameters.Property.Add($buildParam);
    }  
    return $buildParam
}

[TeamCitySharp.TeamCityClient]$c = New-Object 'TeamCitySharp.TeamCityClient' @('teamcity.webcetera.test',$false)
$c.Connect($TeamCityUser,$TeamCityPassword)

$builds = $c.BuildConfigs.All() | sort Name | where ProjectName -eq $ProjectName

foreach ($build in $builds)
{
    [TeamCitySharp.DomainEntities.BuildConfig]$build = $c.BuildConfigs.ByConfigurationId($build.Id)  
    if ($build.Project.Archived) { Write-Host "Archived $($build.Name)"; continue; } 

    $fullSolutionParam = GetParam 'Default Solution file' $build
    if ((-not $fullSolutionParam) -or (-not $fullSolutionParam.Value)) { Write-Host "Skipping.1 $($build.Name)"; continue; } 

    $ApplicationSolutionDirParam = GetAddParam 'ApplicationSolutionDir' $build
    $ApplicationSolutionFileParam = GetAddParam 'ApplicationSolutionFile' $build

    if (-not $ApplicationSolutionDirParam.Value)
    {
        $i = $fullSolutionParam.Value.LastIndexOf('\')
        if ($i -eq -1) { $i = $fullSolutionParam.Value.LastIndexOf('/') } 
        $ApplicationSolutionFileParam.Value = $fullSolutionParam.Value.Substring($i+1)
        $ApplicationSolutionDirParam.Value = $fullSolutionParam.Value.Substring(0,$i)        

        Write-Host "Updating Paramaters for $($build.Name)"
        if (-not $WhatIf) 
        {            
            $locals = 'ApplicationSolutionDir','ApplicationSolutionFile','Default Solution file','OctopusProjectName'
            $paramDict = New-Object 'System.Collections.Generic.Dictionary[String,String]'; $build.Parameters.Property | where Name -In $locals | % { $paramDict[$_.Name] = $_.Value } 
            [TeamCitySharp.Locators.BuildTypeLocator] $locator = [TeamCitySharp.Locators.BuildTypeLocator]::WithId($build.Id)
            #$c.BuildConfigs.SetConfigurationPauseStatus($locator, $true)        
            $c.BuildConfigs.PutAllBuildTypeParameters($locator, $paramDict)    
            #$c.BuildConfigs.SetConfigurationPauseStatus($locator, $false)
        }
    }
    else
    {
        Write-Host "Skipping $($build.Name)"
    }

    #break;
}