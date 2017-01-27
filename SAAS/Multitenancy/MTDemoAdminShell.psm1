$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$verbosePreference = 'SilentlyContinue'
$warningPreference = 'SilentlyContinue'
$errorActionPreference = 'Stop'
. (Join-Path $PSScriptRootV2 '..\Common\HelperFunctions.ps1')

$DVDfolder = (Get-ChildItem -Path "C:\NAVDVD" -Directory | where-object { Test-Path -Path (Join-Path $_.FullName "WindowsPowerShellScripts") -PathType Container } | Select-Object -First 1).FullName
$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name

. (Join-Path $PSScriptRootV2 'HelperFunctions.ps1')
. ("c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1") | Out-null
. ("C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\NavModelTools.ps1") | Out-null
Import-Module (Join-Path $DVDFolder "WindowsPowerShellScripts\Cloud\NAVAdministration\NAVAdministration.psm1")
Import-module Microsoft.Online.SharePoint.PowerShell -DisableNameChecking

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
$CreateClickOnceManifest = $true
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

    if (!$multitenant) {
        Log -kind Error "System not setup for multi tenancy"
    } else {
        Copy-NavDatabase -SourceDatabaseName "Tenant Template" -DestinationDatabaseName $TenantID

        # Change Tenant Id in Database
        Set-NavDatabaseTenantId -DatabaseName $TenantID -TenantId $TenantID

        if ($CreateSharePointPortal) {
            $SharePointSiteUrl = "$SharePointUrl/sites/$TenantID"
            $FinanceManagementName = "FinanceManagement"            $FinanceManagementSiteUrl = "$SharePointSiteUrl/$FinanceManagementName"            $ServiceManagementName = "ServiceManagement"            $ServiceManagementSiteUrl = "$SharePointSiteUrl/$ServiceManagementName"            $OrderProcessingName = "OrderProcessing"            $OrderProcessingSiteUrl = "$SharePointSiteUrl/$OrderProcessingName"            $SalesProcessName = "Sales"            $SalesProcessSiteUrl = "$SharePointSiteUrl/$SalesProcessName"
            Mount-NavDatabase -DatabaseName $TenantID -TenantId $TenantID -AlternateId @($SharePointSiteUrl, $FinanceManagementSiteUrl, $ServiceManagementSiteUrl, $OrderProcessingSiteUrl, $SalesProcessSiteUrl)
        } else {
            Mount-NavDatabase -DatabaseName $TenantID -TenantId $TenantID
        }
        
        Log "Synchronize tenant $TenantID"
        Sync-NAVTenant -Tenant $TenantID -Mode ForceSync -ServerInstance $serverInstance -Force
        
        if ([Environment]::UserName -ne "SYSTEM") {
            New-ClickOnceDeployment -Name $TenantID -PublicMachineName $PublicMachineName -TenantID $TenantID -clickOnceWebSiteDirectory $httpWebSiteDirectory
        }

        Add-Content -Path  "$httpWebSiteDirectory\tenants.txt" -Value $TenantID

        if ($CreateSharePointPortal) {
            Log "Create SharePoint Portal on $SharePointSiteUrl"
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

        New-Item "C:\MT\$TenantID" -ItemType Directory -Force -ErrorAction Ignore | Out-null
        $URLsFile = ("C:\MT\$TenantID\URLs.txt")        "Web Client URL         : https://$PublicMachineName/NAV/WebClient?tenant=$TenantID"                 | Set-Content -Path $URLsFile
        "Tablet Client URL      : https://$PublicMachineName/NAV/WebClient/tablet.aspx?tenant=$TenantID"     | Add-Content -Path $URLsFile
       ("Device URL             : https://$PublicMachineName/NAV"+"?tenant=$TenantID")                       | Add-Content -Path $URLsFile
       ("Device (configure) URL : ms-dynamicsnav://$PublicMachineName/NAV"+"?tenant=$TenantID")              | Add-Content -Path $URLsFile
    
        if ($SharePointAdminLoginName) {
            "Web Client URL (AAD)   : https://$PublicMachineName/AAD/WebClient?tenant=$TenantID"             | Add-Content -Path $URLsFile
            "Tablet Client URL (AAD): https://$PublicMachineName/AAD/WebClient/tablet.aspx?tenant=$TenantID" | Add-Content -Path $URLsFile
           ("Device URL             : https://$PublicMachineName/AAD"+"?tenant=$TenantID")                   | Add-Content -Path $URLsFile
           ("Device (configure) URL : ms-dynamicsnav://$PublicMachineName/AAD"+"?tenant=$TenantID")          | Add-Content -Path $URLsFile
        }
        if ($CreateSharePointPortal) {
            "SharePoint Portal      : $SharePointUrl/sites/$TenantID"                                        | Add-Content -Path $URLsFile
        }
        "WinClient Local URL    : dynamicsnav://///?tenant=$TenantID"                                        | Add-Content -Path $URLsFile
        "WinClient ClickOnce URL: http://$PublicMachineName/$TenantID"                                       | Add-Content -Path $URLsFile

        $SharePointParams = @{}
        if ($SharePointAdminLoginName) {
            $SharePointParams += @{"AuthenticationEmail" = "$SharePointAdminLoginName"}
        }
        $createuser = $true
        Get-NavServerUser $serverInstance -Tenant $TenantID | % {
            if ($_.UserName -eq $NavAdminUser) {
                Set-NavServerUser $serverInstance -Tenant $TenantId -UserName $NavAdminUser -Password (ConvertTo-SecureString -String $NavAdminPassword -AsPlainText -Force) @SharePointParams
                $createuser = $false
            }
        }
        if ($createuser) {
            New-NavServerUser $serverInstance -Tenant $TenantId -UserName $NavAdminUser -Password (ConvertTo-SecureString -String $NavAdminPassword -AsPlainText -Force) @SharePointParams
            New-NavServerUserPermissionSet $serverInstance -Tenant $TenantID -UserName $NavAdminUser -PermissionSetId "SUPER"
        }

        Log -OnlyInfo "" 
        Log -OnlyInfo -kind Emphasis "URLs"
        Get-Content $URLsFile | Log -OnlyInfo
        Log -OnlyInfo ""
        Log -kind Success "Tenant $TenantID successfully added"
    }
}

function Remove-DemoTenant
{
	Param
	(
		[Parameter(Mandatory=$True)]
		[string]$TenantID
    )

    if (!$multitenant) {
        Log -kind Error "System not setup for multi tenancy"
    } else {
        Log "Dismount tenant $TenantID"
        Dismount-NAVTenant -ServerInstance $serverInstance -Tenant $TenantID -Force
        
        Remove-NavDatabase -DatabaseName $TenantID

        Log "Cleanup"
        Remove-Item "C:\MT\$TenantID" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $httpWebSiteDirectory $TenantID) -Recurse -Force -ErrorAction SilentlyContinue
        
        $tenants = Get-Content -Path "$httpWebSiteDirectory\tenants.txt"
        Clear-Content -Path "$httpWebSiteDirectory\tenants.txt"
        $tenants | % {
            if ($_ -ne $TenantID) {
                Add-Content -Path "$httpWebSiteDirectory\tenants.txt" -Value $_
            }
        }

        Log -kind Success "Tenant $TenantID successfully removed"
    }
}

Function Get-DemoTenantList {

    if (!$multitenant) {
        Log -kind Error "System not setup for multi tenancy"
    } else {
        get-navtenant $serverInstance | % { Log -kind Info -OnlyInfo $_.Id }
    }
}

Export-ModuleMember -Function "New-DemoTenant", "Remove-DemoTenant", "Get-DemoTenantList"
