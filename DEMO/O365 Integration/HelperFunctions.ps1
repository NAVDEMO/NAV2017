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

function Setup-AadApp
{
    Param
    (
        [string]$publicWebBaseUrl,
        [string]$aadTenant,
        [string]$SharePointAdminLoginname,
        [string]$SharePointAdminPassword,
        [string]$keyValue
    )

    $SharePointAdminSecurePassword = ConvertTo-SecureString -String $SharePointAdminPassword -AsPlainText -Force
    $SharePointAdminCredential = New-Object System.Management.Automation.PSCredential ($SharePointAdminLoginname, $SharePointAdminSecurePassword)
    Login-AzureRmAccount -Credential $SharePointAdminCredential | Out-Null
    
    # Load ADAL Assemblies
    $adal = "${env:ProgramFiles(x86)}\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\Services\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    [System.Reflection.Assembly]::LoadFrom($adal) | Out-Null
    
    if (!($publicWebBaseUrl.EndsWith("/"))) {
        $publicWebBaseUrl += "/"
    }
    
    # Create PSADCredential
    $psadCredential = New-Object Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADPasswordCredential
    $startDate = Get-Date
    $psadCredential.StartDate = $startDate
    $psadCredential.EndDate = $startDate.AddYears(10)
    $psadCredential.KeyId = [guid]::NewGuid()
    $psadCredential.Password = $KeyValue
    
    # Remove "old" AD Application
    Get-AzureRmADApplication -IdentifierUri $publicWebBaseUrl | Remove-AzureRmADApplication -Force
    
    # Create AD Application
    $adApp = New-AzureRmADApplication –DisplayName $publicWebBaseUrl `
                                      -HomePage $publicWebBaseUrl `
                                      -IdentifierUris $publicWebBaseUrl `
                                      -PasswordCredentials $psadCredential `
                                      -ReplyUrls "${publicWebBaseUrl}OAuthLanding.htm"
    
    $applicationId = $adApp.ApplicationId
    $authority = "https://login.microsoftonline.com/$aadTenant"
    
    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2"  # Set well-known client ID for AzurePowerShell
    $resourceAppIdURI = "https://graph.windows.net/" # resource we want to use
    
    # Create Authentication Context tied to Azure AD Tenant
    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
    
    # Acquire token and create authentication headers
    $userCred = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.UserCredential" -ArgumentList $SharePointAdminLoginname, $SharePointAdminSecurePassword
    $authResult = $authContext.AcquireToken($resourceAppIdURI, $clientId, $userCred)
    $authHeader = $authResult.CreateAuthorizationHeader()
    $headers = @{"Authorization" = $authHeader; "Content-Type"="application/json"}    
    
    # Add Required Resource Access
    $url = "https://graph.windows.net/$aadTenant/applications/$($adApp.ObjectID)?api-version=1.6"
    $postData = "{`"requiredResourceAccess`":[{`"resourceAppId`":`"00000009-0000-0000-c000-000000000000`",`"resourceAccess`":[{`"id`":`"4ae1bf56-f562-4747-b7bc-2fa0874ed46f`",`"type`":`"Scope`"}]},{`"resourceAppId`":`"00000002-0000-0000-c000-000000000000`",`"resourceAccess`":[{`"id`":`"311a71cc-e848-46a1-bdf8-97ff7156d8e6`",`"type`":`"Scope`"}]}]}"
    $result = Invoke-RestMethod -Uri $url -Method "PATCH" -Headers $headers -Body $postData 
    $applicationId
}
