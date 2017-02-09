function Create-AesManagedObject($key, $IV) {
    $aesManaged = New-Object "System.Security.Cryptography.AesManaged"
    $aesManaged.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aesManaged.Padding = [System.Security.Cryptography.PaddingMode]::Zeros
    $aesManaged.BlockSize = 128
    $aesManaged.KeySize = 256

    if ($IV) {
        if ($IV.getType().Name -eq "String") {
            $aesManaged.IV = [System.Convert]::FromBase64String($IV)
        }
        else {
            $aesManaged.IV = $IV
        }
    }
    if ($key) {
        if ($key.getType().Name -eq "String") {
            $aesManaged.Key = [System.Convert]::FromBase64String($key)
        }
        else {
            $aesManaged.Key = $key
        }
    }
    $aesManaged
}

function Create-AesKey() {
    $aesManaged = Create-AesManagedObject 
    $aesManaged.GenerateKey()
    [System.Convert]::ToBase64String($aesManaged.Key)
}

function Setup-AadApps
{
    Param
    (
        [string]$publicWebBaseUrl,
        [string]$SharePointAdminLoginname,
        [string]$SharePointAdminPassword
    )

    # Load ADAL Assemblies
    $adal = "C:\Program Files\Microsoft Dynamics NAV\$NavVersion\Service\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null

    # Login to AzureRm
    $SharePointAdminSecurePassword = ConvertTo-SecureString -String $SharePointAdminPassword -AsPlainText -Force
    $SharePointAdminCredential = New-Object System.Management.Automation.PSCredential ($SharePointAdminLoginname, $SharePointAdminSecurePassword)
    $account = Add-AzureRmAccount -Credential $SharePointAdminCredential

    $adUserObjectId = 0
    Log "Identify AAD Tenant ID"
    $account.Context.Account.Tenants | % {
        try {
            Log "Try $_"
            $GLOBAL:AadTenant = $_
            Set-AzureRmContext -TenantId $GLOBAL:AadTenant | Out-Null
            $adUser = Get-AzureRmADUser -UserPrincipalName $account.Context.Account.Id
            $adUserObjectId = $adUser.Id
            Log "Success"
            break
        } catch {
            Log "Failure"
        }
    }

    if (!$adUserObjectId) {
        Log -Kind Error "Could not identify Aad Tenant ID"
        exit
    }

    $graphUrl = "https://graph.windows.net"
    $apiversion = "1.6"

    $authority = "https://login.microsoftonline.com/$GLOBAL:aadTenant"
    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2"  # Set well-known client ID for AzurePowerShell
    $resourceAppIdURI = "$graphUrl/" # resource we want to use
    
    # Create Authentication Context tied to Azure AD Tenant
    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
    $userCred = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserCredential" -ArgumentList $SharePointAdminLoginname, $SharePointAdminSecurePassword
    
    # Acquire token and create authentication headers
    $authResult = $authContext.AcquireToken($resourceAppIdURI, $clientId, $userCred)
    $authHeader = $authResult.CreateAuthorizationHeader()
    $headers = @{"Authorization" = $authHeader; "Content-Type"="application/json"}    

    # Remove "old" AD Application
    $IdentifierUri = "${PublicWebBaseUrl}"
    Get-AzureRmADApplication -IdentifierUri $IdentifierUri | Remove-AzureRmADApplication -Force

    # Create AesKey
    $GLOBAL:SsoAdAppKeyValue = Create-AesKey

    # Create PSADCredential
    $psadCredential = New-Object Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADPasswordCredential
    $startDate = Get-Date
    $psadCredential.StartDate = $startDate
    $psadCredential.EndDate = $startDate.AddYears(10)
    $psadCredential.KeyId = [guid]::NewGuid()
    $psadCredential.Password = $GLOBAL:SsoAdAppKeyValue
    
    # Create SSO AD Application
    $ssoAdApp = New-AzureRmADApplication –DisplayName ("NAV 2017 WebClient for "+$publicWebBaseUrl.Split("/")[2]) `
                                         -HomePage $publicWebBaseUrl `
                                         -IdentifierUris $publicWebBaseUrl `
                                         -PasswordCredentials $psadCredential `
                                         -ReplyUrls "$publicWebBaseUrl"
    
    $GLOBAL:SsoAdAppId = $ssoAdApp.ApplicationId

    # Get oauth2 permission id for sso app
    $url = ("$graphUrl/$GLOBAL:aadTenant/applications/$($ssoAdApp.ObjectID)?api-version=$apiversion")
    $result = Invoke-RestMethod -Uri $url -Method "GET" -Headers $headers
    $oauth2permissionid = $result.oauth2Permissions.id
    
    # Add Required Resource Access
    $ssoUrl = "$graphUrl/$GLOBAL:aadTenant/applications/$($ssoAdApp.ObjectID)?api-version=$apiversion"

    $ssoPostData = @{"requiredResourceAccess" = @(
         @{ 
            "resourceAppId" = "00000002-0000-0000-c000-000000000000"; 
            "resourceAccess" = @( @{
              "id" = "311a71cc-e848-46a1-bdf8-97ff7156d8e6";
              "type" = "Scope"
            }
            )
         }
      )} | ConvertTo-Json -Depth 99

    # Invoke-RestMethod will not close the connection properly and as such will only allow 2 subsequent calls to Invoke-RestMethod
    # This is why we use Invoke-WebRequest and getting the response content
    (Invoke-WebRequest -UseBasicParsing -Method PATCH -ContentType 'application/json' -Headers $headers -Uri $ssoUrl -Body $ssoPostData).Content | Out-Null

    # Set Logo Image for App
    $url = "$graphUrl/$GLOBAL:aadTenant/applications/$($ssoAdApp.ObjectID)/mainLogo?api-version=$apiversion"
    $iconpath = Join-Path $PSScriptRootV2 "NAV.png"
    $chars = [char[]][System.IO.File]::ReadAllBytes($iconpath)
    $icon = -join $chars
    (Invoke-WebRequest -UseBasicParsing -Method PUT -ContentType 'image/Png' -Headers $headers -Uri $url -Body $icon).Content | Out-Null


    # Excel Ad App

    # Remove "old" Excel AD Application
    $ExcelIdentifierUri = "${PublicWebBaseUrl}ExcelAddIn"
    Get-AzureRmADApplication -IdentifierUri $ExcelIdentifierUri | Remove-AzureRmADApplication -Force

    # Create AD Application
    $excelAdApp = New-AzureRmADApplication –DisplayName ("Excel AddIn for "+$publicWebBaseUrl.Split("/")[2]) `
                                           -HomePage $publicWebBaseUrl `
                                           -IdentifierUris $ExcelIdentifierUri `
                                           -ReplyUrls $publicWebBaseUrl, "https://az689774.vo.msecnd.net/dynamicsofficeapp/v1.3.0.0/*"

    $GLOBAL:ExcelAdAppId = $excelAdApp.ApplicationId

    # Add Required Resource Access
    $excelUrl = "$graphUrl/$GLOBAL:aadTenant/applications/$($excelAdApp.ObjectID)?api-version=$apiversion"

    $excelPostData = @{
      "oauth2AllowImplicitFlow" = $true;
      "requiredResourceAccess" = @(
         @{ 
            "resourceAppId" = "$GLOBAL:SsoAdAppId"; 
            "resourceAccess" = @( @{
              "id" = "$oauth2permissionid";
              "type" = "Scope"
            })
         },
         @{ 
            "resourceAppId" = "00000002-0000-0000-c000-000000000000"; 
            "resourceAccess" = @( @{
              "id" = "311a71cc-e848-46a1-bdf8-97ff7156d8e6";
              "type" = "Scope"
            })
         }
      )} | ConvertTo-Json -Depth 99

    (Invoke-WebRequest -UseBasicParsing -Method PATCH -ContentType 'application/json' -Headers $headers -Uri $excelUrl   -Body $excelPostData).Content | Out-Null

    # Add owner to Azure Ad Application
    $excelOwnerUrl = "$graphUrl/$GLOBAL:aadTenant/applications/$($excelAdApp.ObjectID)/`$links/owners?api-version=$apiversion"
    $excelOwnerPostData  = @{
      "url" = "$graphUrl/$GLOBAL:aadTenant/directoryObjects/$adUserObjectId/Microsoft.DirectoryServices.User?api-version=$apiversion"
    } | ConvertTo-Json -Depth 99
   
    (Invoke-WebRequest -UseBasicParsing -Method POST -ContentType 'application/json' -Headers $headers -Uri $excelOwnerUrl -Body $excelOwnerPostData -ErrorAction Ignore).Content | Out-Null

    # PowerBI Ad App

    # Remove "old" PowerBI AD Application
    $PowerBiIdentifierUri = "${PublicWebBaseUrl}PowerBI"
    Get-AzureRmADApplication -IdentifierUri $PowerBiIdentifierUri | Remove-AzureRmADApplication -Force

    # Create AesKey
    $GLOBAL:PowerBiAdAppKeyValue = Create-AesKey

    # Create PSADCredential
    $psadCredential = New-Object Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADPasswordCredential
    $startDate = Get-Date
    $psadCredential.StartDate = $startDate
    $psadCredential.EndDate = $startDate.AddYears(10)
    $psadCredential.KeyId = [guid]::NewGuid()
    $psadCredential.Password = $GLOBAL:PowerBiAdAppKeyValue
    
    # Create AD Application
    $powerBiAdApp = New-AzureRmADApplication –DisplayName ("PowerBI Service for "+$publicWebBaseUrl.Split("/")[2]) `
                                             -HomePage $publicWebBaseUrl `
                                             -IdentifierUris $PowerBiIdentifierUri `
                                             -PasswordCredentials $psadCredential `
                                             -ReplyUrls "${publicWebBaseUrl}OAuthLanding.htm"
    
    $GLOBAL:PowerBiAdAppId = $powerBiAdApp.ApplicationId
    
    # Add Required Resource Access
    $powerBiUrl = "$graphUrl/$GLOBAL:aadTenant/applications/$($powerBiAdApp.ObjectID)?api-version=$apiversion"
    $powerBiPostData = @{"requiredResourceAccess" = @(
         @{ 
            "resourceAppId" = "00000009-0000-0000-c000-000000000000"; 
            "resourceAccess" = @( @{
              "id" = "4ae1bf56-f562-4747-b7bc-2fa0874ed46f";
              "type" = "Scope"
            })
         },
         @{ 
            "resourceAppId" = "00000002-0000-0000-c000-000000000000"; 
            "resourceAccess" = @( @{
              "id" = "311a71cc-e848-46a1-bdf8-97ff7156d8e6";
              "type" = "Scope"
            })
         }
      )} | ConvertTo-Json -Depth 99
    
    (Invoke-WebRequest -UseBasicParsing -Method PATCH -ContentType 'application/json' -Headers $headers -Uri $powerBiUrl -Body $powerBiPostData).Content | Out-Null
}

