$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$verbosePreference = 'SilentlyContinue'
$errorActionPreference = 'Stop'
. (Join-Path $PSScriptRootV2 '..\Common\HelperFunctions.ps1')


Clear
Log -kind Emphasis -OnlyInfo "Welcome to the Extension Development Shell Installation script."
Log -kind Info -OnlyInfo ""
Log -kind Info -OnlyInfo "This script will help you get started developing extensions in your Microsoft Dynamics NAV DEMO Environment."
Log -kind Info -OnlyInfo "The script will add a Shortcut to your desktop to the Extension Development Shell, in which you can:"
Log -kind Info -OnlyInfo "- Create new Developer Instances of NAV with any country version."
Log -kind Info -OnlyInfo "- Remove Developer Instances."
Log -kind Info -OnlyInfo "- Import DELTAs from any of the existing Extensions (BingMaps, MSBand, O365 Integration)."
Log -kind Info -OnlyInfo "- Update NavX files with changes from the developer experience."
Log -kind Info -OnlyInfo "- Test your extension with Web or Windows Client using Windows Authentication (Desktop shortcuts)."
Log -kind Info -OnlyInfo ""

Log "Read Settings"
$HardcodeFile = (Join-Path $PSScriptRootV2 'HardcodeInput.ps1')
if (Test-Path -Path $HardcodeFile) {
    . $HardcodeFile
}

$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name
Log "NAV Version: $NavVersion"

. "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1" | Out-Null

$licenseFile = "None"
$files = Get-ChildItem -Path (Join-Path $PSScriptRootV2 "*.flf")
if ($files) {
    $licenseFile = $files[0].FullName
}
do {
    $licenseFile = Get-UserInput -Id LicenseFile -Text "Import License File From Path/Url (Enter None to skip license import)" -Default $licenseFile
    if ($licenseFile.StartsWith("http://") -or $licenseFile.StartsWith("https://")) {
        $Folder = "C:\DOWNLOAD"
        New-Item $Folder -itemtype directory -ErrorAction ignore
        $Filename = "$Folder\Developer License.flf"
        try {
            Log "Downloading $licenseFile to $FileName"
            Invoke-WebRequest $licenseFile -OutFile $Filename
            $licenseFile = $Filename
        } catch {
            Log -kind Error "Error downloading $licenseFile to $FileName"
        }
    }
} until (($licenseFile -eq "None") -or (Test-Path -Path $licenseFile))

if ($licenseFile -ne "None") {
    Log "Import License File $LicenseFile"
    $NavIde = "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe"
    Import-NAVServerLicense -ServerInstance NAV -LicenseFile $LicenseFile -WarningAction SilentlyContinue | Out-Null
    if ($licensefile -ne "C:\DEMO\Extensions\license.flf") {
        Copy-Item -Path $licensefile -Destination "C:\DEMO\Extensions\license.flf" -Force -ErrorAction Ignore | Out-Null
    }
}

$TranslateApiKey = Get-Content -Path "c:\DEMO\Extensions\Translate.key" -ErrorAction Ignore
$TranslateApiKey = Get-UserInput -Id TranslateApiKey -Text "Microsoft Azure Cognitive Services Translator Text API Key (Empty if you don't want auto-translation of texts)" -Default $TranslateApiKey
Set-Content -Path "c:\DEMO\Extensions\Translate.key" -Value $TranslateApiKey

# Remove and add http binding for local access using Windows Auth
Log "Recreate Web Bindings for Web Client"
Get-WebBinding -Name "Microsoft Dynamics NAV 2017 Web Client" -Protocol http | Remove-WebBinding
New-WebBinding -Name "Microsoft Dynamics NAV 2017 Web Client" -Port 8080 -Protocol http -IPAddress "*" | Out-Null

Log "Start NetTcpPortSharing Service"
Start-Process -FilePath "sc.exe" -ArgumentList @("config", "NetTcpPortSharing", "start=auto") -Wait
Start-Process -FilePath "sc.exe" -ArgumentList @("start", "NetTcpPortSharing") –Wait

Log "Create Desktop Shortcuts"
$DemoAdminShell = Join-Path $PSScriptRootV2 'Development.ps1'
New-DesktopShortcut -Name "Extension Development Demo Shell" -TargetPath "C:\Windows\system32\WindowsPowerShell\v1.0\PowerShell.exe" -WorkingDirectory $PSScriptRootV2 -Arguments "-NoExit & '$DemoAdminShell'"

Log -kind Success "Extension Development Shell Installation succeeded"

Log -OnlyInfo -kind Emphasis "Please Open Extension Development Demo Shell to develop Extensions"
