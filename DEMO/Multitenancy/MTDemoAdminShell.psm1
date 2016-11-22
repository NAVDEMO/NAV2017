$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 

Set-StrictMode -Version 2.0
$verbosePreference = 'SilentlyContinue'
$errorActionPreference = 'Inquire'

$SharePointInstallFolder = ""
$HardcodeFile = (Join-Path $PSScriptRootV2 'HardcodeInput.ps1')
if (Test-Path -Path $HardcodeFile) {
    . $HardcodeFile
}
$DVDfolder = (Get-ChildItem -Path "C:\NAVDVD" -Directory | where-object { Test-Path -Path (Join-Path $_.FullName "WindowsPowerShellScripts") -PathType Container } | Select-Object -First 1).FullName
$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name

. (Join-Path $PSScriptRootV2 'HelperFunctions.ps1')
. ("c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1")
. ("C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\NavModelTools.ps1")
Import-Module (Join-Path $DVDFolder "WindowsPowerShellScripts\Cloud\NAVAdministration\NAVAdministration.psm1")
Import-module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking
if ($SharePointInstallFolder) {
    . (Join-Path $SharePointInstallFolder '..\Profiles.ps1')
    . (Join-Path $SharePointInstallFolder 'createportal.ps1')
    . (Join-Path $SharePointInstallFolder 'HelperFunctions.ps1')
    Import-module (Join-Path $SharePointInstallFolder 'NavInO365.dll')
    Import-Module (Join-Path $DVDFolder "WindowsPowerShellScripts\NAVOffice365Administration\NAVOffice365Administration.psm1")
}

function New-DemoTenant
{
	Param
	(
		[Parameter(Mandatory=$True)]
		[string]$TenantID
    )

    $httpWebSiteDirectory = "C:\inetpub\wwwroot\http"
    $CustomSettingsConfigFile = "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\CustomSettings.config"
    $config = [xml](Get-Content $CustomSettingsConfigFile)
    $multitenant = $config.SelectSingleNode("//appSettings/add[@key='Multitenant']").value
    $PublicWebBaseUrl = $config.SelectSingleNode("//appSettings/add[@key='PublicWebBaseUrl']").value
    $serverInstance = $config.SelectSingleNode("//appSettings/add[@key='ServerInstance']").value
    $PublicMachineName = $PublicWebBaseUrl.Split('/')[2]

    if ($multitenant -eq 'false') {
        Write-Host -ForegroundColor Red "System not setup for multi tenancy"
    } else {
        Write-Host -ForegroundColor Yellow "Copying tenant template Database"
        Copy-NavDatabase -SourceDatabaseName "Tenant Template" -DestinationDatabaseName $TenantID
        Write-Host -ForegroundColor Yellow "Mounting tenant"

        New-Item "C:\MT\$TenantID" -ItemType Directory -Force -ErrorAction Ignore

        # Change Tenant Id in Database
        Set-NavDatabaseTenantId -DatabaseName $TenantID -TenantId $TenantID

        Write-Host -ForegroundColor Yellow "Mounting tenant"
        if ($SharePointInstallFolder) {
            $SharePointSiteUrl = "$SharePointUrl/sites/$TenantID"
            $FinanceManagementName = "FinanceManagement"            $FinanceManagementSiteUrl = "$SharePointSiteUrl/$FinanceManagementName"            $ServiceManagementName = "ServiceManagement"            $ServiceManagementSiteUrl = "$SharePointSiteUrl/$ServiceManagementName"            $OrderProcessingName = "OrderProcessing"            $OrderProcessingSiteUrl = "$SharePointSiteUrl/$OrderProcessingName"            $SalesProcessName = "Sales"            $SalesProcessSiteUrl = "$SharePointSiteUrl/$SalesProcessName"
            Mount-NavDatabase -DatabaseName $TenantID -TenantId $TenantID -AlternateId @($SharePointSiteUrl, $FinanceManagementSiteUrl, $ServiceManagementSiteUrl, $OrderProcessingSiteUrl, $SalesProcessSiteUrl)
        } else {
            Mount-NavDatabase -DatabaseName $TenantID -TenantId $TenantID
        }
        
        Write-Host -ForegroundColor Yellow "Synchronizing tenant"
        Sync-NAVTenant -Tenant $TenantID -Mode ForceSync -ServerInstance $serverInstance -Force
        
        Write-Host -ForegroundColor Yellow "Creating Click-Once manifest"
        New-ClickOnceDeployment -Name $TenantID -PublicMachineName $PublicMachineName -TenantID $TenantID -clickOnceWebSiteDirectory $httpWebSiteDirectory
        Add-Content -Path  "$httpWebSiteDirectory\tenants.txt" -Value $TenantID

        if ($SharePointInstallFolder) {
            Write-Host -ForegroundColor Yellow "Creating SharePoint Portal"
            CreatePortal -SharePointInstallFolder $SharePointInstallFolder `
                         -SharePointUrl $SharePointUrl `
                         -SharePointSite $TenantID `
                         -SharePointSiteUrl $SharePointSiteUrl `
                         -SharePointAdminLoginName $SharePointAdminLoginName `
                         -SharePointAdminPassword $SharePointAdminPassword `
            		     -appClientId $SharePointAppClientId `
            		     -appFeatureId $SharePointAppfeatureId `
            		     -appProductId $SharePointAppProductId `
                         -publicWebBaseUrl $publicWebBaseUrl `
                         -createPortalForTenant $true `
                         -SharePointLanguageFile $SharePointLanguageFile
        }

        Write-Host 

        $URLsFile = ("C:\MT\$TenantID\URLs.txt")        "Web Client URL                : https://$PublicMachineName/$ServerInstance/WebClient?tenant=$TenantID"             | Add-Content -Path $URLsFile
       ("Device URL                    : https://$PublicMachineName/$ServerInstance"+"?tenant=$TenantID")                   | Add-Content -Path $URLsFile
       ("Device (configure) URL        : ms-dynamicsnav://$PublicMachineName/$ServerInstance"+"?tenant=$TenantID")          | Add-Content -Path $URLsFile
        "Windows Client (local) URL    : dynamicsnav://///?tenant=$TenantID"                                                | Add-Content -Path $URLsFile
        "Windows Client (clickonce) URL: http://$PublicMachineName/$TenantID"                                               | Add-Content -Path $URLsFile

        $SharePointParams = @{}
        if ($SharePointAdminLoginName) {
            $SharePointParams += @{"SharePointAdminLoginName" = "$SharePointAdminLoginName"}
        }
        $createuser = $true
        Get-NavServerUser $serverInstance -Tenant $TenantID | % {
            if ($_.UserName -eq $NavAdminUser) {
                $NewPassword = $NavAdminPassword
                $UserName = $_.UserName
                Set-NavServerUser $serverInstance -Tenant $TenantId -UserName $UserName -Password (ConvertTo-SecureString -String $NewPassword -AsPlainText -Force) @SharePointParams
                $createuser = $false
            }
        }
        if ($createuser) {
            New-NavServerUser $serverInstance -Tenant $TenantId -UserName $UserName -Password (ConvertTo-SecureString -String $NewPassword -AsPlainText -Force) @SharePointParams
            New-NavServerUserPermissionSet $serverInstance -Tenant $TenantID -UserName $UserName -PermissionSetId "SUPER"
        }

        Get-Content $URLsFile | Write-Host -ForegroundColor Yellow
    }
}

function Remove-DemoTenant
{
	Param
	(
		[Parameter(Mandatory=$True)]
		[string]$TenantID
    )

    $httpWebSiteDirectory = "C:\inetpub\wwwroot\http"
    $CustomSettingsConfigFile = "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\CustomSettings.config"
    $config = [xml](Get-Content $CustomSettingsConfigFile)
    $serverInstance = $config.SelectSingleNode("//appSettings/add[@key='ServerInstance']").value
    $multitenant = $config.SelectSingleNode("//appSettings/add[@key='Multitenant']").value

    if ($multitenant -eq 'false') {
        Write-Host -ForegroundColor Red "System not setup for multi tenancy"
    } else {
        Write-Host -ForegroundColor Yellow "Dismounting tenant"
        Dismount-NAVTenant -ServerInstance $serverInstance -Tenant $TenantID -Force
        
        Write-Host -ForegroundColor Yellow "Removing Database"
        Remove-NavDatabase -DatabaseName $TenantID

        Remove-Item "C:\MT\$TenantID" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $httpWebSiteDirectory $TenantID) -Recurse -Force -ErrorAction SilentlyContinue
        
        $tenants = Get-Content -Path "$httpWebSiteDirectory\tenants.txt"
        Clear-Content -Path "$httpWebSiteDirectory\tenants.txt"
        $tenants | % {
            if ($_ -ne $TenantID) {
                Add-Content -Path "$httpWebSiteDirectory\tenants.txt" -Value $_
            }
        }

        Write-Host -ForegroundColor Yellow "Done"
    }
}

Function Get-DemoTenantList {
    $CustomSettingsConfigFile = "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\CustomSettings.config"
    $config = [xml](Get-Content $CustomSettingsConfigFile)
    $serverInstance = $config.SelectSingleNode("//appSettings/add[@key='ServerInstance']").value
    $multitenant = $config.SelectSingleNode("//appSettings/add[@key='Multitenant']").value

    if ($multitenant -eq 'false') {
        Write-Host -ForegroundColor Red "System not setup for multi tenancy"
    } else {
        get-navtenant $serverInstance | % { $_.Id }
    }
}

Export-ModuleMember -Function "New-DemoTenant", "Remove-DemoTenant", "Get-DemoTenantList"
