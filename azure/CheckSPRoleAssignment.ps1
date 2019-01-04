param (
    [Parameter(Mandatory=$false)]
    [string] $SPDisplayNameLike = 'Workflow-*'
)

$workFlowSps = Get-AzureRmADServicePrincipal | where DisplayName -like $SPDisplayNameLike
$subscriptions = Get-AzureRmSubscription;

foreach($sub in $subscriptions)
{
    Write-Host ''
    Write-Host '============================================================================='
    Write-Host "Testing $($sub.Name,$sub.Id)"
    Write-Host '============================================================================='
    Set-AzureRmContext -Subscription $sub

    foreach($sp in $workFlowSps)
    {
        '-------------------------------------------------------------------'
        $sp.DisplayName
        Get-AzureRmRoleAssignment -ObjectId $sp.Id #Workflow-TEST
    }

#    Write-Host "Get-AzureRmRoleDefinition"
#    $workFlowRoles = Get-AzureRmRoleDefinition | Where Name -like 'Workflow*'
#    foreach($roledef in $workFlowRoles)
#    {
#        Get-AzureRmRoleAssignment -RoleDefinitionId $roledef.Id
#    }
}
