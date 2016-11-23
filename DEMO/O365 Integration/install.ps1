$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$VerbosePreference = 'Continue'
$ErrorActionPreference = 'Stop'

$HardcodeFile = (Join-Path $PSScriptRootV2 'HardcodeInput.ps1')
if (Test-Path -Path $HardcodeFile) {
    . $HardcodeFile
}
$DVDfolder = (Get-ChildItem -Path "C:\NAVDVD" -Directory | where-object { Test-Path -Path (Join-Path $_.FullName "WindowsPowerShellScripts") -PathType Container } | Select-Object -First 1).FullName
$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name
$DatabaseFolder = Join-Path (Get-ChildItem -Path "$DVDFolder\SQLDemoDatabase\CommonAppData\Microsoft\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).FullName "Database"
$DatabaseName = (Get-ChildItem -Path $DatabaseFolder -Filter "*.bak" -File).BaseName

. (Join-Path $PSScriptRootV2 'HelperFunctions.ps1')
Import-Module -Name "AzureRM.Resources"
. (Join-Path $PSScriptRootV2 '..\Profiles.ps1')
. (Join-Path $PSScriptRootV2 'createportal.ps1')
. ("c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1")
. ("C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\NavModelTools.ps1")
Import-module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking
Import-Module (Join-Path $DVDFolder "WindowsPowerShellScripts\Cloud\NAVAdministration\NAVAdministration.psm1")
Import-Module (Join-Path $DVDFolder "WindowsPowerShellScripts\NAVOffice365Administration\NAVOffice365Administration.psm1")

$CustomSettingsConfigFile = "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\CustomSettings.config"
$config = [xml](Get-Content $CustomSettingsConfigFile)
$thumbprint = $config.SelectSingleNode("//appSettings/add[@key='ServicesCertificateThumbprint']").value
$publicSoapBaseUrl = $config.SelectSingleNode("//appSettings/add[@key='PublicSOAPBaseUrl']").value
$publicWebBaseUrl = $config.SelectSingleNode("//appSettings/add[@key='PublicWebBaseUrl']").value
$serverInstance = $config.SelectSingleNode("//appSettings/add[@key='ServerInstance']").value
$multitenant = ($config.SelectSingleNode("//appSettings/add[@key='Multitenant']").value -ne "false")
$DatabaseServer = $config.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").value
$ARRisConfigured = (Get-WebBinding -Name "Microsoft Dynamics NAV 2017 Weblogin  Client" | Where-Object { $_.bindingInformation -eq "*:8443:" })

$WebConfigFile = "C:\inetpub\wwwroot\$ServerInstance\Web.config"
$WebConfig = [xml](Get-Content $WebConfigFile)
$dnsidentity = $WebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='DnsIdentity']").Value

# Is it OK to apply this package at this time
if (!$thumbprint) {
    Throw-UserError -Text "You need to run the initialize Server script before applying demo packages."
}

if ($multitenant) {
    Throw-UserError -Text "Server is multi-tenant. You need to apply this package before installing multi-tenancy."
}

if ($DatabaseServer -ne "localhost") {
    Throw-UserError -Text "Server is not using SQL Express as database server. You need to apply this package before using Azure SQL."
}

if ($ARRisConfigured) {
    Throw-UserError -Text "Server is configured for Load Balancing. You need to apply this package before setting up Load Balancing."
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
$SharePointAdminLoginname = Get-UserInput -Id SharePointAdminLoginname -Text "Office 365 administrator E-mail (example: somebody@cronus.onmicrosoft.com)"
$SharePointAdminPassword = Get-Variable -name "HardcodeSharePointAdminPassword" -ValueOnly -ErrorAction SilentlyContinue
if ($SharePointAdminPassword) {
    $SharePointAdminSecurePassword = ConvertTo-SecureString -String $SharePointAdminPassword -AsPlainText -Force
} else {
    $SharePointAdminSecurePassword = Read-Host "Office 365 administrator Password" -AsSecureString
}
$SharePointAdminPassword = Decrypt-SecureString $SharePointAdminSecurePassword
$SharePointAdminCredential = New-Object System.Management.Automation.PSCredential ($SharePointAdminLoginname, $SharePointAdminSecurePassword)

# Connect to Microsoft Online Service
Write-Verbose "Connect to Microsoft Online Service"
Connect-MsolService -Credential $SharePointAdminCredential -ErrorAction Stop

$CreateSharePointPortal = ((Get-UserInput -Id CreateSharePointPortal -Text "Do you want to create a demo SharePoint Portal with App Parts from NAV? (Yes/No)" -Default "Yes") -eq "Yes")
$sku = Get-MsolAccountSku | Select-Object -First 1

if ($CreateSharePointPortal) {

    $SharePointMultitenant = ((Get-UserInput -Id SharePointMultitenant -Text "Is the SharePoint portal going to be integrated to a multitenant NAV? (Yes/No)" -Default "No") -eq "Yes")


    do {
        $err = $false
        $SharePointUrl = ('https://' + $sku.AccountName + '.sharepoint.com')
        $SharePointUrl = Get-UserInput -Id SharePointUrl -Text "SharePoint Base URL (example: https://cronus.sharepoint.com)" -Default $SharePointUrl
        while ($SharePointUrl.EndsWith('/')) {
            $SharePointUrl = $SharePointUrl.SubString(0, $SharePointUrl.Length-1)
        }
        if ((!$SharePointUrl.ToLower().EndsWith(".sharepoint.com")) -or (!$SharePointUrl.ToLower().StartsWith("https://"))) {
            $err = $true
            Write-Host -ForegroundColor Red "SharePoint URL must be formed like: https://tenant.sharepoint.com"
        }
    } while ($err)

    do {
        Write-Host "Languages:"
        $languages.GetEnumerator() | % { Write-Host ($_.Name + " = " + $_.Value) }
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

    # Setup online doc. storage configuration
    Invoke-sqlcmd -ea stop -ServerInstance "localhost\NAVDEMO" -QueryTimeout 0 `
    "USE [$DatabaseName]
    GO
    IF EXISTS (SELECT * FROM [dbo].[Document Service] WHERE [Service ID]='SERVICE 1')
        UPDATE [dbo].[Document Service]
           SET [Description] = 'Office 365 Documents repository'
              ,[Location] = '$SharePointUrl/sites/$SharePointSite'
              ,[User Name] = '$SharePointAdminLoginname'
              ,[Password] = '$SharePointAdminPassword'
              ,[Document Repository] = '$DocumentsTitle'
              ,[Folder] = 'Temp'
         WHERE [Service ID] = 'SERVICE 1'
    ELSE
        INSERT INTO [dbo].[Document Service]
                   ([Service ID]
                   ,[Description]
                   ,[Location]
                   ,[User Name]
                   ,[Password]
                   ,[Document Repository]
                   ,[Folder])
             VALUES
                   ('SERVICE 1'
                   ,'Office 365'
                   ,'$SharePointUrl/sites/$SharePointSite'
                   ,'$SharePointAdminLoginname'
                   ,'$SharePointAdminPassword'
                   ,'$DocumentsTitle'
                   ,'Temp')
    GO"
    
    cd $PSScriptRootV2
}

$publicWebBaseUrl = $publicWebBaseUrl.Replace("/$ServerInstance/", "/AAD/")

# Create new Web Server Instance
if (!(Test-Path "C:\inetpub\wwwroot\AAD")) {

    Setup-AadApps -publicWebBaseUrl $publicWebBaseUrl -SharePointAdminLoginname $SharePointAdminLoginname -SharePointAdminPassword $SharePointAdminPassword

    ('$CreateSharePointPortal = '+$CreateSharePointPortal)            | Add-Content "C:\DEMO\Multitenancy\HardcodeInput.ps1"
    ('$SharePointAdminLoginName = "'+$SharePointAdminLoginName+'"')   | Add-Content 'C:\DEMO\Multitenancy\HardcodeInput.ps1'
    ('$SharePointAdminPassword = "' + $SharePointAdminPassword + '"') | Add-Content "C:\DEMO\Multitenancy\HardcodeInput.ps1"

    $AcsUri = "https://login.windows.net/$GLOBAL:AadTenant/wsfed?wa=wsignin1.0%26wtrealm=$publicWebBaseUrl"
    $federationMetadata = "https://login.windows.net/$GLOBAL:AadTenant/federationmetadata/2007-06/federationmetadata.xml"

    Write-Verbose "Set FederationMetada $federationMetadata"
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "ClientServicesFederationMetadataLocation" -KeyValue $federationMetadata
    
    Write-Verbose "Create NAV WebServerInstance with ACSUri $ACSUri"
    New-NAVWebServerInstance -ClientServicesCredentialType "AccessControlService" -ClientServicesPort 7046 -DnsIdentity $dnsidentity -Server "localhost" -ServerInstance $serverInstance -WebServerInstance "AAD" -AcsUri $AcsUri -Company $Company

    # Change AAD Web.config
    $NAVWebConfigFile = "C:\inetpub\wwwroot\$ServerInstance\Web.config"
    $NAVWebConfig = [xml](Get-Content $NAVWebConfigFile)

    $AADWebConfigFile = "C:\inetpub\wwwroot\AAD\Web.config"
    $AADWebConfig = [xml](Get-Content $AADWebConfigFile)
    $AADWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='HelpServer']").value = $NAVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='HelpServer']").value
    $AADWebConfig.Save($AADWebConfigFile)

    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "AppIdUri" -KeyValue $publicWebBaseUrl
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "PublicWebBaseUrl" -KeyValue $publicWebBaseUrl
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "AzureActiveDirectoryClientId" -KeyValue $GLOBAL:ssoAdAppId
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "ExcelAddInAzureActiveDirectoryClientId" -KeyValue $GLOBAL:ExcelAdAppId
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "WSFederationLoginEndpoint" -KeyValue $ACSUri
    Set-NAVServerUser -ServerInstance $serverInstance -UserName $NAVAdminUser -AuthenticationEmail $SharePointAdminLoginname

    # Copy Client Add-ins
    Write-Verbose "Copy Client Add-ins"
    XCopy (Join-Path $PSScriptRootV2 "Client Add-Ins\*.*") "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\Add-ins" /Y
    XCopy (Join-Path $PSScriptRootV2 "Client Add-Ins\*.*") "C:\Program Files\Microsoft Dynamics NAV\$NavVersion\Service\Add-ins" /Y
    
    Write-Verbose "Register Client Add-in"
    Remove-NAVAddIn -ServerInstance $serverInstance -AddInName "HTMLViewer" -PublicKeyToken "5be233b58c6bf929" -Force -ErrorAction Ignore
    New-NAVAddIn    -ServerInstance $serverInstance -AddInName "HTMLViewer" -PublicKeyToken "5be233b58c6bf929" -Category JavaScriptControlAddIn -Description "HTML Viewer Control Add-In" -ResourceFile "C:\DEMO\O365 Integration\HtmlViewerControlAddIn\ControlAddIn\Resource\manifest.zip" 
    
    # Uninstall and unpublish NAV App if already installed
    UnInstall-NAVApp -ServerInstance $serverInstance -Name "O365 Integration Demo" -ErrorAction Ignore
    UnPublish-NAVApp -ServerInstance $serverInstance -Name "O365 Integration Demo" -ErrorAction Ignore
    
    # Install pre-requisites if they exist
    $NavIde = "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe"
    $PrereqFile = Join-Path $PSScriptRootV2 "$Language Prereq.fob"
    if (Test-Path -Path $PrereqFile) {
        Write-Host -ForegroundColor Green "Import pre-requisite .fob file"
        Import-NAVApplicationObject -DatabaseServer 'localhost\NAVDEMO' -DatabaseName $DatabaseName -Path $PrereqFile -SynchronizeSchemaChanges Force -NavServerName localhost -NavServerInstance $ServerInstance -NavServerManagementPort 7045 -ImportAction Overwrite -Confirm:$false
    }
    
    # Publish and Install NAV App 
    Publish-NAVApp -ServerInstance $serverInstance -Path (Join-Path $PSScriptRootV2 "O365 Integration.navx") -SkipVerification
    Install-NAVApp -ServerInstance $serverInstance -Name "O365 Integration Demo"
    
    # Copy misc. files
    Copy-Item (Join-Path $PSScriptRootV2 "Translations") "C:\Program Files\Microsoft Dynamics NAV\$NavVersion\Service" -Recurse -Force
    Copy-Item (Join-Path $PSScriptRootV2 "Office.png") "C:\inetpub\wwwroot\AAD\WebClient\Resources\Images\Office.png" -Force
    Copy-Item (Join-Path $PSScriptRootV2 "myapps.png") "C:\inetpub\wwwroot\AAD\WebClient\Resources\Images\myapps.png" -Force
    
    # Restart NAV Service Tier
    Write-Verbose "Restart Service Tier"
    Set-NAVServerInstance -ServerInstance $serverInstance -Restart
    
    Push-Location
    #Install local DB
    Invoke-sqlcmd -ea stop -ServerInstance "localhost\NAVDEMO" -QueryTimeout 0 `
    "USE [$DatabaseName]
    GO
    DELETE FROM [dbo].[Web Service] WHERE [Service Name] = 'AzureAdAppSetup'
    GO
    INSERT INTO [dbo].[Web Service] ([Object Type],[Service Name],[Object ID],[Published]) VALUES (5,'AzureAdAppSetup',51401,1)
    GO"
    Pop-Location
    
    # Restart Service Tier
    Write-Verbose "Restart Service Tier"
    Set-NAVServerInstance $ServerInstance -Restart
    
    $O365Username = "o365user"
    $O365Password = "o365P@ssw0rd"
    if (!(Get-NAVServerUser $serverInstance | Where-Object { $_.UserName -eq $O365Username })) {
        Write-Verbose "Create O365 user"
        New-NAVServerUser -ServerInstance $serverInstance -UserName $O365Username -Password (ConvertTo-SecureString -String $O365Password -AsPlainText -Force) 
        New-NAVServerUserPermissionSet -ServerInstance $serverInstance -UserName $O365Username -PermissionSetId SUPER
    } else {
        Write-Verbose "Enable O365 user"
        Set-NAVServerUser $serverInstance -UserName $O365Username -State Enabled
    }
    
    # Invoke Web Service
    Write-Verbose "Create Web Service Proxy"
    $secureO365Password = ConvertTo-SecureString -String $O365Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($O365Username, $secureO365Password)
    $Uri = ("$publicSoapBaseUrl" + "$Company/Codeunit/AzureAdAppSetup")
    $proxy = New-WebServiceProxy -Uri $Uri -Credential $credential
    # Timout 1 hour
    $proxy.timeout = 60*60*1000
    Write-Verbose "Setup Azure Ad App"
    $proxy.SetAzureAdAppSetup($GLOBAL:PowerBiAdAppId, $GLOBAL:PowerBiAdAppKeyValue)
    
    Write-Verbose "Disable O365 user"
    Set-NAVServerUser $Serverinstance -UserName $O365Username -State Disabled
    Get-NAVServerSession -ServerInstance $serverInstance | % { Remove-NAVServerSession -ServerInstance $serverInstance -SessionId $_.SessionID -Force }
    
    # Modify Default.aspx to include a link to SharePoint
    Write-Verbose "Modify default.aspx"
    
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
    Write-Verbose "Remove X-FRAME Options"
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

if ([Environment]::UserName -ne "SYSTEM") {
    Get-Content $URLsFile | Write-Host -ForegroundColor Yellow
    & notepad.exe $URLsFile
}
