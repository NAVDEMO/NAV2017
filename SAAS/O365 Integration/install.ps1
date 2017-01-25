$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$verbosePreference =  'SilentlyContinue'
$errorActionPreference = 'Stop'
. (Join-Path $PSScriptRootV2 '..\Common\HelperFunctions.ps1')

Clear
Log -kind Emphasis -OnlyInfo "Welcome to the O365 Integration Installation script."
Log -kind Info -OnlyInfo ""
Log -kind Info -OnlyInfo "This script will help you setup O365 integration in your Microsoft Dynamics NAV DEMO Environment."
Log -kind Info -OnlyInfo "The script will help you:"
Log -kind Info -OnlyInfo "- Setup AAD App in Azure AD for Single Signon with O365."
Log -kind Info -OnlyInfo "- Create AAD WebClient instance."
Log -kind Info -OnlyInfo "- Setup AAD Apps in Azure AD for the Excel AddIn and the PowerBI service."
Log -kind Info -OnlyInfo "- Uninstall and unpublish previous versions of the O365 Extension."
Log -kind Info -OnlyInfo "- Publish and install the O365 Extension."
Log -kind Info -OnlyInfo "- Remove X-FRAME option to allow NAV parts to be hosted in SharePoint."
Log -kind Info -OnlyInfo "- Create Provider Hosted App for SharePoint."
Log -kind Info -OnlyInfo "- Create SharePoint portal with NAV App Parts.."
Log -kind Info -OnlyInfo ""
Log -kind Info -OnlyInfo "The landing page will automatically be updated."
Log -kind Info -OnlyInfo ""

Log "Read Settings"
$HardcodeFile = (Join-Path $PSScriptRootV2 'HardcodeInput.ps1')
if (Test-Path -Path $HardcodeFile) {
    . $HardcodeFile
}
$DVDfolder = (Get-ChildItem -Path "C:\NAVDVD" -Directory | where-object { Test-Path -Path (Join-Path $_.FullName "WindowsPowerShellScripts") -PathType Container } | Select-Object -First 1).FullName
$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name
$DatabaseFolder = Join-Path (Get-ChildItem -Path "$DVDFolder\SQLDemoDatabase\CommonAppData\Microsoft\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).FullName "Database"
$DatabaseName = (Get-ChildItem -Path $DatabaseFolder -Filter "*.bak" -File).BaseName
. (Join-Path $PSScriptRootV2 'AppSettings.ps1')

Log "NAV Version: $NavVersion"
Log "Database Name: [$DatabaseName]"

if (Get-Module -ListAvailable -Name AzureRM) {
    Log "AzureRM Powershell module already installed"
} else {
    Log "Install AzureRM PowerShell Module"
    Unregister-PackageSource -name "PSGallery" -ErrorAction Ignore
    Log "Package Source Unregistered"
    if ([System.Environment]::OSVersion.Version.Major -lt 10) {
        Register-PackageSource -Name "PSGallery" -Location "https://www.powershellgallery.com/api/v2/" -ProviderName PowerShellGet -Trusted
    } else {
        Register-PackageSource -Name "PSGallery" -ProviderName PowerShellGet -Trusted | Out-Null
    }
    Log "Package Source Registered"
    Install-Module -Name "AzureRM" -Repository "PSGallery" -Force
    Log "AzureRM module Installed"
    Import-Module -Name "AzureRM"
}

Log "Import Modules"
. (Join-Path $PSScriptRootV2 '..\Profiles.ps1')
. (Join-Path $PSScriptRootV2 'HelperFunctions.ps1')
. (Join-Path $PSScriptRootV2 'createportal.ps1')
. ("c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1") | Out-null
. ("C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\NavModelTools.ps1") | Out-Null
Import-module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking
Import-Module (Join-Path $DVDFolder "WindowsPowerShellScripts\Cloud\NAVAdministration\NAVAdministration.psm1")
Import-Module (Join-Path $DVDFolder "WindowsPowerShellScripts\NAVOffice365Administration\NAVOffice365Administration.psm1")

Log "Read CustomSettings.config"
$CustomSettingsConfigFile = "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\CustomSettings.config"
$config = [xml](Get-Content $CustomSettingsConfigFile)
$thumbprint = $config.SelectSingleNode("//appSettings/add[@key='ServicesCertificateThumbprint']").value
$publicSoapBaseUrl = $config.SelectSingleNode("//appSettings/add[@key='PublicSOAPBaseUrl']").value
$publicWebBaseUrl = $config.SelectSingleNode("//appSettings/add[@key='PublicWebBaseUrl']").value
$serverInstance = $config.SelectSingleNode("//appSettings/add[@key='ServerInstance']").value
$multitenant = ($config.SelectSingleNode("//appSettings/add[@key='Multitenant']").value -ne "false")
$DatabaseServer = $config.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").value
$ARRisConfigured = (Get-WebBinding -Name "Microsoft Dynamics NAV 2017 Weblogin  Client" | Where-Object { $_.bindingInformation -eq "*:8443:" })

Log "Server Instance: $ServerInstance"

Log "Read Web Config"
$WebConfigFile = "C:\inetpub\wwwroot\$ServerInstance\Web.config"
$WebConfig = [xml](Get-Content $WebConfigFile)
$dnsidentity = $WebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='DnsIdentity']").Value

# Is it OK to apply this package at this time
if (!$thumbprint) {
    throw "You need to run the initialize Server script before applying demo packages."
}

if ($multitenant) {
    throw "Server is multi-tenant. You need to apply this package before installing multi-tenancy."
}

$languages = @{ 
    "da-DK" = "Danish - Denmark";
    "de-AT" = "German - Austria";
    "de-CH" = "German - Switzerland";
    "de-DE" = "German - Germany";
    "cs-CZ" = "Czech - Czech Republic";
    "en-AU" = "English - Australia"; 
    "en-CA" = "English - Canada";
    "en-GB" = "English - United Kingdom";
    "en-IN" = "English - India";
    "en-NZ" = "English - New Zealand";
    "en-US" = "English - United States";
    "es-ES" = "Spanish - Spain";
    "es-MX" = "Spanish - Mexico";
    "fi-FI" = "Finnish - Finland";
    "fr-BE" = "French - Belgium";
    "fr-CA" = "French - Canada";
    "fr-CH" = "French - Switzerland";
    "fr-FR" = "French - France";
    "is-IS" = "Icelandic - Iceland";
    "it-CH" = "Italian - Switzerland";
    "it-IT" = "Italian - Italy";
    "nb-NO" = "Norwegian (Bokmål) - Norway";
    "nl-BE" = "Dutch - Belgium";
    "nl-NL" = "Dutch - Netherlands";
    "ru-RU" = "Russian - Russia";
    "sv-SE" = "Swedish - Sweden";
}

$regionCodes = @{ 
 "AT" = "de-AT";
 "AU" = "en-AU"; 
 "BE" = "nl-BE";
 "CH" = "de-CH";
 "CZ" = "cs-CZ";
 "DE" = "de-DE";
 "DK" = "da-DK";
 "ES" = "es-ES";
 "FI" = "fi-FI";
 "FR" = "fr-FR";
 "GB" = "en-GB";
 "IN" = "en-IN";
 "IS" = "is-IS";
 "IT" = "it-IT";
 "NA" = "en-US";
 "NL" = "nl-NL";
 "NO" = "nb-NO";
 "NZ" = "en-NZ";
 "RU" = "ru-RU";
 "SE" = "sv-SE";
 "W1" = "en-US";
 "US" = "en-US";
 "MX" = "es-MX";
 "CA" = "en-CA";
 "DECH" = "de-CH";
 "FRBE" = "fr-BE";
 "FRCA" = "fr-CA";
 "FRCH" = "fr-CH";
 "ITCH" = "it-CH";
 "NLBE" = "nl-BE";
}

$NAVAdminUser = Get-UserInput -Id NavAdminUser -Text "NAV administrator username" -Default "admin"
$SharePointAdminLoginname = ""
do {
    $Ok = $false
    $SharePointAdminLoginname = Get-UserInput -Id SharePointAdminLoginname -Text "Office 365 administrator E-mail (example: somebody@cronus.onmicrosoft.com)" -default $SharePointAdminLoginName
    $SharePointAdminPassword = Get-SecureUserInput -Id SharePointAdminPassword -Text "Office 365 administrator Password"
    $SharePointAdminSecurePassword = ConvertTo-SecureString -String $SharePointAdminPassword -AsPlainText -Force
    $SharePointAdminCredential = New-Object System.Management.Automation.PSCredential ($SharePointAdminLoginname, $SharePointAdminSecurePassword)
    $account = Add-AzureRmAccount -Credential $SharePointAdminCredential -ErrorAction Ignore
    if ($account) {
        $Ok = ($account.Context.Account.Tenants.Count -gt 0)
        if (!$Ok) {
            Log -kind Warning "Cannot use this Office 365 Account, there are no AAD tenants defined."
            $SharePointAdminLoginname = ""
        }
    } else {
        Log -kind Warning "Wrong Office 365 Account Email or Password"
    }
} while (!$Ok)

$CreateSharePointPortal = ((Get-UserInput -Id CreateSharePointPortal -Text "Do you want to create a demo SharePoint Portal with App Parts from NAV? (Yes/No)" -Default "Yes") -eq "Yes")
$SharePointMultitenant = $false

if ($CreateSharePointPortal) {

    $SharePointMultitenant = ((Get-UserInput -Id SharePointMultitenant -Text "Is the SharePoint portal going to be integrated to a multitenant NAV? (Yes/No)" -Default "No") -eq "Yes")

    $SharePointUrl = ""
    if ($SharePointAdminLoginname.EndsWith(".onmicrosoft.com") -and $SharePointAdminLoginname.Contains("@")) {
        $idx = $SharePointAdminLoginname.LastIndexOf("@")
        $SharePointUrl = ('https://' + $SharePointAdminLoginname.Substring($idx+1, $SharePointAdminLoginname.Length-$idx-17) + '.sharepoint.com')
    }
    do {
        $err = $false
        $SharePointUrl = Get-UserInput -Id SharePointUrl -Text "SharePoint Base URL (example: https://cronus.sharepoint.com)" -Default $SharePointUrl
        while ($SharePointUrl.EndsWith('/')) {
            $SharePointUrl = $SharePointUrl.SubString(0, $SharePointUrl.Length-1)
        }
        if ((!$SharePointUrl.ToLower().EndsWith(".sharepoint.com")) -or (!$SharePointUrl.ToLower().StartsWith("https://"))) {
            $err = $true
            Log -kind Error "SharePoint URL must be formed like: https://tenant.sharepoint.com"
        }
    } while ($err)

    do {
        Log -kind Emphasis -OnlyInfo "Languages:"
        $languages.GetEnumerator() | % { Log -OnlyInfo ($_.Name + " = " + $_.Value) }
        $SharePointLanguage = Get-UserInput -Id SharePointLanguage -Text "SharePoint Language" -Default $regionCodes[$Language]
        $LanguageFile = (Join-Path $PSScriptRootV2 "O365Translations\$SharePointLanguage.ps1")
    } while (!(Test-Path $LanguageFile))
    
    if ($SharePointMultitenant) {
        $SharePointSite = "default"
        ('$SharePointInstallFolder = "' + $PSScriptRootV2 + '"')            | Add-Content "C:\DEMO\Multitenancy\HardcodeInput.ps1"
        ('$SharePointUrl = "' + $SharePointUrl + '"')                       | Add-Content "C:\DEMO\Multitenancy\HardcodeInput.ps1"
        ('$SharePointLanguageFile = "' + $LanguageFile + '"')               | Add-Content "C:\DEMO\Multitenancy\HardcodeInput.ps1"
    } else {
        $SharePointSite = Get-UserInput -Id SharePointSite -Text "SharePoint Site Name" -Default ($env:COMPUTERNAME.ToLower())
    }
    
    . $LanguageFile
    
    $SharePointTimezoneId = Get-UserInput -Id SharePointTimezoneId -Text "SharePoint Timezone ID (see http://blog.jussipalo.com/2013/10/list-of-sharepoint-timezoneid-values.html)" -Default $SharePointTimezoneId
    $SharePointSiteTitle = "Team Site"
}

$publicWebBaseUrl = $publicWebBaseUrl.Replace("/$ServerInstance/", "/AAD/")

# Create new Web Server Instance
if (!(Test-Path "C:\inetpub\wwwroot\AAD")) {

    Setup-AadApps -publicWebBaseUrl $publicWebBaseUrl -SharePointAdminLoginname $SharePointAdminLoginname -SharePointAdminPassword $SharePointAdminPassword

    ('$CreateSharePointPortal = $'+$SharePointMultitenant)            | Add-Content "C:\DEMO\Multitenancy\HardcodeInput.ps1"
    ('$SharePointAdminLoginName = "'+$SharePointAdminLoginName+'"')   | Add-Content 'C:\DEMO\Multitenancy\HardcodeInput.ps1'
    ('$SharePointAdminPassword = "' + $SharePointAdminPassword + '"') | Add-Content "C:\DEMO\Multitenancy\HardcodeInput.ps1"

    $AcsUri = "https://login.windows.net/Common/wsfed?wa=wsignin1.0%26wtrealm=$publicWebBaseUrl"
    $federationMetadata = "https://login.windows.net/Common/federationmetadata/2007-06/federationmetadata.xml"

    Log "Set FederationMetada $federationMetadata"
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "ClientServicesFederationMetadataLocation" -KeyValue $federationMetadata -WarningAction Ignore
    
    Log "Create NAV WebServerInstance with ACSUri $ACSUri"
    New-NAVWebServerInstance -ClientServicesCredentialType "AccessControlService" -ClientServicesPort 7046 -DnsIdentity $dnsidentity -Server "localhost" -ServerInstance $serverInstance -WebServerInstance "AAD"

    # Change AAD Web.config
    $NAVWebConfigFile = "C:\inetpub\wwwroot\$ServerInstance\Web.config"
    $NAVWebConfig = [xml](Get-Content $NAVWebConfigFile)

    $AADWebConfigFile = "C:\inetpub\wwwroot\AAD\Web.config"
    $AADWebConfig = [xml](Get-Content $AADWebConfigFile)
    $AADWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='HelpServer']").value = $NAVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='HelpServer']").value
    $AADWebConfig.Save($AADWebConfigFile)
    
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "AppIdUri" -KeyValue $publicWebBaseUrl -WarningAction Ignore
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "PublicWebBaseUrl" -KeyValue $publicWebBaseUrl -WarningAction Ignore
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "AzureActiveDirectoryClientId" -KeyValue $GLOBAL:ssoAdAppId -WarningAction Ignore
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "AzureActiveDirectoryClientSecret" -KeyValue $GLOBAL:SsoAdAppKeyValue -WarningAction Ignore
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "ExcelAddInAzureActiveDirectoryClientId" -KeyValue $GLOBAL:ExcelAdAppId -WarningAction Ignore
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "WSFederationLoginEndpoint" -KeyValue $ACSUri -WarningAction Ignore
    Set-NAVServerUser -ServerInstance $serverInstance -UserName $NAVAdminUser -AuthenticationEmail $SharePointAdminLoginname -WarningAction Ignore

    Log "Uninstall and unpublish NAV App if already installed"
    UnInstall-NAVApp -ServerInstance $serverInstance -Name $AppName -ErrorAction Ignore
    UnPublish-NAVApp -ServerInstance $serverInstance -Name $AppName -ErrorAction Ignore
    
    # Install pre-requisites if they exist
    $NavIde = "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe"
    $PrereqFile = Join-Path $PSScriptRootV2 "$Language Prereq.fob"
    if (Test-Path -Path $PrereqFile) {
        Log "Import pre-requisite .fob file"
        Import-NAVApplicationObject -DatabaseServer 'localhost\NAVDEMO' -DatabaseName $DatabaseName -Path $PrereqFile -SynchronizeSchemaChanges Force -NavServerName localhost -NavServerInstance $ServerInstance -NavServerManagementPort 7045 -ImportAction Overwrite -Confirm:$false
    }

    # Publish and Install NAV App
    $NavIde = "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe"
    Log "Publish O365 Integration App"
    Publish-NAVApp -ServerInstance $serverInstance -Path $AppFilename -SkipVerification
    Log "Install O365 Integration App"
    Install-NAVApp -ServerInstance $serverInstance -Name $AppName
    
    # Copy misc. files
    Copy-Item (Join-Path $PSScriptRootV2 "Office.png") "C:\inetpub\wwwroot\AAD\WebClient\Resources\Images\Office.png" -Force
    Copy-Item (Join-Path $PSScriptRootV2 "myapps.png") "C:\inetpub\wwwroot\AAD\WebClient\Resources\Images\myapps.png" -Force
    
    # Restart NAV Service Tier
    Log "Restart Service Tier"
    Set-NAVServerInstance -ServerInstance $serverInstance -Restart
    
    Log "Create webserviceuser for O365 setup"
    $wsusername = 'webserviceuser'
    $user = get-navserveruser $serverInstance | where-object { $_.UserName -eq $wsusername }
    if (!($user)){
        new-navserveruser $serverInstance -UserName $wsusername -CreateWebServicesKey -LicenseType External
        New-NAVServerUserPermissionSet $serverInstance -UserName $wsusername -PermissionSetId SUPER
        $user = get-navserveruser $serverInstance | where-object { $_.UserName -eq $wsusername }
    }

    # Invoke Web Service
    Log "Create Web Service Proxy"
    $securePassword = ConvertTo-SecureString -String $user.WebServicesKey -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($wsUsername, $securePassword)
    $Uri = ("$publicSoapBaseUrl" + "$Company/Codeunit/AzureAdAppSetup")
    $proxy = New-WebServiceProxy -Uri $Uri -Credential $credential
    # Timout 1 hour
    $proxy.timeout = 60*60*1000
    Log "Setup Azure Ad App"
    $proxy.SetAzureAdAppSetup($GLOBAL:PowerBiAdAppId, $GLOBAL:PowerBiAdAppKeyValue)
    
    # Modify Default.aspx to include a link to SharePoint
    Log "Modify default.aspx"
    
    $insertcode = ""
    if ($CreateSharePointPortal) {
        $SharePointSiteUrl = "$SharePointUrl/sites/$SharePointSite"
        $insertcode = "var officeDiv = InsertTopBarButton(helpDiv, ""Resources/Images/Office.png"", ""$SharePointSiteUrl"", ""_self"", ""Go to Office 365"");"
    }
    
    $codesnippet = "if (window.location.href.toLowerCase().indexOf(""/aad/"") >= 0) {
      var intRef = setInterval(AddTopBarButtons, 1000);
    }
    
    function AddTopBarButtons() {
      var helpDivs= document.getElementsByClassName(""system-help"");
      if (helpDivs.length > 0) {
        clearInterval(intRef);
        var helpDiv = helpDivs[helpDivs.length-1];
        $insertCode   
        var productnameDivs = document.getElementsByClassName(""productname"");
        productnameDiv = productnameDivs[0];
        if (productnameDivs.length > 0) {
          var waffleDiv = InsertTopBarButton(productnameDiv, ""Resources/Images/MyApps.png"", ""https://portal.office.com/myapps"", ""_self"", ""Go to My Apps"");   
        }
      }
    }
    
    function InsertTopBarButton(beforeDiv, src, link, target, title) {
        var myDiv = CreateTopBarButton(src, link, target, title);
        beforeDiv.parentNode.insertBefore(myDiv, beforeDiv);
        return myDiv;
    }
    
    function CreateTopBarButton(src, link, target, title) {
        var myDiv = document.createElement(""div"");
        myDiv.className = ""system-help"";
        var myLink = document.createElement(""a"");
        myLink.href = link;
        myLink.setAttribute('target', target);
        var myImage = document.createElement(""img"");
        myImage.src = src;
        myImage.title = title;
        myImage.setAttribute(""style"",""vertical-align: middle"");
        myLink.appendChild(myImage);
        myDiv.appendChild(myLink);
        return myDiv;
    }"
    
    $defaultAspxFile = "C:\inetpub\wwwroot\NAV\WebClient\default.aspx"
    $defaultAspx = (Get-Content $defaultAspxFile)
    $idx = 0
    $end1 = 0
    $start2 = 0
    
    # Find location to insert code snippet
    while ($idx -lt ($defaultAspx.Length-2))
    {
        if (($end1 -eq 0) -and
            $defaultAspx[$idx].Trim().Startswith('Microsoft.Dynamics.NAV.App.initialize') -and 
            ($defaultAspx[$idx-2].Trim().Equals('<script type="text/javascript">') -or 
             $defaultAspx[$idx-11].Trim().Equals('<script type="text/javascript">')))
        {
            if ($defaultAspx[$idx+1].Trim().Equals('}') -or 
                $defaultAspx[$idx+1].Trim().Equals('if (window.location.href.toLowerCase().indexOf("/aad/") >= 0) {'))
            {
                # Insert code snippet after Initialize if it wasn't modified by others
                $end1 = $idx
            }
        }
    
        if (($end1 -gt 0) -and
            $defaultAspx[$idx].Trim().Equals('}') -and
            $defaultAspx[$idx+1].Trim().Equals('</script>'))
        {
            # End of code snippet        
            $start2 = $idx
            break;
        }
    
        $idx++
    }
    
    # Write default.aspx with modified code snippet
    if ($start2 -gt 0) {
        $stream = [System.IO.StreamWriter] $defaultAspxFile
        0..$end1 | % {
            $stream.WriteLine($defaultAspx[$_])
        }
    
        $stream.WriteLine($codesnippet)
        
        $start2..($defaultAspx.Length-1) | % {
            $stream.WriteLine($defaultAspx[$_])
        }
        $stream.close()
    }
}

if ($CreateSharePointPortal) {
    # Remove X-FRAME OPTIONS
    Log "Remove X-FRAME Options"
    $WebConfigFile = 'C:\inetpub\wwwroot\AAD\WebClient\Web.config'
    $WebConfig = [xml](Get-Content $WebConfigFile)
    $xframeoptions = $WebConfig.SelectSingleNode("//httpProtocol/customHeaders/add[@name='X-FRAME-OPTIONS']")
    if ($xframeoptions) {
        $xframeoptions.ParentNode.RemoveChild($xframeoptions)
        $WebConfig.Save($WebConfigFile)
    }
    
    CreatePortal -SharePointInstallFolder $PSScriptRootV2 `
                 -SharePointUrl $SharePointUrl `
                 -SharePointSite $SharePointSite `
                 -SharePointSiteUrl $SharePointSiteUrl `
                 -SharePointAdminLoginName $SharePointAdminLoginName `
                 -SharePointAdminPassword $SharePointAdminPassword `
    		     -publicWebBaseUrl $publicWebBaseUrl `
    		     -SharePointMultitenant $SharePointMultitenant `
                 -SharePointLanguageFile $LanguageFile 
}

Sync-NavTenant -ServerInstance $serverInstance -Tenant default -Force

# URLs
$URLsFile = "C:\Users\Public\Desktop\URLs.txt"
"NAV WebClient with AAD auth.  : $PublicWebBaseURL"         | Add-Content -Path $URLsFile

if ($CreateSharePointPortal) {
    "SharePoint Team Site          : $SharePointSiteUrl"        | Add-Content -Path $URLsFile
}

Log -kind Success "O365 Integration Installation succeeded"
