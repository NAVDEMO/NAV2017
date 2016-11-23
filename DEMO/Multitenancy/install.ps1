$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$verbosePreference = 'Continue'
$errorActionPreference = 'Stop'

$DVDfolder = (Get-ChildItem -Path "C:\NAVDVD" -Directory | where-object { Test-Path -Path (Join-Path $_.FullName "WindowsPowerShellScripts") -PathType Container } | Select-Object -First 1).FullName
$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name
$DatabaseFolder = Join-Path (Get-ChildItem -Path "$DVDFolder\SQLDemoDatabase\CommonAppData\Microsoft\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).FullName "Database"
$DatabaseName = (Get-ChildItem -Path $DatabaseFolder -Filter "*.bak" -File).BaseName

. (Join-Path $PSScriptRootV2 'HelperFunctions.ps1')
. ("c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1")
. ("C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\NavModelTools.ps1")
Import-Module (Join-Path $DVDFolder "WindowsPowerShellScripts\Cloud\NAVAdministration\NAVAdministration.psm1")
Import-Module (Join-Path $PSScriptRootV2 "MTDemoAdminShell.psm1")

$httpWebSiteDirectory = "C:\inetpub\wwwroot\http"
$CustomSettingsConfigFile = "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\CustomSettings.config"
$config = [xml](Get-Content $CustomSettingsConfigFile)
$multitenant = ($config.SelectSingleNode("//appSettings/add[@key='Multitenant']").value -ne "false")
$serverInstance = $config.SelectSingleNode("//appSettings/add[@key='ServerInstance']").value
$PublicWebBaseUrl = $config.SelectSingleNode("//appSettings/add[@key='PublicWebBaseUrl']").value
$PublicMachineName = $PublicWebBaseUrl.Split('/')[2]
$thumbprint = $config.SelectSingleNode("//appSettings/add[@key='ServicesCertificateThumbprint']").value
$DatabaseServer = $config.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").value
$DatabaseInstance = $config.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").value
$ARRisConfigured = (Get-WebBinding -Name "Microsoft Dynamics NAV 2017 Web Client" | Where-Object { $_.bindingInformation -eq "*:8443:" })

$SharePointInstallFolder = ""
$SharePointAdminLoginName = ""
$CreateSharePointPortal = $false
$DatabaseServerInstance = "$DatabaseServer"
if ($DatabaseInstance -ne "") {
    $DatabaseServerInstance += "\$DatabaseInstance"
}
$DatabaseServerParams = @{
    'ServerInstance' = $DatabaseServerInstance
    'QueryTimeout' = 0
    'ea' = 'stop'
}
$HardcodeFile = (Join-Path $PSScriptRootV2 'HardcodeInput.ps1')
if (Test-Path -Path $HardcodeFile) {
    . $HardcodeFile
}

# Is it OK to apply this package at this time
if (!$thumbprint) {
    Throw-UserError -Text "You need to run the initialize Server script before applying demo packages."
}

$webServerInstance = Get-NAVWebServerInstance -WebServerInstance AAD
if ($webServerInstance) {
    if ($CreateSharePointPortal -and $SharePointInstallFolder -eq "") {
        Throw-UserError -Text "If you want to apply Multitenancy after installing O365 integration pack, you need to answer Yes to the question whether you want to install Multitenancy while installing O365 Integration."
    }
}

if (Test-Path (Join-Path $httpWebSiteDirectory $serverInstance)) {
    Throw-UserError -Text "ClickOnce is an integrated part of the Multitenancy pack, you cannot install Multitenancy after you have installed ClickOnce."
}

if ($ARRisConfigured) {
    Throw-UserError -Text "Server is configured for Load Balancing. You need to apply this package before setting up Load Balancing."
}

if ($DatabaseServer -eq "localhost") {

    if (!$multitenant) {

        # Switch to multi tenancy
        Log("Switch to Multi-tenancy")
        clear

        Set-NAVServerInstance $serverInstance -Stop

        Copy-NavDatabase -SourceDatabaseName $DatabaseName -DestinationDatabaseName "Tenant Template"
        Remove-NavDatabase -DatabaseName $DatabaseName
        Export-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "Tenant Template" -DestinationDatabaseName $DatabaseName -ServiceAccount "NT AUTHORITY\Network Service"
        Set-NAVServerConfiguration $serverInstance -KeyName DatabaseName -KeyValue ""
        Set-NAVServerInstance $serverInstance -Start

        Mount-NAVApplication $serverInstance -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName $DatabaseName -Force

        # Change Tenant Id in Database
        Remove-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "Tenant Template" -Force
    }
}

[array]$tenants = Get-NAVTenant -ServerInstance $ServerInstance
if (!($tenants)) {

    # Create MT folder  
    New-Item 'C:\MT' -ItemType Directory -Force -ErrorAction Ignore

    # No tenants, Add default tenant
    $TenantID = "default"
    New-DemoTenant -TenantID $TenantID

    # Change global ClientUserSettings
    Log("Modify public ClientUserSettings")
    $ClientUserSettingsFile = "C:\Users\All Users\Microsoft\Microsoft Dynamics NAV\$NavVersion\ClientUserSettings.config"
    $ClientUserSettings = [xml](Get-Content $ClientUserSettingsFile)
    $ClientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='TenantId']").value= $TenantID
    $ClientUserSettings.Save($ClientUserSettingsFile)
    
    if ([Environment]::UserName -ne "SYSTEM") {
        $vmadmin = $env:USERNAME
        # Change vmadmin ClientUserSettings
        Log("Modify ClientUserSettings for $vmadmin")
        $ClientUserSettingsFile = "C:\Users\$vmadmin\AppData\Roaming\Microsoft\Microsoft Dynamics NAV\$NavVersion\ClientUserSettings.config"
        if (Test-Path -Path $ClientUserSettingsFile) {
            $ClientUserSettings = [xml](Get-Content $ClientUserSettingsFile)
            $ClientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='TenantId']").value= $TenantID
            $ClientUserSettings.Save($ClientUserSettingsFile)
        }
    }

    Log("Remove old Desktop Shortcuts")
    # Remove Old Web Client
    get-item C:\Users\Public\Desktop\*.lnk | % {
        $Shell =  New-object -comobject WScript.Shell
        $lnk = $Shell.CreateShortcut($_.FullName)
        if ($lnk.TargetPath -eq "") {
            Remove-Item $_.FullName
        }
    }

    Log("Setup Desktop Shortcuts")
    New-DesktopShortcut -Name "Demo Environment Landing Page"     -TargetPath "http://$PublicMachineName" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
    New-DesktopShortcut -Name "NAV 2017 Web Client"               -TargetPath "https://$PublicMachineName/$serverInstance/WebClient/?tenant=$TenantID" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
    New-DesktopShortcut -Name "NAV 2017 Tablet Client"            -TargetPath "https://$PublicMachineName/$serverInstance/WebClient/tablet.aspx?tenant=$TenantID" IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
    $DemoAdminShell = Join-Path $PSScriptRootV2 'MTDemoAdminShell.ps1'
    New-DesktopShortcut -Name "Multitenancy Demo Admin Shell"     -TargetPath "C:\Windows\system32\WindowsPowerShell\v1.0\PowerShell.exe" -Arguments "-NoExit & '$DemoAdminShell'"

    $URLsFile = "C:\Users\Public\Desktop\URLs.txt"    $URLs = Get-Content $URLsFile
    
    "Web Client URL                : https://$PublicMachineName/$serverInstance/WebClient?tenant=$TenantID"                  | Set-Content -Path $URLsFile
    "Tablet Client URL             : https://$PublicMachineName/$serverInstance/WebClient/tablet.aspx?tenant=$TenantID"      | Add-Content -Path $URLsFile
    
    if ($SharePointAdminLoginName) {
        "Web Client URL (AAD)          : https://$PublicMachineName/AAD/WebClient?tenant=$TenantID"                          | Add-Content -Path $URLsFile
        "Tablet Client URL (AAD)       : https://$PublicMachineName/AAD/WebClient/tablet.aspx?tenant=$TenantID"              | Add-Content -Path $URLsFile
    }
    if ($CreateSharePointPortal) {
        "SharePoint Portal             : $SharePointUrl/sites/$TenantID"                                                     | Add-Content -Path $URLsFile
    }
    
    $URLs | % { if ($_.StartsWith("NAV Admin")) { $_ | Add-Content -Path $URLsFile } }
    "Please open Multitenancy Demo Admin Shell on the desktop to add or remove tenants" | Add-Content -Path $URLsFile

    if ([Environment]::UserName -ne "SYSTEM") {
        Get-Content $URLsFile | Write-Host -ForegroundColor Yellow
        & notepad.exe $URLsFile
    }
}