function Install-Git
{
    $gitexe = "C:\Program Files\Git\bin\git.exe"

    if (!(Test-Path -Path $gitexe -PathType Leaf)) {
        $url = "https://github.com/git-for-windows/git/releases/download/v2.11.0.windows.1/Git-2.11.0-64-bit.exe"
        $downloadFolder = "C:\DOWNLOAD"
        New-Item -Path $downloadFolder -ItemType Directory -ErrorAction Ignore | Out-Null
        
        $filename = ("$downloadFolder\"+$url.Substring($url.LastIndexOf("/")+1))
        $WebClient = New-Object System.Net.WebClient
        $status = $WebClient.DownloadFile($url, $Filename)
        Start-Process -FilePath $Filename -WorkingDirectory $downloadFolder -ArgumentList @("/verysilent") -Wait -Passthru | Out-Null
    }
    $gitexe
}

$gitexe = Install-Git

$documentsFolder = [environment]::getfolderpath(“mydocuments”)

$perfFolder = "$documentsFolder\NAVPERF"
New-Item $perfFolder -ItemType Directory -ErrorAction Ignore | Out-Null
$nav2017sampleUrl = "https://github.com/NAVPERF/NAV2017-Sample"
Start-Process $gitexe -WorkingDirectory $perfFolder -ArgumentList @("clone", $nav2017sampleUrl) -Wait -PassThru | Out-Null

# Find NAV Version
$DVDfolder = (Get-ChildItem -Path "C:\NAVDVD" -Directory | where-object { Test-Path -Path (Join-Path $_.FullName "WindowsPowerShellScripts") -PathType Container } | Select-Object -First 1).FullName
$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name

# Find Public WebBase Url for Username/Password endpoint
$CustomSettingsConfigFile = "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\CustomSettings.config"
$config = [xml](Get-Content $CustomSettingsConfigFile)
$PublicWebBaseUrl = $config.SelectSingleNode("//appSettings/add[@key='PublicWebBaseUrl']").value.Replace('/AAD/','/NAV/')
$serverInstance = $config.SelectSingleNode("//appSettings/add[@key='ServerInstance']").value

if ($PublicWebBaseUrl -ne "") {
    . "c:\demo\multitenancy\hardcodeinput.ps1"
    # Modify app.config
    $appConfigFile = "$perfFolder\NAV2017-Sample\Microsoft.Dynamics.Nav.LoadTest\app.config"
    $appConfig = [xml](Get-Content $appConfigFile)
    $appConfig.SelectSingleNode("//configuration/applicationSettings/Microsoft.Dynamics.Nav.LoadTest.Properties.Settings/setting[@name='NAVClientService']").value = ($PublicWebBaseUrl.Replace('/AAD/','/NAV/')+'cs')
    $appConfig.SelectSingleNode("//configuration/applicationSettings/Microsoft.Dynamics.Nav.LoadTest.Properties.Settings/setting[@name='NAVUserName']").value = $NavAdminUser
    $appConfig.SelectSingleNode("//configuration/applicationSettings/Microsoft.Dynamics.Nav.LoadTest.Properties.Settings/setting[@name='NAVUserPassword']").value = $NavAdminPassword
    $appConfig.SelectSingleNode("//configuration/applicationSettings/Microsoft.Dynamics.Nav.LoadTest.Properties.Settings/setting[@name='UseWindowsAuthentication']").value = "False"
    $appConfig.Save($appConfigFile)
}

. ("c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1") | Out-Null
0..9 | % {
    New-NAVServerUser -ServerInstance $serverInstance -UserName "$navAdminUser$_" -Password (ConvertTo-SecureString -String $NavAdminPassword -AsPlainText -Force) -LicenseType Full
    New-NAVServerUserPermissionSet -ServerInstance $serverInstance -UserName "$navAdminUser$_" -PermissionSetId SUPER
}

& "$perfFolder\NAV2017-Sample\Microsoft.Dynamics.Nav.LoadTest.sln"