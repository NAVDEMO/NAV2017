function New-ClickOnceDeployment
{
    param (
        [parameter(Mandatory=$true)]
        [string]$Name,
        [parameter(Mandatory=$true)]
        [string]$PublicMachineName,
        [parameter(Mandatory=$true)]
        [string]$TenantID,
        [parameter(Mandatory=$true)]
        [string]$clickOnceWebSiteDirectory
    )

    Log "Creating Click-Once manifest for $TenantID"
    $clickOnceDirectory = Join-Path $clickOnceWebSiteDirectory $Name
    $webSiteUrl = ("http://" + $PublicMachineName + "/" + $Name)

    $NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name
    $clientUserSettingsFileName = Join-Path $env:ProgramData "Microsoft\Microsoft Dynamics NAV\$NavVersion\ClientUserSettings.config"
    [xml]$ClientUserSettings = Get-Content $clientUserSettingsFileName
    $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='Server']").value=$PublicMachineName
    $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='TenantId']").value=$TenantID
    $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='ServicesCertificateValidationEnabled']").value="false"


    if ($Name -eq 'AAD') {
        [xml]$webConfig = Get-Content 'C:\inetpub\wwwroot\AAD\web.config'
        $ACSUri = ($webConfig.SelectSingleNode("//configuration/DynamicsNAVSettings/add[@key='ACSUri']").value + "%26wreply=https://$PublicMachineName/AAD/WebClient")
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='ACSUri']").value = $ACSUri
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key='ClientServicesCredentialType']").value = 'AccessControlService'        
    }

    $applicationName = "Microsoft Dynamics NAV 2017 Windows Client for $PublicMachineName ($Name)"
    $applicationPublisher = "Microsoft Corporation"
    
    New-ClickOnceDirectory -ClickOnceDirectory $clickOnceDirectory -ClientUserSettings $clientuserSettings

    $MageExeLocation = Join-Path $PSScriptRoot 'mage.exe'
    
    $clickOnceApplicationFilesDirectory = Join-Path $clickOnceDirectory 'Deployment\ApplicationFiles'

    # Remove more unnecessary stuff
    Get-ChildItem $clickOnceApplicationFilesDirectory -include '*.etx' -Recurse | Remove-Item
    Get-ChildItem $clickOnceApplicationFilesDirectory -include '*.stx' -Recurse | Remove-Item
    Get-ChildItem $clickOnceApplicationFilesDirectory -include '*.chm' -Recurse | Remove-Item
    Remove-Item (Join-Path $clickOnceApplicationFilesDirectory 'SLT') -force -Recurse -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $clickOnceApplicationFilesDirectory 'NavModelTools.ps1') -force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $clickOnceApplicationFilesDirectory 'ClientUserSettings.lnk') -force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $clickOnceApplicationFilesDirectory 'Microsoft.Dynamics.Nav.Model.Tools.*') -force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $clickOnceApplicationFilesDirectory 'Microsoft.Dynamics.Nav.Ide.psm1') -force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $clickOnceApplicationFilesDirectory 'Cronus.flf') -force -ErrorAction SilentlyContinue
    
    $applicationManifestFile = Join-Path $clickOnceApplicationFilesDirectory 'Microsoft.Dynamics.Nav.Client.exe.manifest'
    $applicationIdentityName = "$PublicMachineName ClickOnce $Name"
    $applicationIdentityVersion = '9.0.0.0'
    
    Set-ApplicationManifestFileList `
        -ApplicationManifestFile $ApplicationManifestFile `
        -ApplicationFilesDirectory $ClickOnceApplicationFilesDirectory `
        -MageExeLocation $MageExeLocation
    Set-ApplicationManifestApplicationIdentity `
        -ApplicationManifestFile $ApplicationManifestFile `
        -ApplicationIdentityName $ApplicationIdentityName `
        -ApplicationIdentityVersion $ApplicationIdentityVersion
    
    $deploymentManifestFile = Join-Path $clickOnceDirectory 'Deployment\Microsoft.Dynamics.Nav.Client.application'
    $deploymentIdentityName = "$PublicMachineName ClickOnce $Name"
    $deploymentIdentityVersion = '9.0.0.0'
    $deploymentManifestUrl = ($webSiteUrl + "/Deployment/Microsoft.Dynamics.Nav.Client.application")
    $applicationManifestUrl = ($webSiteUrl + "/Deployment/ApplicationFiles/Microsoft.Dynamics.Nav.Client.exe.manifest")
    
    Set-DeploymentManifestApplicationReference `
        -DeploymentManifestFile $DeploymentManifestFile `
        -ApplicationManifestFile $ApplicationManifestFile `
        -ApplicationManifestUrl $ApplicationManifestUrl `
        -MageExeLocation $MageExeLocation
    Set-DeploymentManifestSettings `
        -DeploymentManifestFile $DeploymentManifestFile `
        -DeploymentIdentityName $DeploymentIdentityName `
        -DeploymentIdentityVersion $DeploymentIdentityVersion `
        -ApplicationPublisher $ApplicationPublisher `
        -ApplicationName $ApplicationName `
        -DeploymentManifestUrl $DeploymentManifestUrl
    
    # Put a web.config file in the root folder, which will tell IIS which .html file to open
    $sourceFile = Join-Path $PSScriptRoot 'root_web.config'
    $targetFile = Join-Path $clickOnceDirectory 'web.config'
    Copy-Item $sourceFile -destination $targetFile
    
    # Put a web.config file in the Deployment folder, which will tell IIS to allow downloading of .config files etc.
    $sourceFile = Join-Path $PSScriptRoot 'deployment_web.config'
    $targetFile = Join-Path $clickOnceDirectory 'Deployment\web.config'
    Copy-Item $sourceFile -destination $targetFile
}

function Copy-NavDatabase([string]$SourceDatabaseName, [string]$DestinationDatabaseName)
{
    Log "Copy NAV Database from $SourceDatabaseName to $DestinationDatabaseName"

    if (Test-NavDatabase -DatabaseName $DestinationDatabaseName)
    {
        Log "Remove Destination Database [$DestinationDatabaseName]"
        Remove-NavDatabase -DatabaseName $DestinationDatabaseName
    }

    if (!($DatabaseServerParams.ServerInstance.StartsWith('localhost'))) {

        Log "Create [$DestinationDatabaseName] on $($DatabaseServerParams.ServerInstance)"
        Invoke-SqlCmdWithRetry -Query "CREATE Database [$DestinationDatabaseName] AS COPY OF [$SourceDatabaseName];"
        # Wait for the Database to become ready
        Start-Sleep -Seconds 30

    } else {

        try
        {
            Log "Using SQL Express"
            Log "Take database [$SourceDatabaseName] offline"
            Invoke-SqlCmdWithRetry -Query ("ALTER DATABASE [{0}] SET OFFLINE WITH ROLLBACK IMMEDIATE" -f $SourceDatabaseName)
    
            Log "copy database files"
            $DatabaseFiles = @()
            (Invoke-SqlCmdWithRetry -Query ("SELECT Physical_Name as filename FROM sys.master_files WHERE DB_NAME(database_id) = '{0}'" -f $SourceDatabaseName)).filename | ForEach-Object {
                  $FileInfo = Get-Item -Path $_
                  $DestinationFile = "{0}\{1}{2}" -f $FileInfo.DirectoryName, $DestinationDatabaseName, $FileInfo.Extension
    
                  Copy-Item -Path $FileInfo.FullName -Destination $DestinationFile -Force
    
                  $DatabaseFiles = $DatabaseFiles + $DestinationFile
                }
    
            $Files = "(FILENAME = N'{0}'), (FILENAME = N'{1}')" -f $DatabaseFiles[0], $DatabaseFiles[1]
    
            Log "Attach files as new Database [$DestinationDatabaseName]"
            Invoke-SqlCmdWithRetry -Query ("CREATE DATABASE [{0}] ON {1} FOR ATTACH" -f $DestinationDatabaseName, $Files.ToString())
        }
        finally
        {
            Log "Put database [$SourceDatabaseName] back online"
            Invoke-SqlCmdWithRetry -Query ("ALTER DATABASE [{0}] SET ONLINE" -f $SourceDatabaseName)
        }
    }
}

function Test-NavDatabase([string]$DatabaseName)
{
    $sqlCommandText = @"
    USE MASTER
    SELECT '1' FROM SYS.DATABASES WHERE NAME = '$DatabaseName'
    GO
"@

    return ((Invoke-SqlCmdWithRetry -Query $sqlCommandText) -ne $null)
}

function Remove-NavDatabase
(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName
)
{
    Log "Remove Database [$DatabaseName]"
 
    # Get database files in case they are not removed by the DROP
    $DatabaseFiles = Get-NavDatabaseFiles -DatabaseName $DatabaseName
 
    # SQL Express - take database offline
    if ($DatabaseServerParams.ServerInstance.StartsWith('localhost')) {
        Invoke-SqlCmdWithRetry -Query "ALTER DATABASE [$DatabaseName] SET OFFLINE WITH ROLLBACK IMMEDIATE"
    }
    Invoke-SqlCmdWithRetry -Query "DROP DATABASE [$DatabaseName]"
 
    # According to MSDN database files are not removed after dropping an offline database, we need to manually delete them
    $DatabaseFiles | ? { Test-Path $_ } | Remove-Item -Force
 
}

function Set-NavDatabaseTenantId
(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    [Parameter(Mandatory=$true)]
    [string]$TenantId
)
{
    Invoke-SqlCmdWithRetry -Database $DatabaseName -Query ('UPDATE [dbo].[$ndo$tenantproperty] SET [tenantid] = '''+$TenantId+''';')
}

function Mount-NavDatabase
(
    [Parameter(Mandatory=$false)]
    [string]$ServerInstance = "NAV",
    [Parameter(Mandatory=$true)]
    [string]$TenantId,
    [Parameter(Mandatory=$false)]
    [string]$DatabaseName = $TenantId,
    [Parameter(Mandatory=$false)]
    [string[]]$AlternateId = @()
)
{
    Log "Mount NAV Database for $TenantID on server $($DatabaseServerParams.ServerInstance)"
    $Params = @{}
    if ($TenantId -eq "default") {
        $Params += @{"AllowAppDatabaseWrite"=$true }
    }

    $DatabaseServer = ($DatabaseServerParams.ServerInstance+"\").Split('\')[0]
    $DatabaseInstance = ($DatabaseServerParams.ServerInstance+"\").Split('\')[1]

    if ($DatabaseServer -ne "localhost") {
        $DatabaseCredentials = New-Object PSCredential -ArgumentList $DatabaseServerParams.UserName, (ConvertTo-SecureString -String $DatabaseServerParams.Password -AsPlainText -Force)
        $Params = @{ "DatabaseCredentials"=$DatabaseCredentials; "Force"=$true }
    }

    Log "Change TenantId"
    Set-NavDatabaseTenantId -DatabaseName $DatabaseName -TenantId $TenantID

    Log "Mount"
    Mount-NAVTenant -ServerInstance $ServerInstance -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName $DatabaseName -Id $TenantID -AlternateId $AlternateId @Params
}

function Get-NavDatabaseFiles
(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName
)
{
    if ($DatabaseServerParams.ServerInstance.StartsWith('localhost')) {
        Invoke-SqlCmdWithRetry -Query "SELECT f.physical_name FROM sys.sysdatabases db INNER JOIN sys.master_files f ON f.database_id = db.dbid WHERE db.name = '$DatabaseName'" |
            % {
                $file = $_.physical_name
                if (Test-Path $file)
                {
                    $file = Resolve-Path $file
                }
                $file
            }
    }
}

function Invoke-SqlCmdWithRetry
(
    [Parameter(Mandatory=$false)]
    [string]$Database,
    [Parameter(Mandatory=$true)]
    [string]$Query
)
{
    $maxattempts = 10
    if ($DatabaseServerParams.ServerInstance.StartsWith('localhost')) {
        $maxattempts = 1
    }
    $attempt = 1
    $success = $false
    while (!$success) {
        try
        {
            if ($Database) {
                Invoke-SqlCmd @DatabaseServerParams -Database $Database -Query $Query
            } else {
                Invoke-SqlCmd @DatabaseServerParams -Query $Query
            }
            $success = $true
        }
        catch {
            if ($attempt -ge $maxattempts) {
                Log -kind Error "Error when running: $Query"
                throw    
            }
            Log -kind Warning "Warning, exception when running: $Query"
            $waittime = (Get-Random -Minimum 1 -Maximum 3)*60
            Start-Sleep -Seconds $waittime
            Log "Retrying..."
            $attempt = $attempt + 1
        }
    }
}
