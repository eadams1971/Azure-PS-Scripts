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
        $result="Passed Validation"
    }
    return $result

}

function Invoke-ValidateMoveRESTAPI($sourceResourceGroupName, $targetResourceGroupName, $subscriptionId)
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

    $body="{`"resources`": [$request],`"targetResourceGroup`":`"$targetResourceGroupId`"}"
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "bearer $token")

    $endpoint="https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$sourceResourceGroupName/validateMoveResources?api-version=2018-05-01"

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

$sourceResourceGroupName="CNIRG"
$targetResourceGroupName="CNITestRG"

$context = Get-AzureRmContext

$subscriptionId = $context.Subscription.SubscriptionId
$targetResourceGroupId="/subscriptions/$subscriptionId/resourceGroups/$targetResourceGroupName"

#try
#{
    Get-Date
    Write-Host "Processing" $sourceResourceGroupName -NoNewline
    $response = Invoke-ValidateMoveRESTAPI $sourceResourceGroupName $targetResourceGroupName $subscriptionId 
    Write-Host
    $response
    Get-Date
      
#}
#catch
#{
 #   $_
#}




