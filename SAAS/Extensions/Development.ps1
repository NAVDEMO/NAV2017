$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$verbosePreference = 'SilentlyContinue'
$errorActionPreference = 'Stop'

$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name

. (Join-Path $PSScriptRootV2 '..\Common\HelperFunctions.ps1')
. "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1" | Out-Null
. "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\NavModelTools.ps1" | Out-Null

Remove-Module Development -ErrorAction Ignore
Import-Module (Join-Path $PSScriptRootV2 "Development.psm1") -DisableNameChecking

Log -OnlyInfo -kind Emphasis "Extension Development Demo Shell"
Log -OnlyInfo 
Log -OnlyInfo -kind Emphasis "Maintaining Dev Instances"
Log -OnlyInfo  "New-DevInstance        To add a Dev Instance"
Log -OnlyInfo  "Remove-DevInstance     To remove a Dev Instance"
Log -OnlyInfo  "Remove-AllDevInstances To remove all Dev Instances"
Log -OnlyInfo  "Get-DevInstance        Get a list of Dev Instances"
Log -OnlyInfo 
Log -OnlyInfo -kind Emphasis "Developing/Testing"
Log -OnlyInfo  "Start-NavWebCli        Start Web Client for a Dev Instance"
Log -OnlyInfo  "Start-NavWinCli        Start Windows Client for a Dev Instance"
Log -OnlyInfo  "Start-NavDevExp        Start Developer Experience for a Dev Instance"
Log -OnlyInfo  "Start-NavDebugger      Start Debugger for a Dev Instance"
Log -OnlyInfo 
Log -OnlyInfo -kind Emphasis "Deltas/.navX management"
Log -OnlyInfo  "Import-AppFolderDeltas Import Deltas from an AppFolder (BingMaps, O365 Integration, ...)"
Log -OnlyInfo  "Update-AppFolderDeltas Update Deltas folder in an AppFolder"
Log -OnlyInfo  "Update-AppFolderNavx   Update Deltas folder and update extenstion (.navx) in an AppFolder"
Log -OnlyInfo 
Log -OnlyInfo -kind Emphasis "Testing extensions in Dev Instance"
Log -OnlyInfo  "Publish-AppfolderNavX  Publish extenstion (.navx) in a Dev Instance"
Log -OnlyInfo  "Install-AppfolderNavX  Install extenstion (.navx) in a Dev Instance"
Log -OnlyInfo 
Log -OnlyInfo -kind Emphasis "Testing extensions in Main Instance"
Log -OnlyInfo  "Publish-Extension      Publish Extension (.NavX)"
Log -OnlyInfo  "Install-Extension      Install Extension"
Log -OnlyInfo  "UnInstall-Extension    UnInstall Extension"
Log -OnlyInfo  "UnPublish-Extension    UnPublish Extension"
Log -OnlyInfo 
Log -OnlyInfo  -kind Emphasis "Dev Instances:"
Get-DevInstance | % { Log -OnlyInfo ("Name: " + $_.DevInstance + ", Language: " + $_.Language) }
