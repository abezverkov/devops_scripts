param (
    [string] $VstsApiToken = $env:VstsApiToken,
    [string] $VstsUrl = $env:VstsUrl,
    [string] $VstsUser = $env:VstsUser,
    [switch] $WhatIf = $false
)
$Base64PAT = ([System.Text.Encoding]::UTF8.GetBytes("${VstsUser}:$VstsApiToken") | ConverTo-Base64)

#==================================================================================================================================
function SetPermProject([string]$project,[string]$group,[string]$perm,[string]$allow='allow')
{
    Write-Host "$allow permisson:$perm for [$project]\$group"
    $result = tf git permission /collection:$VstsUrl /teamproject:$project /group:"[$project]\$group" /${allow}:$perm
}
#==================================================================================================================================
function SetPermBranch([string]$project,[string]$group,[string]$perm,[string]$repo,[string]$branch,[string]$allow='allow')
{
    Write-Host "$allow permisson:$perm for [$project]\$group $repo/$branch"
    $result = tf git permission /collection:$VstsUrl /teamproject:$project /group:"[$project]\$group" /${allow}:$perm /repository:$repo /branch:$branch
}
#==================================================================================================================================
# Load VS Command prompt for TF.exe
if (-not(gcm tf.exe)) {
    pushd "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\Tools"
    cmd /c "VsDevCmd.bat&set" |
    foreach {
      if ($_ -match "=") {
        $v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
      }
    }
    popd
    Write-Host "`nVisual Studio 2017 Command Prompt variables set." -ForegroundColor Yellow
}
#==================================================================================================================================
function CreatePolicy([string]$typeId,$settings,$project,$scope = @( @{ "repositoryId"=$null } ))
{    
    Write-Host "Creating policy type:$typeId for project:$project repo:${$scope[0].repositoryId}"
    $json = @{
        "isEnabled"=$true
        "isBlocking"=$true
        "type"=@{
            "id"=$typeId
        }
        "settings"= @{ "scope"=$scope } 
    }
    $settings.scope = $scope
    $json.settings  = $settings
    #return (ConvertTo-Json $json -Depth 12)

    $uri = "https://dev.azure.com/ezlynx/$project/_apis/policy/configurations?api-version=5.0-preview.1"
    $authHeader = @{ 
        "Authorization"="Basic $Base64PAT" 
        "Content-Type"="application/json"
    }
    return (Invoke-RestMethod -Method Post -Uri $uri -Headers $authHeader -Body (ConvertTo-Json $json -Depth 12))
}
#==================================================================================================================================
function GetPolicies($project)
{
    Write-Host "Getting policy configuration for: $project"
    $uri = "https://dev.azure.com/ezlynx/$project/_apis/policy/configurations?api-version=5.0-preview.1"
    $authHeader = @{ "Authorization"="Basic $Base64PAT" }
    $policies = (Invoke-RestMethod -Method Get -Uri $uri -Headers $authHeader).value
    return $policies | select  Id,@{Name="DisplayName"; Expression = {$_.Type.DisplayName}},@{Name="TypeId"; Expression = {$_.Type.Id}},@{Name="Settings"; Expression = {$_.Settings}}
}
#==================================================================================================================================
function RemovePolicy($project,$id)
{
    Write-Host "Deleting policy: $id configuration for: $project"
    $uri = "https://dev.azure.com/ezlynx/$project/_apis/policy/configurations/${id}?api-version=5.0-preview.1"
    $authHeader = @{ "Authorization"="Basic $Base64PAT" }
    $policies = (Invoke-RestMethod -Method Delete -Uri $uri -Headers $authHeader).value
    return $policies | select  Id,@{Name="DisplayName"; Expression = {$_.Type.DisplayName}},@{Name="TypeId"; Expression = {$_.Type.Id}},@{Name="Settings"; Expression = {$_.Settings}}
}
#==================================================================================================================================
function GetRepositories($project)
{
    Write-Host "Getting git repositories for: $project"
    $uri = "https://dev.azure.com/ezlynx/$project/_apis/git/repositories?api-version=5.0-preview.1"
    $authHeader = @{ "Authorization"="Basic $Base64PAT" }
    $repos = (Invoke-RestMethod -Method Get -Uri $uri -Headers $authHeader).value
    return $repos 
}
#==================================================================================================================================
Import-Module Team 
Add-TeamAccount -Account $VstsUrl -PersonalAccessToken $VstsApiToken
#==================================================================================================================================

$vstsProjects = @(Get-Project)
$vstsProjects = @(Get-Project | where name -eq 'AdamBezverkov')

foreach ($project in $vstsProjects) 
{
    Write-Host ''
    Write-Host '===================================================================================================================='
    Write-Host $project.name
    Write-Host '===================================================================================================================='

    #Clean Policies
    $cleanPolicies = GetPolicies $project.name
    #$cleanPolicies | % { RemovePolicy $project.name $_.id }

    # Deny all for project
    $group = 'Contributors'
    SetPermProject $project.name $group 'CreateBranch' 'deny'
    SetPermProject $project.name $group 'ForcePush' 'deny'

    $defaultPolicies = GetPolicies 'Protected'
    $projectPolicies = ($defaultPolicies | ? { -not($_.Settings.Scope.repositoryId) } )
    foreach ($policy in $projectPolicies)
    {
        $settings = $policy.Settings
        $typeId = $policy.TypeId
        $result = CreatePolicy $typeId $settings $project.name
    } 

    $projectRepos = GetRepositories $project.name
    foreach ($repo in $projectRepos)
    {
        $group = 'Contributors'
        SetPermBranch $project.name $group 'CreateBranch' $repo.name 'bugfix'
        SetPermBranch $project.name $group 'CreateBranch' $repo.name 'hotfix'
        SetPermBranch $project.name $group 'CreateBranch' $repo.name 'feature'
        SetPermBranch $project.name $group 'CreateBranch' $repo.name 'support'
        SetPermBranch $project.name $group 'CreateBranch' $repo.name 'team*'

        $group = "Project Administrators"
        SetPermBranch $project.name $group 'CreateBranch' $repo.name 'release'
        SetPermBranch $project.name $group 'CreateBranch' $repo.name 'master'

        $repoPolicies = ($defaultPolicies | ? { $_.Settings.Scope.repositoryId } )
        foreach ($policy in $repoPolicies)
        {
            $oldscope = $policy.Settings.scope[0]
            
            $newscope = @{ }
            $newscope.repositoryId=$repo.id
            if ($oldscope.refName) { $newscope.refName=$oldscope.refName }
            if ($oldscope.matchKind) { $newscope.matchKind=$oldscope.matchKind }

            $result =  CreatePolicy $policy.TypeId $policy.Settings $project.name @($newscope)
        } 

        #break
    }


    

    break;
}