$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$verbosePreference = "SilentlyContinue"
$WarningPreference = "SilentlyContinue"
$errorActionPreference = 'Stop'

$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name

. (Join-Path $PSScriptRootV2 '..\Common\HelperFunctions.ps1')
. "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1"
. "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\NavModelTools.ps1"
Import-Module SQLPS | Out-Null

$TranslateApiKey = Get-Content -Path "c:\DEMO\Extensions\Translate.key" -ErrorAction Ignore

function Remove-AllDevInstances {
    get-DevInstance | % {
        Remove-DevInstance -DevInstance $_.DevInstance
    }
}

function Remove-DevInstance {
	Param
	(
		[Parameter(Mandatory=$true)]
		[string]$DevInstance
    )

    Log -OnlyInfo -kind Emphasis "Remove NAV Instance $DevInstance"

    $DatabaseName = (get-DevInstance $DevInstance).DatabaseName
    $DatabasePath = Join-Path $PSScriptRootV2 "${DevInstance}Db"
    $DevClientUserSettingsFile = "C:\DEMO\Extensions\${DevInstance}ClientUserSettings.config"

    # Remove "old" DEV NAV Instance
    Log -OnlyInfo "Removing NAV Server Instance"
    Remove-NAVServerInstance -ServerInstance $DevInstance -Force -ErrorAction Ignore
    
    # Remove "old" Dev Web Server Instance
    Log -OnlyInfo "Removing NAV Web Server Instance"
    Remove-NAVWebServerInstance $DevInstance -Force -ErrorAction Ignore

    # Remove "old" DEV Database
    Log -OnlyInfo "Removing Database [$DatabaseName]"
    Push-Location
    Invoke-sqlcmd -ErrorAction Ignore -WarningAction SilentlyContinue -ServerInstance "localhost\NAVDEMO" -QueryTimeout 0 `
    "USE [master]
    alter database [$DatabaseName] set single_user with rollback immediate"
    Invoke-sqlcmd -ErrorAction Ignore -WarningAction SilentlyContinue -ServerInstance "localhost\NAVDEMO" -QueryTimeout 0 `
    "USE [master]
    drop database [$DatabaseName]"
    Pop-Location
    Remove-Item -Path $DatabasePath -Force -ErrorAction Ignore
        
    # Remove Developer Client User Settings Config
    Log -OnlyInfo "Removing ClientUserSettings File"
    Remove-Item -Path $DevClientUserSettingsFile -Force -ErrorAction Ignore

    # Remove Database folder
    Log -OnlyInfo "Removing Desktop Shortcuts"
    Remove-DesktopShortcut -Name "$DevInstance Windows Client"
    Remove-DesktopShortcut -Name "$DevInstance Web Client"
    Remove-DesktopShortcut -Name "$DevInstance Development Environment"
    Remove-DesktopShortcut -Name "$DevInstance Debugger"

    Log -OnlyInfo -kind Success "Remove-DevInstance Success"
}

function Copy-NavDatabase([string]$SourceDatabaseName, [string]$DestinationDatabaseName)
{
    Log "Copy NAV Database from $SourceDatabaseName to $DestinationDatabaseName"

    try
    {
        Log "Using SQL Express"
        Log "Take database [$SourceDatabaseName] offline"
        Invoke-SqlCmd -ea stop -ServerInstance "localhost\NAVDEMO" -Query ("ALTER DATABASE [{0}] SET OFFLINE WITH ROLLBACK IMMEDIATE" -f $SourceDatabaseName)

        Log "copy database files"
        $DatabaseFiles = @()
        (Invoke-SqlCmd -ea stop -ServerInstance "localhost\NAVDEMO" -Query ("SELECT Physical_Name as filename FROM sys.master_files WHERE DB_NAME(database_id) = '{0}'" -f $SourceDatabaseName)).filename | ForEach-Object {
              $FileInfo = Get-Item -Path $_
              $DestinationFile = "{0}\{1}{2}" -f $FileInfo.DirectoryName, $DestinationDatabaseName, $FileInfo.Extension

              Copy-Item -Path $FileInfo.FullName -Destination $DestinationFile -Force

              $DatabaseFiles = $DatabaseFiles + $DestinationFile
            }

        $Files = "(FILENAME = N'{0}'), (FILENAME = N'{1}')" -f $DatabaseFiles[0], $DatabaseFiles[1]

        Log "Attach files as new Database [$DestinationDatabaseName]"
        Invoke-SqlCmd -ea stop -ServerInstance "localhost\NAVDEMO" -Query ("CREATE DATABASE [{0}] ON {1} FOR ATTACH" -f $DestinationDatabaseName, $Files.ToString())
    }
    finally
    {
        Log "Put database [$SourceDatabaseName] back online"
        Invoke-SqlCmd -ea stop -ServerInstance "localhost\NAVDEMO" -Query ("ALTER DATABASE [{0}] SET ONLINE" -f $SourceDatabaseName)
    }
}

function New-DevInstance
{
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV",
		[Parameter(Mandatory=$false)]
		[string]$Language,
		[Parameter(Mandatory=$false)]
		[string]$AppFolder,
		[Parameter(Mandatory=$false)]
		[switch]$Stopped
    )

    if ($Language) {
        . "C:\DEMO\Profiles\$Language.ps1"
    } else {
        . "C:\DEMO\Profiles.ps1"
    }

    $SourcesFolder = "C:\DEMO\$AppFolder\Sources";

    Log -OnlyInfo -kind Emphasis "Create NAV Instance $DevInstance"

    $NavIde = "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe"
    $DatabaseName = "$Language $DevInstance Database"
    $DatabasePath = Join-Path $PSScriptRootV2 "${DevInstance}Db"
    $TxtFile      = Join-Path $PSScriptRootV2 "$Language.txt"
    $TxtFolder    = Join-Path $PSScriptRootV2 "$Language"
    $LangTxtFile  = Join-Path $PSScriptRootV2 "$Language-Language.txt"
    $LangTxtFolder= Join-Path $PSScriptRootV2 "$Language-Language"
    $TemplateClientUserSettingsFile = "C:\DEMO\Extensions\ClientUserSettings.config"
    $DevClientUserSettingsFile = "C:\DEMO\Extensions\${DevInstance}ClientUserSettings.config"
    
    $exists = $false
    Get-NAVServerInstance | % {
        if ($DevInstance -eq $_.Attributes[0].Value.SubString(27)) {
            Log -OnlyInfo "Remove old Instance"
            Remove-DevInstance -DevInstance $DevInstance
        }
    }

    if ($Language.StartsWith("365")) {

        Copy-NavDatabase -SourceDatabaseName "DEMO Database NAV (10-0)" -DestinationDatabaseName $DatabaseName

    } else {

        # Restore Database
        Log -OnlyInfo "Restore Database [$DatabaseName] for instance"
        $BakFolder = Join-Path (Get-ChildItem -Path "C:\NAVDVD\$Language\SQLDemoDatabase\CommonAppData\Microsoft\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).FullName "Database"
        $BakFile = (Get-ChildItem -Path $BakFolder -Filter "*.bak" -File).FullName
        New-NAVDatabase -DatabaseServer localhost -DatabaseInstance NAVDEMO -DatabaseName $DatabaseName -FilePath $bakFile -DestinationPath $DatabasePath -Timeout 0 | Out-Null

    }
    
    Log "Remove Users, Remove Servers, Clear Modified, Change Default Role Center to 9022"
    Invoke-sqlcmd -ea stop -ServerInstance "localhost\NAVDEMO" -QueryTimeout 0 `
        "USE [$DatabaseName]
        DELETE FROM [dbo].[Access Control]
        DELETE FROM [dbo].[User]
        DELETE FROM [dbo].[User Property]
        DELETE FROM [dbo].[Server Instance]
        GO
        UPDATE [dbo].[Object] SET [Modified] = 0
        GO
        UPDATE [dbo].[Profile] SET [Default Role Center] = 0
        GO
        UPDATE [dbo].[Profile] SET [Default Role Center] = 1 WHERE [Role Center ID] = 9022
        GO"  -WarningAction SilentlyContinue

    # Create NAV Service Tier
    Log -OnlyInfo "Create Service Tier"
    New-NAVServerInstance -ServerInstance $DevInstance `
                          -DatabaseServer localhost `
                          -DatabaseInstance NAVDEMO `
                          -DatabaseName $DatabaseName `
                          -ClientServicesPort 7146 `
                          -ManagementServicesPort 7145 `
                          -SOAPServicesPort 7147 `
                          -ODataServicesPort 7148 `
                          -ClientServicesCredentialType Windows `
                          -ServiceAccount NetworkService

    Start-Process -FilePath "sc.exe" -ArgumentList @("config", ('MicrosoftDynamicsNavServer$'+$DevInstance), "depend= NetTcpPortSharing/HTTP") -Wait
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName 'DatabaseUserName' -KeyValue ""
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName 'ProtectedDatabasePassword' -KeyValue ""
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName 'EnableSqlConnectionEncryption' -KeyValue ""
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName 'Multitenant' -KeyValue $false
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName 'ServicesDefaultCompany' -KeyValue $Company
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName 'PublicODataBaseUrl' -KeyValue "http://localhost:7148/$DevInstance/OData/"
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName 'PublicSOAPBaseUrl' -KeyValue "http://localhost:7147/$DevInstance/WS/"
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName 'PublicWebBaseUrl' -KeyValue "http://localhost:8080/$DevInstance/WebClient/"
    Set-NAVServerConfiguration -ServerInstance $DevInstance -KeyName 'PublicWinBaseUrl' -KeyValue "dynamicsnav://localhost:7146/$DevInstance/"
    
    Log -OnlyInfo "Start Service Tier"
    Set-NAVServerInstance -ServerInstance $DevInstance -Start

    # Import license
    Log -OnlyInfo "Import License file to Dev Instance Database"
    Import-NAVServerLicense -ServerInstance $DevInstance -LicenseFile "C:\DEMO\Extensions\license.flf" -Database NavDatabase -WarningAction SilentlyContinue | Out-Null
    
    # Get Standard Web.config
    $NAVWebConfigFile = "C:\inetpub\wwwroot\NAV\Web.config"
    $NAVWebConfig = [xml](Get-Content $NAVWebConfigFile)
    
    # Create NAV Web Server Instance
    Log -OnlyInfo "Create Web Server Instance"
    New-NAVWebServerInstance -ServerInstance $DevInstance -WebServerInstance $DevInstance -Server localhost -ClientServicesPort 7146
    
    # Change DEV Web.config
    $DEVWebConfigFile = "C:\inetpub\wwwroot\$DevInstance\Web.config"
    $DEVWebConfig = [xml](Get-Content $DEVWebConfigFile)
    $DEVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='HelpServer']").value = $NAVWebConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='HelpServer']").value
    $DEVWebConfig.Save($DEVWebConfigFile)
    
    if (!(Test-Path $TxtFolder -PathType Container)) 
    {
        if (!($Language.StartsWith("365"))) {
            Log -OnlyInfo "Install Local Installers"
            # Install local installers
            if (Test-Path "C:\NAVDVD\$Language\Installers" -PathType Container) {
                Get-ChildItem "C:\NAVDVD\$Language\Installers" | Where-Object { $_.PSIsContainer } | % {
                    Get-ChildItem $_.FullName | Where-Object { $_.PSIsContainer } | % {
                        $dir = $_.FullName
                        Get-ChildItem (Join-Path $dir "*.msi") | % { 
                            Log -OnlyInfo ("Installing "+$_.FullName)
                            Start-Process -FilePath $_.FullName -WorkingDirectory $dir -ArgumentList "/qn /norestart" -Wait
                        }
                    }
                }
            }
        }

        # Export Standard $Language
        Remove-Item -Path $TxtFile -Force -ErrorAction Ignore
        Log -OnlyInfo "Export Objects for $Language to $TxtFile"
        Export-NAVApplicationObject -Path $TxtFile -DatabaseServer "localhost\NAVDEMO" -DatabaseName $DatabaseName -ExportTxtSkipUnlicensed | Out-Null
        Log -OnlyInfo "Split $TxtFile to $TxtFolder"
        Split-NAVApplicationObjectFile -Source $TxtFile -Destination $TxtFolder
        Remove-Item -Path $TxtFile -Force -ErrorAction Ignore
    }

    if (!(Test-Path $LangTxtFolder -PathType Container)) 
    {
        # Export Language $Language
        Remove-Item -Path $LangTxtFile -Force -ErrorAction Ignore
        Log -OnlyInfo "Export Language for $Language to $LangTxtFile"
        Export-NAVApplicationObjectLanguage -Source $TxtFolder -Destination $LangTxtFile

        # Export Standard $Language
        Log -OnlyInfo "Split $LangTxtFile to $LangTxtFolder"
        Split-NAVApplicationObjectLanguageFile -Source $LangTxtFile -Destination $LangTxtFolder
        Remove-Item -Path $LangTxtFile -Force -ErrorAction Ignore
    }
        
    # Create Desktop Shortcuts
    $config = [xml](Get-Content $TemplateClientUserSettingsFile)
    $config.SelectSingleNode("//configuration/appSettings/add[@key='ServerInstance']").value = $DevInstance
    $config.Save($DevClientUserSettingsFile)
    
    New-DesktopShortcut -Name "$DevInstance Windows Client"           -TargetPath "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\Microsoft.Dynamics.Nav.Client.exe" -Arguments "-Language:1033 -Settings:$DevClientUserSettingsFile"
    New-DesktopShortcut -Name "$DevInstance Web Client"               -TargetPath "http://localhost:8080/$DevInstance/WebClient/" -IconLocation "C:\Program Files\Internet Explorer\iexplore.exe, 3"
    New-DesktopShortcut -Name "$DevInstance Development Environment"  -TargetPath "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe" -Arguments "servername=localhost\NAVDEMO, database=$DatabaseName, ntauthentication=1"
    New-DesktopShortcut -Name "$DevInstance Debugger"                 -TargetPath "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\Microsoft.Dynamics.Nav.Client.exe" -Arguments "-Language:1033 -Settings:$DevClientUserSettingsFile ""dynamicsnav:////debug"""
    
    if ($AppFolder) {

        if (!(Test-Path $SourcesFolder -PathType Container)) {
            New-Item -path $SourcesFolder -ItemType Directory -Force -ErrorAction Ignore | Out-Null
        }

        Log -OnlyInfo "Import Deltas for AppFolder"
        Import-AppFolderDeltas -DevInstance $DevInstance -AppFolder $AppFolder
    }

    if ($Stopped) {
        Log -OnlyInfo "Stop Service Tier"
        Set-NAVServerInstance -ServerInstance $DevInstance -Stop
    }

    Log -OnlyInfo -kind Success "New-DevInstance Success"
}

function get-DevInstance
{
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance
    )

    Get-NAVServerInstance | % {
        $instance = $_.Attributes[0].Value.SubString(27)
        $ServiceDir = "C:\Program Files\Microsoft Dynamics NAV\$NavVersion\Service\Instances\$instance"
        if (Test-Path $ServiceDir -PathType Container) {
            $config = [xml](Get-Content "C:\Program Files\Microsoft Dynamics NAV\$NavVersion\Service\Instances\$instance\CustomSettings.config")
            $DatabaseName = $config.SelectSingleNode("//appSettings/add[@key='DatabaseName']").value
            $ClientServicesCredentialType = $config.SelectSingleNode("//appSettings/add[@key='ClientServicesCredentialType']").value
            if ($ClientServicesCredentialType -eq "Windows") {
                $idx = $DatabaseName.IndexOf(" ")
                $Language = $DatabaseName.Substring(0,$idx)
                if (!($DevInstance) -or ($DevInstance -eq $instance))
                {
                    New-Object PSObject -Property @{ DevInstance = $instance; Language = $Language; DatabaseName = $DatabaseName }
                }
            }
        }    
    }
}

function Import-AppFolderDeltas
{
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV",
		[Parameter(Mandatory=$true)]
		[string]$AppFolder
    )

    $SourcesFolder      = "C:\DEMO\$AppFolder\Sources"
    $ClientAddinsFolder = "C:\DEMO\$AppFolder\Client Add-Ins"
    $MergeResultsFile   = "C:\DEMO\$AppFolder\Temp\$DevInstance-MergeResult.txt"

    Log -OnlyInfo -kind Emphasis "Using NAV instance: $DevInstance"
    
    $DevInstanceObj = get-DevInstance $DevInstance
    $DatabaseName = $devInstanceObj.DatabaseName
    $Language = $DevInstanceObj.Language
    $NavIde = "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe"
    $TxtFolder = Join-Path $PSScriptRootV2 "$Language"
    $PrereqFile = "C:\DEMO\$AppFolder\$Language Prereq.fob"
    
    . "C:\DEMO\profiles\$Language.ps1"

    if (!(Test-Path $SourcesFolder -PathType Container)) {
        Log "Create $SourcesFolder"
        New-Item -path $SourcesFolder -ItemType Directory -Force -ErrorAction Ignore | Out-Null
    }

    if (Test-Path $ClientAddinsFolder -PathType Container) {
        Log "Copy Client Add-ins from $ClientAddinsFolder"
        Copy-Item -Path (Join-Path $ClientAddinsFolder "*.dll") -Destination "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\Add-ins" -Force -ErrorAction Ignore
        Copy-Item -Path (Join-Path $ClientAddinsFolder "*.dll") -Destination "C:\Program Files\Microsoft Dynamics NAV\$NavVersion\Service\Add-ins" -Force -ErrorAction Ignore
    }

    # Create folder with Orginal files for "my" delta files
    $OrgFolder   = "C:\DEMO\$AppFolder\Temp\Original-$DevInstance"
    Log -OnlyInfo "Copy original objects to $OrgFolder for all objects that are modified"
    Remove-Item -Path $OrgFolder -Recurse -Force -ErrorAction Ignore
    New-Item -Path $OrgFolder -ItemType Directory | Out-Null
    Get-ChildItem $SourcesFolder -Filter "*.DELTA" | % {
        $Name = $_.BaseName
        $OrgName = Join-Path $OrgFolder "$Name.TXT"
        $TxtFile = Join-Path $TxtFolder "$Name.TXT"
        if (Test-Path -Path $TxtFile) {
            Copy-Item -Path $TxtFile -Destination $OrgName
        }
    }
    
    # Merge Deltas
    $newTxtFile = "C:\DEMO\$AppFolder\Temp\$DevInstance.txt"
    Log -OnlyInfo "Merge deltas from $SourcesFolder with $orgFolder and create $newTxtFile"
    Remove-Item $newTxtFile -Force -ErrorAction Ignore
    $DeltaFolder = "C:\DEMO\$AppFolder\Temp\Deltas-$DevInstance"
    Remove-Item $DeltaFolder -Recurse -Force -ErrorAction Ignore
    New-Item -Path $DeltaFolder -ItemType Directory | Out-Null
    Copy-Item -Path (Join-Path $SourcesFolder "*.DELTA") -Destination $DeltaFolder
    Update-NAVApplicationObject -TargetPath $orgFolder -DeltaPath $deltaFolder -ResultPath $newTxtFile -ModifiedProperty Yes -VersionListProperty FromModified -DateTimeProperty FromModified | Set-Content $MergeResultsFile
    Log -OnlyInfo "MergeResults in $MergeResultsFile"

    if (Test-Path -Path $PrereqFile) {
        Log -OnlyInfo "Import pre-requisite .fob file"
        Import-NAVApplicationObject  -DatabaseServer 'localhost\NAVDEMO' -DatabaseName $DatabaseName -NavServerName localhost -NavServerInstance $DevInstance -NavServerManagementPort 7145 -SynchronizeSchemaChanges Force -ImportAction Overwrite -Confirm:$false -Path $PrereqFile
    }
    
    # Import and compile objects
    if (Test-Path $newTxtFile) {
        Log -OnlyInfo "Import merged objects from $newTxtFile"
        Import-NAVApplicationObject  -DatabaseServer 'localhost\NAVDEMO' -DatabaseName $DatabaseName -NavServerName localhost -NavServerInstance $DevInstance -NavServerManagementPort 7145 -SynchronizeSchemaChanges Force -ImportAction Overwrite -Confirm:$false -Path $newTxtFile
        Start-sleep -Seconds 10
        Log -OnlyInfo "Compile Objects"
        Compile-NAVApplicationObject -DatabaseServer 'localhost\NAVDEMO' -DatabaseName $DatabaseName -NavServerName localhost -NavServerInstance $DevInstance -NavServerManagementPort 7145 -SynchronizeSchemaChanges Force -Filter "Compiled=No" 
    }
    Log -OnlyInfo -kind Success "Import-AppFolderDeltas Success"
}

function Update-AppFolderDeltas
{
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV",
		[Parameter(Mandatory=$true)]
		[string]$AppFolder
    )

    if (Test-Path -Path "C:\DEMO\$AppFolder\AppSettings.ps1") {
        . "C:\DEMO\$AppFolder\AppSettings.ps1"
    } else {
        $AppName = "$AppFolder Demo"
        $AppGuid = [Guid]::NewGuid().ToString()
    	$AppVersion = "1.0.0.0"
    	$AppPublisher = "Microsoft"
    	$AppFileName = "C:\DEMO\$AppFolder\$AppFolder.navx"
        $AppSrcLanguage = 1033
        $AppLanguages = @()
    }

    $SourcesFolder = "C:\DEMO\$AppFolder\Sources"
    if (!(Test-Path $SourcesFolder -PathType Container)) {
        New-Item -path $SourcesFolder -ItemType Directory -Force -ErrorAction Ignore | Out-Null
    }

    Log -OnlyInfo -kind Emphasis "Using NAV instance: $DevInstance"

    $DevInstanceObj = get-DevInstance $DevInstance
    $DatabaseName = $devInstanceObj.DatabaseName
    $Language = $DevInstanceObj.Language
    $NavIde = "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe"
    $TxtFolder      = Join-Path $PSScriptRootV2 "$Language"
                    
    $ObjFile        = "C:\DEMO\$AppFolder\Temp\Modified-$DevInstance.txt"
    $ObjFolder      = "C:\DEMO\$AppFolder\Temp\Modified-$DevInstance"
    $OrgFolder      = "C:\DEMO\$AppFolder\Temp\Original-$DevInstance"
    $DeltaFolder    = "C:\DEMO\$AppFolder\Temp\Deltas-$DevInstance"

    $LangObjFile    = "C:\DEMO\$AppFolder\Temp\Modified-$DevInstance-Lang.txt"
    $LangOrgFile    = "C:\DEMO\$AppFolder\Temp\Original-$DevInstance-Lang.txt"
    $LangObjFolder  = "C:\DEMO\$AppFolder\Temp\Modified-$DevInstance-Lang"
    $LangOrgFolder  = "C:\DEMO\$AppFolder\Temp\Original-$DevInstance-Lang"
    $LangDeltaFolder= "C:\DEMO\$AppFolder\Temp\Deltas-$DevInstance-Lang"

    # Export Modified Objects
    Log -OnlyInfo "Export Modified objects to $ObjFile"
    Remove-Item -Path $ObjFile -Force -ErrorAction Ignore
    Export-NAVApplicationObject -Path $ObjFile -DatabaseServer "localhost\NAVDEMO" -DatabaseName $DatabaseName -ExportTxtSkipUnlicensed -Filter 'Modified=Yes' | Out-Null

    Log -OnlyInfo "Split $ObjFile into individual object files in $objFolder"
    Remove-Item -Path $ObjFolder -Recurse -Force -ErrorAction Ignore
    New-Item -Path $ObjFolder -ItemType Directory | Out-Null
    Split-NAVApplicationObjectFile -Source $ObjFile -Destination $ObjFolder | Out-Null
    
    Log -OnlyInfo "Copy original $Language objects to $OrgFolder for all objects that are modified"
    Remove-Item -Path $OrgFolder -Recurse -Force -ErrorAction Ignore
    New-Item -Path $OrgFolder -ItemType Directory | Out-Null
    Get-ChildItem $ObjFolder | % {
        $Name = $_.Name
        $OrgName = Join-Path $OrgFolder $Name
        $TxtFile = Join-Path $TxtFolder $Name
        if (Test-Path -Path $TxtFile) {
            Copy-Item -Path $TxtFile -Destination $OrgName
        }
    }
    
    # Compare / Create Deltas
    Log -OnlyInfo "Compare modified objects in $ObjFolder with original objects in $orgFolder and create Deltas in $deltaFolder"
    Remove-Item -Path $DeltaFolder -Recurse -Force -ErrorAction Ignore
    New-Item -Path $DeltaFolder -ItemType Directory | Out-Null
    Compare-NAVApplicationObject -OriginalPath $orgFolder -ModifiedPath $ObjFolder -DeltaPath $deltaFolder | Out-Null

    # Copy DELTA files to sources
    Remove-Item (Join-Path $sourcesFolder "*.DELTA") -ErrorAction Ignore
    Copy-Item -Path (Join-Path $DeltaFolder "*.DELTA") -Destination $SourcesFolder

    Log "Export Language from modified objects"
    Remove-Item -Path $LangObjFile -Force -ErrorAction Ignore
    Export-NAVApplicationObjectLanguage -Source $ObjFolder -Destination $LangObjFile
    Remove-Item -Path $LangObjFolder -Recurse -ErrorAction Ignore
    Split-NAVApplicationObjectLanguageFile -Source $LangObjFile -Destination $LangObjFolder

    Log "Export Language from original objects"
    Remove-Item -Path $LangOrgFile -Force -ErrorAction Ignore
    Export-NAVApplicationObjectLanguage -Source $OrgFolder -Destination $LangOrgFile
    Remove-Item -Path $LangOrgFolder -Recurse -ErrorAction Ignore
    Split-NAVApplicationObjectLanguageFile -Source $LangOrgFile -Destination $LangOrgFolder

    Log "Compare language files"
    Remove-Item -Path $LangDeltaFolder -Recurse -ErrorAction Ignore
    Compare-NAVAppApplicationObjectLanguage -OriginalPath $LangOrgFolder -ModifiedPath $LangObjFolder -DeltaPath $LangDeltaFolder | Out-Null

    # Copy TXT files to sources
    Remove-Item (Join-Path $sourcesFolder "*-strings.TXT") -ErrorAction Ignore
    Copy-Item -Path (Join-Path $LangDeltaFolder "*-Strings.TXT") -Destination $SourcesFolder

    $SrcLangName = [System.Globalization.CultureInfo]::GetCultureInfo($AppSrcLanguage).Name.Substring(0,2)
    # Update txt files for supported languages
    $AppLanguages | % {
        $AllLines = @()
        $AppLanguage = $_
        $LangName = [System.Globalization.CultureInfo]::GetCultureInfo($AppLanguage).Name
        $LangFileName = (Join-Path $sourcesFolder "$AppLanguage-$LangName.TXT")

        $langlines = new-object system.collections.arraylist
        if (Test-Path $LangFileName) {
            $langlines.AddRange([System.IO.File]::ReadAllLines($LangFileName))
        }
        $changes = $false
        Get-ChildItem -Path $SourcesFolder -Filter "*-Strings.TXT" | % {
            $SrcLangFileName = $_.FullName
            $lines = [System.IO.File]::ReadAllLines($SrcLangFileName)
            $alllines += $lines
            $lines | % {
                $line = $_.Replace("-A$AppSrcLanguage-","-A$AppLanguage-")
                $colonidx = $line.IndexOf(':')
                $existing = $lines | Where-Object { $_.StartsWith($line.Substring(0, $colonidx+1)) }
                if (!($existing)) {
                    $alreadyadded = $langlines | Where-Object { $_.StartsWith($line.Substring(0, $colonidx+1)) }
                    if (!($alreadyadded)) {
                        $text = $line.Substring($colonidx+1)
                        if ($TranslateApiKey) {
                            $from = $SrcLangName
                            $to = $LangName
                            $text = TranslateText -ApiKey $TranslateApiKey -from $from -to $to -text $text
                        }
                        $langlines.Add($line.Substring(0,$colonidx+1)+$text) | Out-Null
                        $changes = $true
                    }
                }
            }
        }

        $i = 0;
        while ($i -lt $langlines.Count) {
            $line = $langlines[$i]
            $colonidx = $line.IndexOf(':')
            $existing1 = $alllines | Where-Object { $_.StartsWith($line.Substring(0, $colonidx+1)) }

            # Check that if controls has been removed
            $line = $langlines[$i].Replace("-A$AppLanguage-","-A$AppSrcLanguage-")
            $colonidx = $line.IndexOf(':')
            $existing2 = $alllines | Where-Object { $_.StartsWith($line.Substring(0, $colonidx+1)) }

            if ($existing1) {
                # Line exists in exported file with this language code - remove it from language file
                # Developer must have added the translation to the object
                $langlines.RemoveAt($i) 
                $changes = $true
            } elseif ($existing2) {
                # Line still exists in the exported file with Src Language code - everything is fine
                $i++
            } else {
                # Line doesn't exist in the exported file - remove it from language file
                # Developer must have deleted the string from the object
                $langlines.RemoveAt($i) 
                $changes = $true
            }
        }
        if ($changes) {
            Log -OnlyInfo "$AppLanguage-$LangName Updated"
            Remove-Item -Path $LangFileName -Force -ErrorAction Ignore
            [System.IO.File]::WriteAllLines($LangFileName, $langlines, [System.Text.Encoding]::UTF8)
        }
    }

    Log -OnlyInfo -kind Success "Update-AppFolderDeltas Success"
}

function Update-AppFolderNavx
{
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV",
		[Parameter(Mandatory=$true)]
		[string]$AppFolder
    )

    if (Test-Path -Path "C:\DEMO\$AppFolder\AppSettings.ps1") {
        . "C:\DEMO\$AppFolder\AppSettings.ps1"
    } else {
        $AppName = "$AppFolder Demo"
        $AppGuid = [Guid]::NewGuid().ToString()
    	$AppVersion = "1.0.0.0"
    	$AppPublisher = "Microsoft"
    	$AppFileName = "C:\DEMO\$AppFolder\$AppFolder.navx"
        $AppSrcLanguage = 1033
        $AppLanguages = @()
    }

    $SourcesFolder = "C:\DEMO\$AppFolder\Sources"

    Log -OnlyInfo -kind Emphasis "Using NAV instance: $DevInstance"

    Log -OnlyInfo "Update Deltas files in $SourcesFolder from database"
    Remove-Item $AppFilename -Force -ErrorAction Ignore
    Update-AppFolderDeltas -DevInstance $DevInstance -AppFolder $AppFolder

    $logo = "C:\DEMO\$AppFolder\logo.png"
    $newappparms = @{}
    if (Test-Path -Path $logo -PathType Leaf) {
        $newappparms += @{"logo" = $logo}
    }

    Log -OnlyInfo "Create $AppName navx file in $AppFilename"
    New-NAVAppManifest -Name $AppName -Publisher $AppPublisher -Id $AppGuid -Version $AppVersion | 
        New-NAVAppPackage $AppFilename -SourcePath $SourcesFolder @newappparms

    Log -OnlyInfo -kind Success "Update-AppFolderNavx Success"
}

function install-AppfolderNavX {
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV",
		[Parameter(Mandatory=$true)]
		[string]$AppFolder
    )

    if (Test-Path -Path "C:\DEMO\$AppFolder\AppSettings.ps1") {
        . "C:\DEMO\$AppFolder\AppSettings.ps1"
    } else {
        $AppName = "$AppFolder Demo"
    	$AppFileName = "C:\DEMO\$AppFolder\$AppFolder.navx"
    }

    publish-AppfolderNavX -DevInstance $DevInstance -AppFolder $AppFolder
    Log -OnlyInfo "Install $AppName"
    Install-NAVApp -ServerInstance $DevInstance -Name $AppName
}

function publish-AppfolderNavX {
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV",
		[Parameter(Mandatory=$true)]
		[string]$AppFolder
    )

    Log -OnlyInfo -kind Emphasis "Using NAV instance: $DevInstance"

    if (Test-Path -Path "C:\DEMO\$AppFolder\AppSettings.ps1") {
        . "C:\DEMO\$AppFolder\AppSettings.ps1"
    } else {
        $AppName = "$AppFolder Demo"
    	$AppFileName = "C:\DEMO\$AppFolder\$AppFolder.navx"
    }

    # Prereq object file (only for demo extensions)
    $PrereqFile = "C:\DEMO\$AppFolder\$Language Prereq.fob"
    if (Test-Path -Path $PrereqFile) {
    
        $DevInstanceObj = get-DevInstance $DevInstance
        $DatabaseName = $devInstanceObj.DatabaseName
        $Language = $DevInstanceObj.Language
        $NavIde = "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe"
    
        Log -OnlyInfo "Import pre-requisite .fob file"
        Import-NAVApplicationObject -DatabaseServer 'localhost\NAVDEMO' -DatabaseName $DatabaseName -Path $PrereqFile -SynchronizeSchemaChanges Force -NavServerName localhost -NavServerInstance $DevInstance -NavServerManagementPort 7145 -ImportAction Overwrite -Confirm:$false
    }

    Log -OnlyInfo "Uninstall $AppName (if already installed)"
    UnInstall-NAVApp -ServerInstance $DevInstance -Name $AppName -ErrorAction Ignore
    Log -OnlyInfo "Unpublish $AppName (if already published)"
    UnPublish-NAVApp -ServerInstance $DevInstance -Name $AppName -ErrorAction Ignore
    Log -OnlyInfo "Publish $AppName"
    Publish-NAVApp -ServerInstance $DevInstance -Path $AppFilename -SkipVerification
}

function Start-NavWebCli {
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV"
    )
    [Diagnostics.Process]::Start("http://localhost:8080/$DevInstance/WebClient/")
}

function Start-NavWinCli {
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV"
    )
    $DevClientUserSettingsFile = "C:\DEMO\Extensions\${DevInstance}ClientUserSettings.config"
    Start-Process -FilePath "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\Microsoft.Dynamics.Nav.Client.exe" -ArgumentList @("-Language:1033", "-Settings:$DevClientUserSettingsFile")
}

function Start-NavDevExp {
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV"
    )
    $DevInstanceObj = get-DevInstance $DevInstance
    $DatabaseName = $devInstanceObj.DatabaseName
    $Command = ('& ' + """C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\finsql.exe""" + ' --% servername=localhost\NAVDEMO, database=' + $DatabaseName + ', ntauthentication=1')
    Invoke-Expression $Command
}

function Start-NavDebugger {
	Param
	(
		[Parameter(Mandatory=$false)]
		[string]$DevInstance = "DEV"
    )
    $DevClientUserSettingsFile = "C:\DEMO\Extensions\${DevInstance}ClientUserSettings.config"
    Start-Process -FilePath "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\Microsoft.Dynamics.Nav.Client.exe" -ArgumentList @("-Language:1033", "-Settings:$DevClientUserSettingsFile", "dynamicsnav:////debug")
}

function Publish-Extension {
    Param
    (
		[Parameter(Mandatory=$true)]
		[string]$Path,
		[Parameter(Mandatory=$false)]
		[string[]]$Addins,
		[Parameter(Mandatory=$false)]
        [switch]$installIt
    )

    $ServerInstance = "NAV"

    if (!(Test-Path -Path $Path -PathType Leaf)) {
        Log -kind Error -OnlyInfo "Extension '$Path' does not exist"
    }

    $AppInfo = Get-NavAppInfo -Path $Path
    UnPublish-Extension -Name $AppInfo.Name

    # Copy Add-ins to Add-ins folders
    if ($Addins) {
        $Addins | % {
            if (!(Test-Path -Path $_ -PathType Leaf)) {
                Log -kind Error -OnlyInfo "Addin '$_' does not exist"
            }
            $name = [System.IO.Path]::GetFileName($_)
            Log -OnlyInfo "Copy '$Name' to Add-ins"
            Copy-Item -Path $_ -Destination "C:\Program Files\Microsoft Dynamics NAV\$NavVersion\Service\Add-ins\$name" -Force -ErrorAction Ignore | Out-Null
            Copy-Item -Path $_ -Destination "C:\Program Files (x86)\Microsoft Dynamics NAV\$NavVersion\RoleTailored Client\Add-ins\$name" -Force -ErrorAction Ignore | Out-Null
        }
    }

    $SandBoxParams = @{}
    if ($isSaaS) {
        $SandBoxParams = @{
            'SandboxDatabaseName' = 'Sandbox Database'
            'SandboxDatabaseServer' =  'localhost\NAVDEMO'
        }
    }
        
    Log -OnlyInfo "Publish Extension '$Path'"
    Publish-NAVApp @SandBoxParams -Path $Path -SkipVerification -Force -ServerInstance $ServerInstance -PackageType Extension
    if ($InstallIt) {
        Install-Extension -Name $AppInfo.Name
    }
}

function Install-Extension {
    Param
    (
		[Parameter(Mandatory=$true)]
		[string]$Name,
		[Parameter(Mandatory=$false)]
		[string]$TenantId
    )

    $ServerInstance = "NAV"
    if ($tenantId) {
        Log -OnlyInfo "Installing '$Name' to Tenant '$TenantId'"
        Install-NavApp -ServerInstance $ServerInstance -Name $Name -Tenant $TenantId
    } else {
        Get-NAVTenant -ServerInstance $ServerInstance | % {
            $TenantId = $_.Id
            Log -OnlyInfo "Installing '$Name' to Tenant '$TenantId'"
            Install-NavApp -ServerInstance $ServerInstance -Name $Name -Tenant $_.Id
        }
    }
}

function UnInstall-Extension {
    Param
    (
		[Parameter(Mandatory=$true)]
		[string]$Name,
		[Parameter(Mandatory=$false)]
		[string]$TenantId
    )

    $ServerInstance = "NAV"
    if ($tenantId) {
        Log -OnlyInfo "Uninstalling '$Name' from Tenant '$TenantId' (if installed)"
        UnInstall-NavApp -ServerInstance $ServerInstance -Name $Name -Tenant $TenantId -ErrorAction Ignore
    } else {
        Get-NAVTenant -ServerInstance $ServerInstance | % {
            $TenantId = $_.Id
            Log -OnlyInfo "Uninstalling '$Name' from Tenant '$TenantId' (if installed)"
            UnInstall-NavApp -ServerInstance $ServerInstance -Name $Name -Tenant $TenantId -ErrorAction Ignore
        }
    }
}

function UnPublish-Extension {
    Param
    (
		[Parameter(Mandatory=$true)]
		[string]$Name
    )

    $ServerInstance = "NAV"
    UnInstall-Extension -Name $Name
    Log "Unpublish Extension '$Name' (if published)"
    Unpublish-NAVApp -ServerInstance $ServerInstance -Name $Name -ErrorAction Ignore
}

