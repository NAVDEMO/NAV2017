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
    if (!$SharePointInstallFolder) {
        Throw-UserError -Text "If you want to apply Multitenancy after installing O365 integration pack, you need to answer Yes to the question whether you want to install Multitenancy while installing O365 Integration."
    }
}

if (Test-Path (Join-Path $httpWebSiteDirectory $serverInstance)) {
    Throw-UserError -Text "ClickOnce is an integrated part of the Multitenancy pack, you cannot install Multitenancy after you have installed ClickOnce."
}

if ($ARRisConfigured) {
    Throw-UserError -Text "Server is configured for Load Balancing. You need to apply this package before setting up Load Balancing."
}

$defaultTenant = "default"
$changesettings = $false

if ($DatabaseServer -ne "localhost") {
    
    # Using AzureSQL as database server
    [array]$tenants = Get-NAVTenant -ServerInstance $ServerInstance
    if ($tenants) {
        Throw-UserError -Text "Server is not using SQL Express as database server. You need to apply this package before using Azure SQL."
    }
    
    # AzureSQL with no tenants - create default tenant
    $DatabaseCredentials = New-Object PSCredential -ArgumentList $DatabaseServerParams.UserName, (ConvertTo-SecureString -String $DatabaseServerParams.Password -AsPlainText -Force)
    Copy-NavDatabase -SourceDatabaseName "Tenant Template" -DestinationDatabaseName $defaultTenant
    Mount-NAVTenant -ServerInstance $serverInstance -Id $defaultTenant -AllowAppDatabaseWrite -DatabaseServer $DatabaseServer -DatabaseName $defaultTenant -DatabaseCredentials $DatabaseCredentials -OverwriteTenantIdInDatabase -Force
    New-NAVServerUser -ServerInstance $serverInstance -Tenant $defaultTenant -UserName "admin" -Password (ConvertTo-SecureString -String "Coke4ever" -AsPlainText -Force)
    New-NAVServerUserPermissionSet -ServerInstance $serverInstance -Tenant $defaultTenant -UserName "admin" -PermissionSetId "SUPER"
    $changesettings = $true

} else {

    if (!$multitenant) {
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

    Copy-NavDatabase -SourceDatabaseName "Tenant Template" -DestinationDatabaseName $TenantID
    Write-Host -ForegroundColor Yellow "Mounting tenant"

    New-Item "C:\MT\$TenantID" -ItemType Directory -Force -ErrorAction Ignore

    # Change Tenant Id in Database
    Set-NavDatabaseTenantId -DatabaseName $TenantID -TenantId $TenantID

    Write-Host -ForegroundColor Yellow "Mounting tenant"
    if ($SharePointInstallFolder) {
        $SharePointSiteUrl = "$SharePointUrl/sites/$TenantID"
        $FinanceManagementName = "FinanceManagement"        $FinanceManagementSiteUrl = "$SharePointSiteUrl/$FinanceManagementName"        $ServiceManagementName = "ServiceManagement"        $ServiceManagementSiteUrl = "$SharePointSiteUrl/$ServiceManagementName"        $OrderProcessingName = "OrderProcessing"        $OrderProcessingSiteUrl = "$SharePointSiteUrl/$OrderProcessingName"        $SalesProcessName = "Sales"        $SalesProcessSiteUrl = "$SharePointSiteUrl/$SalesProcessName"
        Mount-NavDatabase -DatabaseName $TenantID -TenantId $TenantID -AlternateId @($SharePointSiteUrl, $FinanceManagementSiteUrl, $ServiceManagementSiteUrl, $OrderProcessingSiteUrl, $SalesProcessSiteUrl)
    } else {
        Mount-NavDatabase -DatabaseName $TenantID -TenantId $TenantID
    }
    
    Write-Host -ForegroundColor Yellow "Synchronizing tenant"
    Sync-NAVTenant -Tenant $TenantID -Mode ForceSync -ServerInstance $serverInstance -Force
    
    Write-Host -ForegroundColor Yellow "Creating Click-Once manifest"
    New-ClickOnceDeployment -Name $TenantID -PublicMachineName $PublicMachineName -TenantID $TenantID -clickOnceWebSiteDirectory $httpWebSiteDirectory
    Add-Content -Path  "$httpWebSiteDirectory\tenants.txt" -Value $TenantID

    Set-Content -Path  "$httpWebSiteDirectory\tenants.txt" -Value $defaultTenant

    # Change global ClientUserSettings
    $ClientUserSettingsFile = "C:\Users\All Users\Microsoft\Microsoft Dynamics NAV\$NavVersion\ClientUserSettings.config"
    $ClientUserSettings = [xml](Get-Content $ClientUserSettingsFile)
    $ClientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='TenantId']").value= $defaultTenant
    $ClientUserSettings.Save($ClientUserSettingsFile)
    
    if ([Environment]::UserName -ne "SYSTEM") {
        $vmadmin = $env:USERNAME

        # Change vmadmin ClientUserSettings
        $ClientUserSettingsFile = "C:\Users\$vmadmin\AppData\Roaming\Microsoft\Microsoft Dynamics NAV\$NavVersion\ClientUserSettings.config"
        if (Test-Path -Path $ClientUserSettingsFile) {
            $ClientUserSettings = [xml](Get-Content $ClientUserSettingsFile)
            $ClientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='TenantId']").value= $defaultTenant
            $ClientUserSettings.Save($ClientUserSettingsFile)
        }
    }

    # Remove Old Web Client
    get-item C:\Users\Public\Desktop\*.lnk | % {
        $Shell =  New-object -comobject WScript.Shell
        $lnk = $Shell.CreateShortcut($_.FullName)
        if ($lnk.TargetPath -eq "") {
            Remove-Item $_.FullName
        }
    }

    New-DesktopShortcut -Name "Demo Environment Landing Page"     -TargetPath "http://$PublicMachineName" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
    New-DesktopShortcut -Name "NAV 2017 Web Client"               -TargetPath "https://$PublicMachineName/$serverInstance/WebClient/?tenant=$defaultTenant" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
    New-DesktopShortcut -Name "NAV 2017 Tablet Client"            -TargetPath "https://$PublicMachineName/$serverInstance/WebClient/tablet.aspx?tenant=$defaultTenant" IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
    $DemoAdminShell = Join-Path $PSScriptRootV2 'MTDemoAdminShell.ps1'
    New-DesktopShortcut -Name "Multitenancy Demo Admin Shell"     -TargetPath "C:\Windows\system32\WindowsPowerShell\v1.0\PowerShell.exe" -Arguments "-NoExit & '$DemoAdminShell'"

    New-Item 'C:\MT' -ItemType Directory -Force -ErrorAction Ignore
}

$URLsFile = "C:\Users\Public\Desktop\URLs.txt"$URLs = Get-Content $URLsFile

"Web Client URL                : https://$PublicMachineName/$serverInstance/WebClient?tenant=$defaultTenant"             | Set-Content -Path $URLsFile
"Tablet Client URL             : https://$PublicMachineName/$serverInstance/WebClient/tablet.aspx?tenant=$defaultTenant" | Add-Content -Path $URLsFile

if ($SharePointInstallFolder) {
    "Web Client URL (AAD)          : https://$PublicMachineName/AAD/WebClient?tenant=$defaultTenant"                     | Add-Content -Path $URLsFile
    "Tablet Client URL (AAD)       : https://$PublicMachineName/AAD/WebClient/tablet.aspx?tenant=$defaultTenant"         | Add-Content -Path $URLsFile
}

$URLs | % { if ($_.StartsWith("NAV Admin")) { $_ | Add-Content -Path $URLsFile } }

"Please open Multitenancy Demo Admin Shell on the desktop to add or remove tenants" | Add-Content -Path $URLsFile

if ([Environment]::UserName -ne "SYSTEM") {
    Get-Content $URLsFile | Write-Host -ForegroundColor Yellow
    & notepad.exe $URLsFile
}
