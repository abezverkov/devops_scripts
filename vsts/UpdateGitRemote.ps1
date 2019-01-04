param (
    [Parameter(Mandatory=$true)]
    [string] $VstsUrl,

    [Parameter(Mandatory=$true)]
    [switch] $GitlabUrl,

    [Parameter(Mandatory=$false)]
    [switch] $RevertToGitLab = $true
)
$VstsUrl = $VstsUrl -replace 'https://',''
$GitlabUrl = $GitlabUrl -replace 'https://',''

function Split-GitLabRemote ([string]$gitRemote)
{
    if ($gitRemote -eq $null) { return $null }
    $s1 = $origin -split ':'
    if ($s1.Length -ne 2) { return $null }

    $r1 = @()
    $r1 += (($s1)[1] -split '/')[0]
    $r1 += (($s1)[1] -split '/')[1] -replace '.git',''
    return $r1
}

function Split-VstsRemote ([string]$gitRemote)
{
    #https://ezlynx.visualstudio.com/EzLynx/_git/EzLynx
    if ($gitRemote -eq $null) { return $null }
    $s1 = ($origin -replace "https://$VstsUrl/",'') -split '/'
    if ($s1.Length -ne 3) { return $null }

    $r1 = @()
    $r1 += ($s1)[0]
    $r1 += ($s1)[2]
    return $r1
}

function Switch-Remote ([string]$projectName,[string]$repoName)
{
    $source = @('GitLab','Vsts')[$RevertToGitLab]
    $destination = @('Vsts','GitLab')[$RevertToGitLab]

    Write-Host "Backing up $source remote"
    git remote rename 'origin' $source
    if ($LASTEXITCODE -ne 0) { return $LASTEXITCODE } 

    Write-Host "Adding $destination remote"

    $vstsRemote = 'https://{2}/{0}/_git/{1}' -f $projectName,$repoName,$VstsUrl
    $gitlabRemote = 'git@{2}:{0}/{1}.git' -f $projectName,$repoName,$GitlabUrl
    $newRemote = @($vstsRemote,$gitlabRemote)[$RevertToGitLab]

    git remote add 'origin' $newRemote
    if ($LASTEXITCODE -ne 0) { 
        Write-Host "Restoring $source remote"
        git remote remove 'origin'
        git remote rename $source 'origin'
    }
    else {
        Write-Host "Removing $source remote"
        git remote remove $source

        #Write-Host "Fetching all from $destination"
        git fetch --all 

        Write-Host "Resetting upstream"
        $localbranches = (git branch --format '%(refname)') -replace 'refs/heads/',''
        $remotebranches = (git branch -r --format '%(refname)') -replace 'refs/remotes/origin/',''
        $localbranches | ? { $remotebranches -contains $_ } | %{ git branch -u "origin/$_" $_ }         
    } 
}

function ConvertToDir($path) {
    try {
        if ($path -eq '' -or $path -eq $null -or -not(Test-Path $path)) { return ''; }
        $path = Resolve-Path $path;
        if ((Get-Item $path) -is [System.IO.DirectoryInfo])
        {
        	return $path
        }
        else
        {
        	return (Resolve-Path ((Get-Item $path).Directory))
        }
    }
    catch { return ''; }
}

function HasGitDir($dir) {
    $dir = ConvertToDir($dir)
    $gitDir = Join-Path $dir .git 
    $hasGit = (Test-Path $gitDir);
    return $hasGit;
}

function FindGitDirDown($dir) {
    [System.Collections.ArrayList]$gitDirs = @();
    if ($dir -eq '' -or $dir -eq $null) { return $getDirs; }

    $dir = ConvertToDir($dir)
    if (HasGitDir ($dir)) {
        $resolvedDir  = (Resolve-Path $dir)
        $gitDirs.Add($resolvedDir) | Out-Null
        return $gitDirs;
    }
    else
    {
        $range = @(Get-ChildItem $dir -Directory | % { FindGitDirDown($_.FullName) })
        if ($range.Count -gt 0) { $gitDirs.AddRange($range) | Out-Null };
        return $gitDirs;
    }
}

function FindGitDirUp($dir) {
    [System.Collections.ArrayList]$gitDirs = @() #New-Object -Type System.Collections.ArrayList;
    if ($dir -eq '' -or $dir -eq $null) { return $getDirs; }

    $dir = ConvertToDir($dir)
    if (HasGitDir($dir)) {
        $resolvedDir  = (Resolve-Path $dir)
        $gitDirs.Add($resolvedDir) | Out-Null
        return $gitDirs;
    }
    else
    {
        $range = @($dir | Get-Item | % { FindGitDirUp($_.Parent.FullName); })
        if ($range.Count -gt 0) { $gitDirs.AddRange($range) | Out-Null };
        return $gitDirs;
    }
}

function FindGitDirs($dir) {
    if ($dir -eq $null -or $dir -eq '') { $dir = Resolve-Path . }
    [System.Collections.ArrayList]$gitDirs = @(FindGitDirUp($dir));
    if ($gitDirs -ne $null -and $gitDirs.Count -gt 0) { return $gitDirs; }
    if ($Global:GitRepos) {return $Global:GitRepos;}
    [System.Collections.ArrayList]$Global:GitRepos = FindGitDirDown($dir);
    return $Global:GitRepos;
}

#--------------------------------------------------------------------------
# Work
#--------------------------------------------------------------------------
$gitDirectories = FindGitDirs($pwd)

foreach ($gitDir in $gitDirectories) {
    pushd $gitDir
    $origin = git remote get-url origin
    if (($origin -eq $null) -or ($origin -eq ''))
    {
        Write-Error 'No origin found.'
        exit 1
    }
    Write-Host ''
    Write-Host '----------------------------------------------------------------------------------------------------'
    Write-Host $origin
    Write-Host '----------------------------------------------------------------------------------------------------'

    if (-not $RevertToGitLab) {
        if ($origin -match $GitlabUrl) {
            $originSplit = Split-GitLabRemote $origin    
            Switch-Remote $originSplit[0] $originSplit[1]
        }
        else {
            Write-Host 'origin: Already pointed to Vsts' 
        }
    }


    if ($RevertToGitLab) {
        if  ($origin -match $VstsUrl) {
            $originSplit = Split-VstsRemote $origin
            Switch-Remote $originSplit[0] $originSplit[1]
        } 
        else {
            Write-Host 'origin: Already pointed to GitLab' 
        }
    }
    popd
}