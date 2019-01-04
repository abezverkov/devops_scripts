param (
    [Parameter(Mandatory=$false)]
    [string] $OctopusAPIKey = $env:OctopusAPIKey,

    [Parameter(Mandatory=$false)]
    [string] $OctopusURL = $env:OctopusURL,

    [Parameter(Mandatory=$true)]
    [string] $SearchText,

    [Parameter(Mandatory=$false)]
    [switch] $MatchEqual = $false
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

Write-Host ""
Write-Host "======================================================="
write-host "Searching LibraryVariableSets"
Write-Host "======================================================="
$lvSets = $c.Repository.LibraryVariableSets.GetAll()
foreach( $lvs in $lvSets)
{
    [Octopus.Client.Model.LibraryVariableSetResource]$lvs = $lvs
    [Octopus.Client.Model.VariableSetResource]$vs = $c.Repository.VariableSets.Get($lvs.VariableSetId)
    foreach ($v in $vs.Variables.GetEnumerator()) 
    {
        [Octopus.Client.Model.VariableResource] $v = $v
        if ($MatchEqual) {
          if (($v.Name -eq $SearchText) -or ( $v.Value -eq $SearchText ))
          {
              Write-Host "Found in $($lvs.Name.PadRight(30))  Name:$($v.Name.PadRight(20))  Value:$($v.Value)  Scope:$($v.Scope)"
          }
        }
        else {
          if (($v.Name -match $SearchText) -or ( $v.Value -match $SearchText ))
          {
              Write-Host "Found in $($lvs.Name.PadRight(30))  Name:$($v.Name.PadRight(20))  Value:$($v.Value)  Scope:$($v.Scope)"
          }
        }
    }
}
Write-Host ""
Write-Host "======================================================="
write-host "Searching Projects"
Write-Host "======================================================="
$projects = $c.Repository.Projects.GetAll()
foreach($p in $projects)
{
    [Octopus.Client.Model.ProjectResource]$p = $p
    [Octopus.Client.Model.VariableSetResource]$vs = $c.Repository.VariableSets.Get($p.VariableSetId)
    foreach ($v in $vs.Variables.GetEnumerator()) 
    {
        [Octopus.Client.Model.VariableResource] $v = $v
        if ($MatchEqual) {
          if (($v.Name -eq $SearchText) -or ( $v.Value -eq $SearchText ))
          {
              Write-Host "Found in $($p.Name.PadRight(30))  Name:$($v.Name.PadRight(30))  Value:$($v.Value)  Scope:$($v.Scope)"
          }
        }
        else {
          if (($v.Name -match $SearchText) -or ( $v.Value -match $SearchText ))
          {
              Write-Host "Found in $($p.Name.PadRight(30))  Name:$($v.Name.PadRight(30))  Value:$($v.Value)  Scope:$($v.Scope)"
          }
        }
    }
}