function Retry-Command
{
    param (
    [Parameter(Mandatory=$true)][string]$command, 
    [Parameter(Mandatory=$true)][hashtable]$args, 
    [Parameter(Mandatory=$false)][int]$retries = 5, 
    [Parameter(Mandatory=$false)][int]$secondsDelay = 2
    )
    
    # Setting ErrorAction to Stop is important. This ensures any errors that occur in the command are 
    # treated as terminating errors, and will be caught by the catch block.
    $args.ErrorAction = "Stop"
    
    $retrycount = 0
    $completed = $false
    
    while (-not $completed) {
        try {
            & $command @args
            Write-Verbose ("Command [{0}] succeeded." -f $command)
            $completed = $true
        } catch {
            if ($retrycount -ge $retries) {
                Write-Verbose ("Command [{0}] failed the maximum number of {1} times." -f $command, $retrycount)
                throw
            } else {
                Write-Verbose ("Command [{0}] failed. Retrying in {1} seconds." -f $command, $secondsDelay)
                Start-Sleep $secondsDelay
                $retrycount++
            }
        }
    }
}

function Throw-UserError
{
    Param
    (
		[Parameter(Mandatory=$True)]
		[string]$text
    )

    if ([Environment]::UserName -eq "SYSTEM") {
        throw $Text
    } else {
        Write-Host -ForegroundColor Red $Text
        Read-Host
        Exit
    }
}

function Get-UserInput
{
	Param
	(
		[Parameter(Mandatory=$True)]
		[string]$Id,
		[Parameter(Mandatory=$True)]
		[string]$Text,
		[Parameter(Mandatory=$false)]
		[string]$Default
	)
    
    if ($Default) {
        $Text = ($Text + " (Default " + $Default + ")")
    }
    $reply = Get-Variable -name "Hardcode$Id" -ValueOnly -ErrorAction SilentlyContinue
    if ($reply) {
        if ($reply -eq 'default') {
            $Default
        } else {
            $reply
        }
        Write-Host "$Text : $reply"
    } else {
        if ([Environment]::UserName -eq "SYSTEM") {
            throw "No answer defined for $Text"
        }    
        $reply = Read-Host $Text
        if (!$reply) {
            $Default
        } else {
            $reply
        }
    }
}

function Decrypt-SecureString {
    param(
        [Parameter(Mandatory=$true)]
        [System.Security.SecureString]
        $sstr
    )

    $marshal = [System.Runtime.InteropServices.Marshal]
    $ptr = $marshal::SecureStringToBSTR( $sstr )
    $str = $marshal::PtrToStringBSTR( $ptr )
    $marshal::ZeroFreeBSTR( $ptr )
    $str
} 

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
    $adal = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Services\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null

    # Login to AzureRm
    $SharePointAdminSecurePassword = ConvertTo-SecureString -String $SharePointAdminPassword -AsPlainText -Force
    $SharePointAdminCredential = New-Object System.Management.Automation.PSCredential ($SharePointAdminLoginname, $SharePointAdminSecurePassword)
    $account = Login-AzureRmAccount -Credential $SharePointAdminCredential
    
    $GLOBAL:AadTenant = $account.Context.Tenant.TenantId;
    $adUser = Get-AzureRmADUser -UserPrincipalName $account.Context.Account.Id
    $adUserObjectId = $adUser.Id

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
            },
            @{
              "id" = "a42657d6-7f20-40e3-b6f0-cee03008a62a";
              "type" = "Scope"
            },
            @{
              "id": "5778995a-e1bf-45b8-affa-663a9f3f4d04";
              "type": "Role"
            }
            )
         }
      )} | ConvertTo-Json -Depth 99

    # Invoke-RestMethod will not close the connection properly and as such will only allow 2 subsequent calls to Invoke-RestMethod
    # This is why we use Invoke-WebRequest and getting the response content
    (Invoke-WebRequest -UseBasicParsing -Method PATCH -ContentType 'application/json' -Headers $headers -Uri $ssoUrl -Body $ssoPostData).Content 



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

    (Invoke-WebRequest -UseBasicParsing -Method PATCH -ContentType 'application/json' -Headers $headers -Uri $excelUrl   -Body $excelPostData).Content

    # Add owner to Azure Ad Application
    $excelOwnerUrl = "$graphUrl/$GLOBAL:aadTenant/applications/$($excelAdApp.ObjectID)/`$links/owners?api-version=$apiversion"
    $excelOwnerPostData  = @{
      "url" = "$graphUrl/$GLOBAL:aadTenant/directoryObjects/$adUserObjectId/Microsoft.DirectoryServices.User?api-version=$apiversion"
    } | ConvertTo-Json -Depth 99

    (Invoke-WebRequest -UseBasicParsing -Method POST -ContentType 'application/json' -Headers $headers -Uri $excelOwnerUrl   -Body $excelOwnerPostData).Content


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
    
    (Invoke-WebRequest -UseBasicParsing -Method PATCH -ContentType 'application/json' -Headers $headers -Uri $powerBiUrl -Body $powerBiPostData).Content
}

