param (
    [string] $GitLabApiToken = $env:GitLabApiToken,
    [string] $GitLabUrl = $env:GitLabUrl,
    [string] $VstsApiToken = $env:VstsApiToken,
    [string] $VstsUrl = $env:VstsUrl,
    [switch] $WhatIf = $false
)
#'http://gitlab.webcetera.com/ezlynx-data/EzLynx.Data.EzLynxPolicy/merge_requests/11'

pushd "C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\Common7\Tools"
cmd /c "VsDevCmd.bat&set" |
foreach {
  if ($_ -match "=") {
    $v = $_.split("="); set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
  }
}
popd
Write-Host "`nVisual Studio 2017 Command Prompt variables set." -ForegroundColor Yellow


if (-not([bool](Get-Module Team -ListAvailable))) 
{
    Write-Host 'Installing Module: Team'
    Install-Module Team
}
if (-not([bool](Get-Module Team))) 
{
    Write-Host 'Loading Module: Team'
    Import-Module Team
}
Add-TeamAccount -Account $VstsUrl -PersonalAccessToken $VstsApiToken

$startDir = $pwd

# Project List
$gitlabHeaders =  @{ 'PRIVATE-TOKEN'=$GitLabApiToken } 
$groups = Invoke-RestMethod -Headers $gitlabHeaders -Uri "$GitLabUrl/api/v4/groups"
foreach ($group in $groups)
{
    Write-Host ''
    Write-Host '================================================================================'
    Write-Host $group.path
    Write-Host '================================================================================'

    $groupDir = Join-Path $startDir $group.path
    if (-not(Test-Path $groupDir)) { md $groupDir }
    cd $groupDir | Out-Null

    $vstsProject = Get-Project -ProjectName $group.path -ErrorAction SilentlyContinue
    if (-not($vstsProject))
    {
        Write-Host ('Create VSTS Project {0}' -f $group.path)
        if (-not($WhatIf)) {
            $vstsProject = Add-Project -ProjectName $group.path
        }
    }
    Set-DefaultProject -Project $group.path

    $projects = Invoke-RestMethod -Headers $gitlabHeaders -Uri "$GitLabUrl/api/v4/groups/$($group.id)/projects"
    foreach ($project in $projects)
    {
        $projectDir = Join-Path $groupDir ('{0}.git' -f $project.path)
        if (-not(Test-Path $projectDir)) 
        { 
            Write-Host ('Cloning {0}' -f $project.ssh_url_to_repo)
            if (-not($WhatIf)) {
                git clone --mirror $project.ssh_url_to_repo
            }
        }

        $vstsRepo = Get-GitRepository -ProjectName $group.path -Name $project.path -ErrorAction SilentlyContinue
        if (-not($vstsRepo))
        {
            Write-Host ('Create VSTS Repo {0} in {1}' -f $project.path,$group.path)
            if (-not($WhatIf)) {
                $vstsRepo = Add-GitRepository --ProjectName $group.path --Name $project.path
            }
        }
    }
    #break
}
cd $startDir

