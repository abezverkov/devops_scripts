param (
    [Parameter(Mandatory=$false)]
    [string] $ServiceName,

    [Parameter(Mandatory=$false)]
    [string] $UserName,

    [Parameter(Mandatory=$false)]
    [string] $Password,

    [Parameter(Mandatory=$false)]
    [string] $DomainName = $env:USERDOMAIN
)

Write-Host "$env:ComputerName"
$objUser = [ADSI]("WinNT://$DomainName/$UserName")
$objGroup = [ADSI]("WinNT://$env:ComputerName/Administrators")
if (!$objGroup.IsMember($objUser.PSBase.Path)) {
    $objGroup.PSBase.Invoke("Add",$objUser.PSBase.Path) | Out-Null
}


#Get SID from current user 
$objUser = New-Object System.Security.Principal.NTAccount("$DomainName\$UserName") 
$strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier]) 
$MySID = $strSID.Value 
Write-Host "MySID=$MySID" -ForegroundColor Cyan
 
#Get list of currently used SIDs 
cd C:\temp

$infTemplate = @(@'
[Unicode]
Unicode=yes
[System Access]
[Event Audit]
[Registry Values]
[Version]
signature="$CHICAGO$"
Revision=1
[Privilege Rights] 
'@ -split '\r\n')

Write-Host 'secedit /export /cfg tempexport.inf'
secedit /export /cfg tempexport.inf 

$curSIDs = Select-String tempexport.inf -Pattern "SeServiceLogonRight" 
$Sids = $curSIDs.line 
Write-Host "Sids=$Sids" -ForegroundColor Cyan

$infTemplate += "$Sids,*$MySID"
$infTemplate | Out-File LogOnAsAServiceTemplate.inf

Write-Host 'secedit /import /db secedit.sdb /cfg LogOnAsAServiceTemplate.inf' -ForegroundColor Cyan
secedit /import /db secedit.sdb /cfg LogOnAsAServiceTemplate.inf

Write-Host 'secedit /configure /db secedit.sdb' -ForegroundColor Cyan
secedit /configure /db secedit.sdb 
 
Write-Host  'gpupdate /force '  -ForegroundColor Cyan
gpupdate /force 
 
del "LogOnAsAServiceTemplate.inf" -force 
del "secedit.sdb" -force 
del "tempexport.inf" -force

Write-Host 'sc.exe config' -ForegroundColor Cyan
Get-Service $ServiceName | % { sc.exe config $_ obj="$DomainName\$UserName" password=$Password }