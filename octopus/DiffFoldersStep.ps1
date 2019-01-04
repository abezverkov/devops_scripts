#=======================================================================================================================================
# This is the PostDeploy script for Running Katalon from the command line.
# 
# There are three main requirements for this file
# - Replace variables in test cases globals
# - Run Katalon tests
# - Collect results as artifacts and return appropriate exit code (Pass/Fail)
#
#=======================================================================================================================================

function TryNew-OctopusArtifact ($Path, $Name)
{
     Write-Verbose "Creating artifact $Name from:$Path"
     if ($octopusPresent) {
        New-OctopusArtifact -Path $Path -Name $Name
     }
     else {
        Write-Verbose "Octopus not present. Skipping Artifacts"
     }
}

Write-Verbose "============================================================================================="
Write-Verbose "Testing Octopus Environment"
$octopusPresent = (gcm New-OctopusArtifact -ErrorAction SilentlyContinue) -ne $null
if (!$octopusPresent)
{   
    # Testing
    $OctopusParameters = @{} 
    $OctopusParameters['CompareFiles.CurrentDirectory'] = 'C:\Temp\OldConfig'
    $OctopusParameters['CompareFiles.PreviousDirectory'] = 'C:\Temp\NewConfigs'
    $OctopusParameters['CompareFiles.OutputPath'] = 'configs.patch'
    $OctopusParameters['CompareFiles.ComparePatterns'] = @"
*.config
"@
}

Write-Verbose "============================================================================================="
Write-Verbose "Setting up variables"

$currentDir = Get-Item $OctopusParameters['CompareFiles.CurrentDirectory']
Write-Verbose "currentDir:$currentDir"

$previousDir = Get-Item $OctopusParameters['CompareFiles.PreviousDirectory']
Write-Verbose "previousDir:$previousDir"

#this should be in the work directory
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OctopusParameters['CompareFiles.OutputPath'])
Write-Verbose "outputPath:$outputPath"

$comparePatterns = $OctopusParameters['CompareFiles.ComparePatterns'] -split "`r`n|`r|`n"
Write-Verbose "comparePatterns:$comparePatterns"

#============================================================================================================

$comparePath  = (Join-Path $currentDir.Parent.FullName 'compare')
if (Test-Path $comparePath) { 
    rd $comparePath -Recurse -Force  #-ErrorAction SilentlyContinue 
}
md $comparePath -ErrorAction SilentlyContinue | Out-Null
$compareDir = Get-Item $comparePath
cd $compareDir

$compareDir1 = md (Join-Path $compareDir 'current') -ErrorAction SilentlyContinue
$compareDir2 = md (Join-Path $compareDir 'previous') -ErrorAction SilentlyContinue

$comparePatterns |  % {
    xcopy /s (Join-Path $previousDir $_) $compareDir1 | Out-Null
    xcopy /s (Join-Path $currentDir $_) $compareDir2 | Out-Null
}

$currentDirExt = (dir $currentDir -Recurse -File -ErrorAction SilentlyContinue).Extension | select -Unique
$previousDirExt = (dir $previousDir -Recurse -File -ErrorAction SilentlyContinue).Extension | select -Unique
$allExt = ($currentDirExt +  $previousDirExt) | select -Unique 

#$excludePath = "diff.exclude"
#$diffArgs = @('*.Octopus.config')
#$allExt | % { $diffArgs += "*$_" } 
#$diffArgs |? { $_ -notin $comparePatterns } | Out-File $excludePath -Encoding unicode

diff.exe -ur -x '*.Octopus.*' $compareDir1.Name $compareDir2.Name | Out-File $outputPath
TryNew-OctopusArtifact -Path $outputPath -Name "$outputPath"

# Clean up
cd $currentDir
if ($octopusPresent) { rd $compareDir -Recurse -Force } 


