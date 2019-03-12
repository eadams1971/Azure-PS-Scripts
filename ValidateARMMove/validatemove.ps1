function Get-AzureRmCachedAccessToken([Microsoft.Azure.Commands.Profile.Models.PSAzureContext]$context)
{   
  if(-not (Get-Module AzureRm.Profile)) {
    Import-Module AzureRm.Profile
  }  
  $azureRmProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
  $profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient($azureRmProfile)
  Write-Debug ("Getting access token for tenant" + $context.Subscription.TenantId)
  $token = $profileClient.AcquireAccessToken($context.Subscription.TenantId)
  $token.AccessToken
}

function Process-ResponseStatus($response, $headers)
{
    if($response.StatusCode -eq 202)
    {
        #Get long-running result
        Get-LongRunningResult $response.Headers["Location"] $headers
    }   
    else
    {
        if($response.StatusCode -eq 204)
        {
            #Success
            Write-Host "Success"
        }
        else
        {
            #Failure
            Write-Host $response.RawContent
        }
    } 
}

function Get-LongRunningResult($endpoint, $headers)
{        
    do
    {
        Write-Host "." -NoNewline
    
        $result = Invoke-WebRequest $endpoint -Method Get -Headers $headers -ContentType "application/json" #-Verbose
        if($result.StatusCode -eq 202)
        {
            Start-Sleep $result.Headers["Retry-After"]               
        }
    } while($result.StatusCode -eq 202)
    if ($result.StatusCode -eq 204) 
    { 
        $result="  Validation Successful"
    }
    return $result

}

function Invoke-ValidateMoveRESTAPI($sourceResourceGroupName, $sourcesubscriptionid, $targetResourceGroupName, $subscriptionId, $context)
{
    #Get all top-level resources
    $resourceIds = Get-AzureRmResource -ResourceGroupName $sourceResourceGroupName | ?{$_.ParentResource -eq $null} | Select -Property ResourceId

    $request = ""
    foreach($resourceId in $resourceIds)
    {    
        $request += "`"" + $resourceId.ResourceId + "`","
    }

    $request = $request.Remove($request.Length -1, 1)

    $token=Get-AzureRmCachedAccessToken $context

    $targetResourceGroupId="/subscriptions/$targetsubscriptionId/resourceGroups/$targetResourceGroupName"

    $body="{`"resources`": [$request],`"targetResourceGroup`":`"$targetResourceGroupId`"}"
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "bearer $token")

    $endpoint="https://management.azure.com/subscriptions/$sourcesubscriptionId/resourceGroups/$sourceResourceGroupName/validateMoveResources?api-version=2018-05-01"

    $response = $null
    try
    {
        $response = Invoke-WebRequest $endpoint -Method Post -Headers $headers -Body $body -ContentType "application/json" #-Verbose
        Process-ResponseStatus $response $headers
    }
    catch
    {
        return $_.ErrorDetails.Message
    }

}

function DoIt()
{
    #$sourceResourceGroupName=""
    #$targetResourceGroupName=""
    #$subscriptionId = $context.Subscription.SubscriptionId

    Write-Host "Use the Sign-In window to logon to your subscription"
    Write-Host "NOTE: The Sign-In window may be hidden behind other windows" -ForegroundColor Red
    Write-Host

    $login = Connect-AzureRmAccount
    $context = Get-AzureRmContext

    Get-AzureRmSubscription | Select Name, Id | FT
    $sourcesubscriptionid = Read-Host -Prompt "Enter the subscriptionid of the subscription of source resource group"
    #$null = Get-AzureRmSubscription -SubscriptionId $sourcesubscriptionid | Set-AzureRMContext
    
    Get-AzureRmResourceGroup | Select ResourceGroupName | FT
    $sourceResourceGroupName = Read-Host -Prompt "Enter the name of source resource group"
     
    Get-AzureRmSubscription | Select Name, Id | FT
    $targetsubscriptionid = Read-Host -Prompt "Enter the subscriptionid of the subscription of target resource group"
    $null = Get-AzureRmSubscription -SubscriptionId $targetsubscriptionid | Set-AzureRMContext
    
    Get-AzureRmResourceGroup | Select ResourceGroupName | FT
    $targetResourceGroupName = Read-Host -Prompt "Enter the name of target resource group"
    
    #reset bask to original context
    $null = Get-AzureRMSubscription -SubscriptionId $sourcesubscriptionid | Set-AzureRmContext

    Write-Output ("{0}" -f (Get-Date))
    
    Write-Host
    Write-Host "Validating move of " $sourceResourceGroupName " to " $targetResourceGroupName -NoNewline
    
    $response = Invoke-ValidateMoveRESTAPI $sourceResourceGroupName $sourcesubscriptionid $targetResourceGroupName $targetSubscriptionid $context
    $response
    
    Write-Output ("{0}" -f (Get-Date))
    
}

DoIt


