$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$verbosePreference =  'SilentlyContinue'
$errorActionPreference = 'Stop'
. (Join-Path $PSScriptRootV2 '..\Common\HelperFunctions.ps1')

Clear
Log -kind Emphasis -OnlyInfo "Welcome to the Multitenancy Installation script."
Log -kind Info -OnlyInfo ""
Log -kind Info -OnlyInfo "This script will help you turn your NAV DEMO Environment into a multi-tenant server."
Log -kind Info -OnlyInfo "Note:"
Log -kind Info -OnlyInfo "- You cannot install multitenancy after you install the new developer experience."
Log -kind Info -OnlyInfo "- You cannot install multitenancy after taking a single tenant database to Azure SQL."
Log -kind Info -OnlyInfo "- You cannot install multitenancy after setting up load balancing."
Log -kind Info -OnlyInfo ""
Log -kind Info -OnlyInfo "The landing page will automatically be updated with a list of all tenants and their URLs."
Log -kind Info -OnlyInfo ""

Log "Read Settings"
$DVDfolder = (Get-ChildItem -Path "C:\NAVDVD" -Directory | where-object { Test-Path -Path (Join-Path $_.FullName "WindowsPowerShellScripts") -PathType Container } | Select-Object -First 1).FullName
$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name
$DatabaseFolder = Join-Path (Get-ChildItem -Path "$DVDFolder\SQLDemoDatabase\CommonAppData\Microsoft\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).FullName "Database"
$DatabaseName = (Get-ChildItem -Path $DatabaseFolder -Filter "*.bak" -File).BaseName

Log "NAV Version: $NavVersion"
Log "Database Name: [$DatabaseName]"

Log "Import Modules"
. (Join-Path $PSScriptRootV2 'HelperFunctions.ps1')
. ("c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1") | Out-Null
. ("C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\NavModelTools.ps1") | Out-Null
Import-Module (Join-Path $DVDFolder "WindowsPowerShellScripts\Cloud\NAVAdministration\NAVAdministration.psm1")

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

Log "Server Instance: $ServerInstance"

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
    throw "You need to run the initialize Server script before applying demo packages."
}

$devServerInstance = Get-NAVServerInstance -ServerInstance navision_main
if ($devServerInstance) {
    throw "You need to install multi-tenancy before you install the new developer experience."
}

$webServerInstance = Get-NAVWebServerInstance -WebServerInstance AAD
if ($webServerInstance) {
    if ($CreateSharePointPortal -and $SharePointInstallFolder -eq "") {
        throw "If you want to apply Multitenancy after installing O365 integration pack, you need to answer Yes to the question whether you want to install Multitenancy while installing O365 Integration."
    }
}

if (Test-Path (Join-Path $httpWebSiteDirectory $serverInstance)) {
    Log "Remove previous ClickOnce deployments"
    $httpWebSiteDirectory = "C:\inetpub\wwwroot\http"
    Remove-Item "$httpWebSiteDirectory\NAV" -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item "$httpWebSiteDirectory\AAD" -Force -Recurse -ErrorAction SilentlyContinue
}

if ($ARRisConfigured) {
    throw "Server is configured for Load Balancing. You need to apply this package before setting up Load Balancing."
}

if ($DatabaseServer -eq "localhost") {

    if (!$multitenant) {

        # Switch to multi tenancy
        Log -kind Emphasis "Switch to Multi-tenancy"

        Log "Stop NAV Service Tier"
        Set-NAVServerInstance $serverInstance -Stop

        Log "Copy Database [$DatabaseName] to [Tenant Template]"
        Copy-NavDatabase -SourceDatabaseName $DatabaseName -DestinationDatabaseName "Tenant Template"

        Log "Remove Database [$DatabaseName]"
        Remove-NavDatabase -DatabaseName $DatabaseName
        
        Log "Export NAV Application from [Tenant Template] to [$DatabaseName]"
        Export-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "Tenant Template" -DestinationDatabaseName $DatabaseName -ServiceAccount "NT AUTHORITY\Network Service" | Out-Null
        
        Log "Start NAV Service Tier with DatabaseName empty"
        Set-NAVServerConfiguration $serverInstance -KeyName DatabaseName -KeyValue "" -WarningAction SilentlyContinue
        Set-NAVServerInstance $serverInstance -Start

        Log "Mount NAV Application Database"
        Mount-NAVApplication $serverInstance -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName $DatabaseName -Force

        Log "Remove Application part in [Tenant Template]"
        Remove-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "Tenant Template" -Force | Out-Null
    }
}

[array]$tenants = Get-NAVTenant -ServerInstance $ServerInstance
if (!($tenants)) {

    Log "Import MTDemoAdminShell module"
    Import-Module (Join-Path $PSScriptRootV2 "MTDemoAdminShell.psm1")

    Log "Create default tenant"
    # Create MT folder  
    New-Item 'C:\MT' -ItemType Directory -Force -ErrorAction Ignore | Out-Null

    # No tenants, Add default tenant
    $TenantID = "default"
    New-DemoTenant -TenantID $TenantID

    Log "Add Tenant ID to Change global ClientUserSettings"
    $ClientUserSettingsFile = "C:\Users\All Users\Microsoft\Microsoft Dynamics NAV\$NavVersion\ClientUserSettings.config"
    $ClientUserSettings = [xml](Get-Content $ClientUserSettingsFile)
    $ClientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='TenantId']").value= $TenantID
    $ClientUserSettings.Save($ClientUserSettingsFile)
    
    if ([Environment]::UserName -ne "SYSTEM") {
        $vmadmin = $env:USERNAME
        # Change vmadmin ClientUserSettings
        Log "Add Tenant ID to Change ClientUserSettings for $vmadmin"
        $ClientUserSettingsFile = "C:\Users\$vmadmin\AppData\Roaming\Microsoft\Microsoft Dynamics NAV\$NavVersion\ClientUserSettings.config"
        if (Test-Path -Path $ClientUserSettingsFile) {
            $ClientUserSettings = [xml](Get-Content $ClientUserSettingsFile)
            $ClientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='TenantId']").value= $TenantID
            $ClientUserSettings.Save($ClientUserSettingsFile)
        }
    }

    Log "Remove old Desktop Shortcuts"
    get-item C:\Users\Public\Desktop\*.lnk | % {
        $Shell =  New-object -comobject WScript.Shell
        $lnk = $Shell.CreateShortcut($_.FullName)
        if ($lnk.TargetPath -eq "") {
            Remove-Item $_.FullName
        }
    }

    $aid = ""
    if ($isSaaS) { $aid = "&aid=fin" }

    Log "Setup Desktop Shortcuts with Tenant specification"
    New-DesktopShortcut -Name "Demo Environment Landing Page"     -TargetPath "http://$PublicMachineName" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
    New-DesktopShortcut -Name "NAV 2017 Web Client"               -TargetPath "https://$PublicMachineName/$serverInstance/WebClient/?tenant=$TenantID$aid" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
    $DemoAdminShell = Join-Path $PSScriptRootV2 'MTDemoAdminShell.ps1'
    New-DesktopShortcut -Name "Multitenancy Demo Admin Shell"     -TargetPath "C:\Windows\system32\WindowsPowerShell\v1.0\PowerShell.exe" -Arguments "-NoExit & '$DemoAdminShell'"

    $URLsFile = "C:\Users\Public\Desktop\URLs.txt"    $URLs = Get-Content $URLsFile
    

    "Web Client URL                : https://$PublicMachineName/$serverInstance/WebClient?tenant=$TenantID$aid"                  | Set-Content -Path $URLsFile
    
    if ($SharePointAdminLoginName) {
        "Web Client URL (AAD)          : https://$PublicMachineName/AAD/WebClient?tenant=$TenantID$aid"                          | Add-Content -Path $URLsFile
    }
    if ($CreateSharePointPortal) {
        "SharePoint Portal             : $SharePointUrl/sites/$TenantID"                                                     | Add-Content -Path $URLsFile
    }
    
    $URLs | % { if ($_.StartsWith("NAV Admin")) { $_ | Add-Content -Path $URLsFile } }
    
    Log -kind Success "Multitenancy successfully installted."
    Log -kind Success "Please open Multitenancy Demo Admin Shell on the desktop to add or remove tenants"
}