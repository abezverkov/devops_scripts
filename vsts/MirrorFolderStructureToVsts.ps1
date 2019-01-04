param (
    [Parameter(Mandatory=$false)]
    [string] $VstsUrl = $env:VstsUrl,
    [Parameter(Mandatory=$false)]
    [string] $DirectoryMatch
)

if (-not($DirectoryMatch))
{
    $mirrorDirs = @(dir . -Directory -Recurse | where Extension -eq '.git')
}
else {
    $mirrorDirs = @(dir . -Directory -Recurse | where Extension -eq '.git' | where FullName -match $DirectoryMatch)
}
$startDir = $pwd
foreach ($mirror in $mirrorDirs)
{
    Write-Host '-------------------------------------------------------'
    cd $mirror.FullName
    Write-Host $pwd

    $current = (gi .)
    $repoName =  $current.Name -replace $current.Extension
    $projectName = $current.Parent.Name
    $name = "$projectName/$repoName"

    
    if ((git.exe remote) -notcontains 'vsts')
    {
        $remoteAddress = [uri]::EscapeUriString("$VstsUrl/$projectName/_git/$repoName")
        Write-Host "$name : Adding vsts remote:$remoteAddress"
        git.exe remote add vsts $remoteAddress 2>&1
    }

    Write-Host "$name : Fetching origin"
    git.exe remote update origin -p > NULL 2>&1
    Write-Host "$name : Check Write Status"
    git.exe push --dry-run > NULL 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        Write-Warning "$name : Repository set to Read-Only"
    }
    else {
        Write-Host "$name : Pushing --mirror vsts"
        git.exe push --mirror vsts -q
    }
    cd $startDir
}
