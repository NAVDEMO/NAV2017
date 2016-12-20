$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$verbosePreference =  'SilentlyContinue'
$errorActionPreference = 'Stop'
. (Join-Path $PSScriptRootV2 '..\Common\HelperFunctions.ps1')

Clear
Log -kind Emphasis -OnlyInfo "Welcome to the New Developer Experience Installation script."
Log -kind Info -OnlyInfo ""
Log -kind Info -OnlyInfo "This script will help you setup Visual Studio Code and the AL code extension."
Log -kind Info -OnlyInfo ""

Log "Read Settings"
$DVDfolder = (Get-ChildItem -Path "C:\NAVDVD" -Directory | where-object { Test-Path -Path (Join-Path $_.FullName "WindowsPowerShellScripts") -PathType Container } | Select-Object -First 1).FullName
$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name
$DatabaseFolder = Join-Path (Get-ChildItem -Path "$DVDFolder\SQLDemoDatabase\CommonAppData\Microsoft\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).FullName "Database"
$DatabaseName = (Get-ChildItem -Path $DatabaseFolder -Filter "*.bak" -File).BaseName

$CustomSettingsConfigFile = "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\CustomSettings.config"
$config = [xml](Get-Content $CustomSettingsConfigFile)
$multitenant = ($config.SelectSingleNode("//appSettings/add[@key='Multitenant']").value -ne "false")
$serverInstance = $config.SelectSingleNode("//appSettings/add[@key='ServerInstance']").value

Log "Import Modules"
# If the VM is not initialized, import US or W1
if (Test-Path -Path (Join-Path $PSScriptRootV2 'US') -PathType Container) {
    . (Join-Path $PSScriptRootV2 '..\Profiles\US.ps1')
} elseif (Test-Path -Path (Join-Path $PSScriptRootV2 'W1') -PathType Container) {
    . (Join-Path $PSScriptRootV2 '..\Profiles\W1.ps1')
}
if (Test-Path (Join-Path $PSScriptRootV2 '..\Profiles.ps1')) {
    . (Join-Path $PSScriptRootV2 '..\Profiles.ps1')
}
. "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1" | Out-Null

$Folder = "C:\DOWNLOAD\VSCode"
$Filename = "$Folder\VSCodeSetup-stable.exe"
New-Item $Folder -itemtype directory -ErrorAction ignore | Out-Null
    
if (!(Test-Path $Filename)) {
    Log "Downloading Visual Studio Code Setup Program"
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://go.microsoft.com/fwlink/?LinkID=623230", $Filename)
}

Log "Installing Visual Studio Code"
$setupParameters = “/VerySilent /CloseApplications /NoCancel /LoadInf=""c:\demo\vscode.inf"" /MERGETASKS=!runcode"
Start-Process -FilePath $Filename -WorkingDirectory $Folder -ArgumentList $setupParameters -Wait -Passthru | Out-Null

Log "Remove and add http binding for local access using Windows Auth"
Get-WebBinding -Name "Microsoft Dynamics NAV 2017 Web Client" -Protocol http | Remove-WebBinding
New-WebBinding -Name "Microsoft Dynamics NAV 2017 Web Client" -Port 8080 -Protocol http -IPAddress "*" | Out-Null

Log "Setup NetTcpPortSharing"
Start-Process -FilePath "sc.exe" -ArgumentList @("config", "NetTcpPortSharing", "start=auto") -Wait | Out-Null
Start-Process -FilePath "sc.exe" -ArgumentList @("start",  "NetTcpPortSharing") –Wait | Out-Null

Log "Create Developer Service Tier"
$DevInstance = "Navision_main"
if (!(Get-NAVServerInstance -ServerInstance $DevInstance)) {
    New-NAVServerInstance -ServerInstance $DevInstance `
                          -DatabaseServer localhost `
                          -DatabaseInstance NAVDEMO `
                          -DatabaseName $DatabaseName `
                          -ClientServicesPort 7146 `
                          -ManagementServicesPort 7145 `
                          -SOAPServicesPort 7147 `
                          -ODataServicesPort 7148 `
                          -DeveloperServicesPort 7049 `
                          -ClientServicesCredentialType Windows `
                          -ServiceAccount NetworkService
    
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName "PublicWebBaseUrl" -KeyValue "http://localhost:8080/$DevInstance/WebClient/" -WarningAction Ignore

    Log "Set Service tier to depend on NetTcpPort Sharing"
    Start-Process -FilePath "sc.exe" -ArgumentList @("config", ('MicrosoftDynamicsNavServer$'+$DevInstance), "depend= NetTcpPortSharing/HTTP") -Wait | Out-Null

    Log "Start Service Tier"
    Set-NAVServerInstance -ServerInstance $DevInstance -Start
    
    Log "Create Windows User Account in NAV"
    new-navserveruser -ServerInstance $DevInstance -tenant default -WindowsAccount ([Environment]::UserName)
    New-NAVServerUserPermissionSet -ServerInstance $DevInstance -tenant default -WindowsAccount ([Environment]::UserName) -PermissionSetId SUPER

    Log "Read Standard Web.config"
    $NAVWebConfigFile = "C:\inetpub\wwwroot\$ServerInstance\Web.config"
    $NAVWebConfig = [xml](Get-Content $NAVWebConfigFile)
    $designerKey = $NAVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='designer']")
    if ($designerkey) {
        $designerkey.value = "true"
    } else {
        $addelm = $NAVWebConfig.CreateElement("add")
        $keyatt = $NAVWebConfig.CreateAttribute("key")
        $keyatt.Value = "designer"
        $addelm.Attributes.Append($keyatt) | Out-Null
        $valatt = $NAVWebConfig.CreateAttribute("value")
        $valatt.Value = "true"
        $addelm.Attributes.Append($valatt) | Out-Null
        $NAVWebConfig.configuration.DynamicsNAVSettings.AppendChild($addelm) | Out-Null
    }
    $NAVWebConfig.Save($NAVWebConfigFile)
    
    Log "Create NAV Web Server Instance"
    Write-Host -ForegroundColor Green "Create Web Server Instance"
    New-NAVWebServerInstance -ServerInstance $DevInstance -WebServerInstance $DevInstance -Server localhost -RegionFormat "en-US" -Language en-US -Company $Company -ClientServicesPort 7146
    
    Log "Change dev instance Web.config"
    $DEVWebConfigFile = "C:\inetpub\wwwroot\$DevInstance\Web.config"
    $DEVWebConfig = [xml](Get-Content $DEVWebConfigFile)
    $DEVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='HelpServer']").value = $NAVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='HelpServer']").value
    $DEVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='FeedbackLink']").value = "https://github.com/Microsoft/AL/issues"
    $DEVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='CommunityLink']").value = "https://github.com/Microsoft/AL/issues"
    $designerKey = $DEVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='designer']")
    if ($designerkey) {
        $designerkey.value = "true"
    } else {
        $addelm = $DEVWebConfig.CreateElement("add")
        $keyatt = $DEVWebConfig.CreateAttribute("key")
        $keyatt.Value = "designer"
        $addelm.Attributes.Append($keyatt) | Out-Null
        $valatt = $DEVWebConfig.CreateAttribute("value")
        $valatt.Value = "true"
        $addelm.Attributes.Append($valatt) | Out-Null
        $DEVWebConfig.configuration.DynamicsNAVSettings.AppendChild($addelm) | Out-Null
    }
    $DEVWebConfig.Save($DEVWebConfigFile)
    
    Log "Create Windows Client config"
    $TemplateClientUserSettingsFile = "C:\DEMO\Extensions\ClientUserSettings.config"
    $DevClientUserSettingsFile = "C:\DEMO\Extensions\${DevInstance}ClientUserSettings.config"
    $config = [xml](Get-Content $TemplateClientUserSettingsFile)
    $config.SelectSingleNode("//configuration/appSettings/add[@key='ServerInstance']").value = $DevInstance
    $config.SelectSingleNode("//configuration/appSettings/add[@key='TenantId']").value = "default"
    $config.Save($DevClientUserSettingsFile)

    Log "Change Default Role Center to 9022"
    Invoke-sqlcmd -ea stop -ServerInstance "localhost\NAVDEMO" -QueryTimeout 0 `
    "USE [$DatabaseName]
    GO
    UPDATE [dbo].[Profile]
       SET [Default Role Center] = 0
    GO
    UPDATE [dbo].[Profile]
       SET [Default Role Center] = 1
     WHERE [Role Center ID] = 9022
    GO"  -WarningAction SilentlyContinue
}

Log "Copy Resources"
$CountryFolder = Join-Path $PSScriptRootV2 $Language
$ResourcesFolder = Join-Path $PSScriptRootV2 "Resources"
Remove-Item -Path $ResourcesFolder -Recurse -Force -ErrorAction Ignore
New-Item -Path $ResourcesFolder -ItemType Directory -Force -ErrorAction Ignore | Out-Null
Copy-Item -Path (Join-Path $CountryFolder "*.vsix") -Destination $PSScriptRootV2
Copy-Item -Path (Join-Path $CountryFolder "*.navx") -Destination $ResourcesFolder

Log "Download samples"
$Folder = "C:\DOWNLOAD"
$Filename = "$Folder\samples.zip"
New-Item "c:\download" -ItemType Directory -ErrorAction Ignore
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile("https://www.github.com/Microsoft/AL/archive/master.zip", $filename)
Remove-Item -Path "$folder\AL-master" -Force -Recurse -ErrorAction Ignore | Out-null
UnzipFolder -file $filename -destination $folder
Copy-Item -Path "$folder\AL-master\*" -Destination $PSScriptRootV2 -Recurse -Force -ErrorAction Ignore

if ([Environment]::UserName -ne "SYSTEM") {
    $alFolder = "C:\Users\$([Environment]::UserName)\Documents\AL"
    Remove-Item -Path "$alFolder\Samples" -Recurse -Force -ErrorAction Ignore | Out-Null
    New-Item -Path "$alFolder\Samples" -ItemType Directory -Force -ErrorAction Ignore | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRootV2 "Samples\*") -Destination "$alFolder\Samples" -Recurse -ErrorAction Ignore

    New-Item -Path "$alFolder\Resources" -ItemType Directory -Force -ErrorAction Ignore | Out-Null
    Copy-Item -Path (Join-Path $CountryFolder "*.navx") -Destination "$alFolder\Resources"
}

Log "install vsix"
$code = "C:\Program Files (x86)\Microsoft VS Code\bin\Code.cmd"
Get-ChildItem -Path $PSScriptRootV2 -Filter "*.vsix" | % {
   Start-Process -FilePath "$code" -ArgumentList @('--install-extension', $_.FullName) -WorkingDirectory $PSScriptRootV2 -Wait
}

Log "Create Desktop Shortcuts"
New-DesktopShortcut -Name "$DevInstance Web Client"               -TargetPath "http://localhost:8080/$DevInstance/WebClient/?tenant=default" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"

Log "Cleanup"
Remove-Item "C:\DOWNLOAD\AL-master" -Recurse -Force -ErrorAction Ignore
Remove-Item "C:\DOWNLOAD\VSCode" -Recurse -Force -ErrorAction Ignore
Remove-Item "C:\DOWNLOAD\samples.zip" -Force -ErrorAction Ignore

if ([Environment]::UserName -ne "SYSTEM") {
    Log "Start VS Code with the Hello World app"
    $HelloWorldFolder = ('"'+"C:\Users\$([Environment]::UserName)\Documents\AL\samples\HelloWorld"+'"')
    $codeexe = "C:\Program Files (x86)\Microsoft VS Code\Code.exe"
    Start-Process -FilePath "$codeexe" -ArgumentList @($HelloWorldFolder)
}

Log -kind Success "New Developer Experience Installation succeeded"
