$PSScriptRootV2 = Split-Path $MyInvocation.MyCommand.Definition -Parent 
Set-StrictMode -Version 2.0
$verbosePreference = 'Continue'
$errorActionPreference = 'Stop'

$HardcodeFile = (Join-Path $PSScriptRootV2 'HardcodeInput.ps1')
if (Test-Path -Path $HardcodeFile) {
    . $HardcodeFile
}
$DVDfolder = (Get-ChildItem -Path "C:\NAVDVD" -Directory | where-object { Test-Path -Path (Join-Path $_.FullName "WindowsPowerShellScripts") -PathType Container } | Select-Object -First 1).FullName
$NavVersion = (Get-ChildItem -Path "c:\program files\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).Name
$DatabaseFolder = Join-Path (Get-ChildItem -Path "$DVDFolder\SQLDemoDatabase\CommonAppData\Microsoft\Microsoft Dynamics NAV" -Directory | Select-Object -Last 1).FullName "Database"
$DatabaseName = (Get-ChildItem -Path $DatabaseFolder -Filter "*.bak" -File).BaseName

. (Join-Path $PSScriptRootV2 'HelperFunctions.ps1')

# Read settings
$httpWebSiteDirectory = "C:\inetpub\wwwroot\http"
$CustomSettingsConfigFile = "c:\program files\Microsoft Dynamics NAV\$NavVersion\Service\CustomSettings.config"
$config = [xml](Get-Content $CustomSettingsConfigFile)
$thumbprint = $config.SelectSingleNode("//appSettings/add[@key='ServicesCertificateThumbprint']").value
$multitenant = ($config.SelectSingleNode("//appSettings/add[@key='Multitenant']").value -ne "false")
$serverInstance = $config.SelectSingleNode("//appSettings/add[@key='ServerInstance']").value
$publicSoapBaseUrl = $config.SelectSingleNode("//appSettings/add[@key='PublicSOAPBaseUrl']").value
$DatabaseServer = $config.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").value

# Is it OK to apply this package at this time
if (!$thumbprint) {
    Throw-UserError -Text "You need to run the initialize Server script before applying demo packages."
}

if ($DatabaseServer -ne "localhost") {
    Throw-UserError -Text "You can only run the Use Azure SQL script if the NAV Server is setup for using SQL Express."
}

# Install Microsoft Azure PowerShell
Install-MicrosoftAzurePowerShell

# Import modules
Import-module "C:\Program Files\Microsoft Dynamics NAV\$NavVersion\Service\NavAdminTool.ps1"

$AzureStorageAccountCreated = $false
$PublicSoapBaseUri = New-Object Uri -ArgumentList $publicSoapBaseUrl
$ServiceHostName = $PublicSoapBaseUri.Host
$AzureSqlServerLocation = GetDefaultAzureLocation -Hostname $ServiceHostName

$ExistingAzureSqlDatabase = Get-UserInput -Id ExistingAzureSqlDatabase -Text "Do you want to connect this Server to an existing Azure SQL App Database? (Yes/No)" -Default "No"
if ($ExistingAzureSqlDatabase -ne "Yes") {

    # Install DACFX (Microsoft SQL Server Data-Tier Application Framework)
    Install-DACFx
    
    # Install NET HTTP Activation
    Install-WindowsFeature -Name NET-HTTP-Activation

    SetAzureSubscription
   
    Write-Verbose "Get Azure SQL Database Info"
    $DatabaseServer   = Get-UserInput -Id DatabaseServer   -Text "Azure SQL Database Server Name (e.g. ivwu2x2qad) (leave empty to create new Azure SQL Server)"
    if ($DatabaseServer -eq "" -or $DatabaseServer -eq "Default") {

        if ([Environment]::UserName -ne "SYSTEM") {
            Write-Host "Available Locations:"
            Get-AzureLocation | % {
                if ($_.Name -eq $AzureSqlServerLocation) { $color = "Green" } else { $color = "Yellow" }
                Write-Host -ForegroundColor $color $_.Name
            }
        }
        $AzureSqlServerLocation = Get-UserInput -Id AzureSqlServerLocation -Text "Location of the Azure SQL Server (must be the same location as your Virtual Machine)" -Default $AzureSqlServerLocation
        
        $DatabaseUserName = Get-UserInput -Id DatabaseUserName -Text "New Azure SQL Database Server Username" -Default "sqladmin"
        $DatabasePassword = Get-Variable -name "HardcodeDatabasePassword" -ValueOnly -ErrorAction SilentlyContinue
        if ($DatabasePassword) {
            $DatabaseSecurePassword = ConvertTo-SecureString -String $DatabasePassword -AsPlainText -Force
        } else {
            $DatabaseSecurePassword = Read-Host "New Azure SQL Database Server Password" -AsSecureString
        }
        $DatabasePassword = Decrypt-SecureString $DatabaseSecurePassword
        $DatabaseCredentials = New-Object PSCredential -ArgumentList $DatabaseUserName, $DatabaseSecurePassword

        $AzureSqlServer = New-AzureSqlDatabaseServer -Location $AzureSqlServerLocation -AdministratorLogin $DatabaseUserName -AdministratorLoginPassword $DatabasePassword -Version 12.0
        $DatabaseServer = $AzureSqlServer.ServerName
        New-AzureSqlDatabaseServerFirewallRule -ServerName $DatabaseServer -RuleName "Azure Services" -StartIPAddress "0.0.0.0" -EndIPAddress "0.0.0.0"

    } else {
        $DatabaseUserName = Get-UserInput -Id DatabaseUserName -Text "Azure SQL Database Server Username" -Default "sqladmin"
        $DatabasePassword = Get-Variable -name "HardcodeDatabasePassword" -ValueOnly -ErrorAction SilentlyContinue
        if ($DatabasePassword) {
            $DatabaseSecurePassword = ConvertTo-SecureString -String $DatabasePassword -AsPlainText -Force
        } else {
            $DatabaseSecurePassword = Read-Host "Azure SQL Database Server Password" -AsSecureString
        }
        $DatabasePassword = Decrypt-SecureString $DatabaseSecurePassword
        $DatabaseCredentials = New-Object PSCredential -ArgumentList $DatabaseUserName, $DatabaseSecurePassword
    }
    $DatabaseServerContext = New-AzureSqlDatabaseServerContext -Credential $DatabaseCredentials -ServerName $DatabaseServer

    $storageAccountName = Get-UserInput -Id StorageAccountName -Text "Storage Account Name (leave empty to create new temporary storage account)"
    if ($storageAccountName -eq "" -or $storageAccountName -eq "Default") {

        if ([Environment]::UserName -ne "SYSTEM") {
            Write-Host "Available Locations:"
            Get-AzureLocation | % {
                if ($_.Name -eq $AzureSqlServerLocation) { $color = "Green" } else { $color = "Yellow" }
                Write-Host -ForegroundColor $color $_.Name
            }
        }
        $StorageAccountLocation = Get-UserInput -Id StorageAccountLocation -Text "Location of the new Storage Account (must be the same location as your Azure SQL Server)" -Default $AzureSqlServerLocation
        $storageAccountName = ([Regex]::Replace($ServiceHostName.ToLower(), '[^(a-z0-9)]', ''))
        $storageAccountName = $storageAccountName.SubString(0,[Math]::Min($storageAccountName.Length,24))
        $storageAccount = Get-AzureStorageAccount -StorageAccountName $storageAccountName -ErrorAction Ignore
        if (!($storageAccount)) {
            $storageAccount = New-AzureStorageAccount -StorageAccountName $storageAccountName -Location $StorageAccountLocation -Type "Standard_LRS"
            $AzureStorageAccountCreated = $true
        }
        $storageAccountKey = (Get-AzureStorageKey -StorageAccountName $storageAccountName).Primary
        $containerName = "bacpac"
    } else {
        $storageAccountKey  = Get-UserInput -Id StorageAccountKey  -Text "Storage Account Key"
        $containerName      = Get-UserInput -Id ContainerName      -Text "Container Name" -Default "bacpac"
    }

    $StorageContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
    try
    {
        $newcontainer = New-AzureStorageContainer -Context $StorageContext -Container $ContainerName
        Write-Verbose('Storage Container created')
    }
    catch
    {
        Write-Verbose('Storage Container already exists')
    }

    $DatabaseNames = @()
    if ($multitenant) {
        # Tenant Template Database
        $DatabaseNames += "Tenant Template"

        # All Tenant Databases
        Get-NAVTenant -ServerInstance $serverInstance | % {
            $DatabaseNames += $_.DatabaseName
        }
    }
    #App Database / Single Tenant Database
    $DatabaseNames += $DatabaseName

    $ImportRequests = @()
    $SqlServerInstance = "localhost\NAVDEMO"
    $DatabaseNames | % {
        $DatabaseName = $_
        $TempDatabaseName = "Temp $DatabaseName"
        $bacpacFileName = (Join-Path $PSScriptRootV2 "$DatabaseName.bacpac")
        
        # Make a Copy of the database
        Write-Verbose "Copying NAV Database to Temp Database"
        Copy-NavDatabase -SourceDatabaseName $DatabaseName -DestinationDatabaseName $TempDatabaseName
        
        # Remove unwanted "stuff"
        Write-Verbose "Removing ""stuff"" which is incompatible with Azure SQL"
        Remove-NavDatabaseSystemTableData -DatabaseName $TempDatabaseName
        Remove-NavTenantDatabaseUserData -DatabaseName $TempDatabaseName -RemoveUserData $false
        
        # Create .bacpac
        Write-Verbose "Create $bacpacFileName"
        $arguments = @(
        "/action:Export", 
        "/tf:""$bacpacFileName""", 
        "/SourceConnectionString:""Data Source=$SqlServerInstance;Initial Catalog=$TempDatabaseName;Integrated Security=SSPI;Persist Security Info=False;"""
        )
        Start-Process -FilePath "C:\Program Files\Microsoft SQL Server\120\DAC\bin\sqlpackage.exe" -ArgumentList $arguments -NoNewWindow -Wait

        # Remove database copy
        Write-Verbose "Remove Temp Database"
        Remove-NavDatabase -DatabaseName $TempDatabaseName -Force

        Write-Verbose "Restore $DatabaseName.bacpac to Azure SQL Database"
   
        $DatabaseEdition = "Standard"
        $PerformanceLevel = "S0"
        $DatabaseMaxSize = 100
        $BlobName = "db.bacpac"

        Set-AzureStorageBlobContent -File $bacpacFileName -Container $ContainerName -Context $StorageContext -Blob $BlobName -Force

        Write-Verbose "Extracting information about DB Collation from $bacpacFileName"
        $Collation = ExtractCollationInformationFromNAVBacpac -bacpacFileName $bacpacFileName
        Write-Verbose "Extracting information about DB Collation from bacpac file completed. Detected DB collation: '$Collation'."

        $serviceObjective = Get-AzureSqlDatabaseServiceObjective -Context $DatabaseServerContext -ServiceObjectiveName $PerformanceLevel
        $database = Get-AzureSqlDatabase -ConnectionContext $DatabaseServerContext -DatabaseName $DatabaseName -ErrorAction Ignore
        if($database)
        {
            throw "Database '$DatabaseName' already exists on server '$DatabaseServer'!"
        }

        $collationSetting = @{}
        if($Collation)
        {
            $collationSetting.Add('Collation',$Collation)
        }

        New-AzureSqlDatabase -ConnectionContext $DatabaseServerContext `
            -Edition $DatabaseEdition -DatabaseName $DatabaseName `
            -MaxSizeGB $DatabaseMaxSize `
            -ServiceObjective $serviceObjective @collationSetting
          
        $container = Get-AzureStorageContainer -Context $StorageContext -Name $containerName
        # Start import
        Write-Verbose "Starting import for $DatabaseName"
        $importRequest = Start-AzureSqlDatabaseImport -DatabaseName $DatabaseName `
                                         -SqlConnectionContext $DatabaseServerContext `
                                         -StorageContainer $Container `
                                         -BlobName $BlobName `
                                         -Edition $DatabaseEdition `
                                         -DatabaseMaxSize $DatabaseMaxSize
        Write-Verbose "Done starting import for $DatabaseName"
        $ImportRequests += $importRequest
    }

    Write-Verbose "Waiting for import to finish..."
    $AllDone = $true
    do {
        Start-Sleep -Seconds 30
        $AllDone = $true
        0..($ImportRequests.Length-1) | % {
            $DatabaseName = $DatabaseNames[$_]
            $RequestId = $importRequests[$_].RequestGuid
            # Wait for completion
            $status = Get-AzureSqlDatabaseImportExportStatus -ServerName $DatabaseServer `
                                                             -Username   $DatabaseUserName `
                                                             -Password   $DatabasePassword `
                                                             -RequestId  $RequestId
            Write-Verbose ("Import $DatabaseName "+$Status.Status)
            if ($status.Status.StartsWith("Running") -or $status.Status.StartsWith("Pending")) {
                $AllDone = $false
            }
        }
    } until ($AllDone)
    Write-Verbose "Done waiting for import to finish."

} else {

    Write-Verbose "Get Azure SQL Database Info"
    $DatabaseServer   = Get-UserInput -Id DatabaseServer   -Text "Azure SQL Database Server Name (e.g. ivwu2x2qad)"
    $DatabaseUserName = Get-UserInput -Id DatabaseUserName -Text "Azure SQL Database Server Username" -Default "sqladmin"
    $DatabasePassword = Get-Variable -name "HardcodeDatabasePassword" -ValueOnly -ErrorAction SilentlyContinue
    if ($DatabasePassword) {
        $DatabaseSecurePassword = ConvertTo-SecureString -String $DatabasePassword -AsPlainText -Force
    } else {
        $DatabaseSecurePassword = Read-Host "Azure SQL Database Server Password" -AsSecureString
    }
    $DatabasePassword = Decrypt-SecureString $DatabaseSecurePassword
    $DatabaseName     = Get-UserInput -Id DatabaseName     -Text "Azure SQL Database Name" -Default $DatabaseName
    $DatabaseCredentials = New-Object PSCredential -ArgumentList $DatabaseUserName, $DatabaseSecurePassword
    $DatabaseServerContext = New-AzureSqlDatabaseServerContext -Credential $DatabaseCredentials -FullyQualifiedServerName "$DatabaseServer.database.windows.net"

    $DatabaseServerFull = "$DatabaseServer.database.windows.net"
    # If the database doesn't have a USER table, we assume that it is multi tenant
    $multitenant = (Invoke-Sqlcmd -ServerInstance $DatabaseServerFull -Username $DatabaseUserName -Password $DatabasePassword -Database $DatabaseName -Query "SELECT 1 FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' AND TABLE_NAME='USER'") -eq $null

    New-Item -Path  "$httpWebSiteDirectory\tenants.txt" -ItemType File
}

Write-Verbose "Configure NAV to use Azure SQL Database [$DatabaseServer][$DatabaseName]"
$EncryptionPassword = Get-RandomPassword
$EncryptionPassword = "$EncryptionPassword!$EncryptionPassword"
$EncryptionSecurePassword = ConvertTo-SecureString -String $EncryptionPassword -AsPlainText -Force
$EncryptionKeyPath = (Join-Path $PSScriptRootV2 'DynamicsNAV.key')

# Use existing Encryption key for demo environments
if (!(Test-Path $EncryptionKeyPath)) {
    New-NAVEncryptionKey -KeyPath $EncryptionKeyPath -Password $EncryptionSecurePassword -Force
}
$DatabaseServerFull = "$DatabaseServer.database.windows.net"
Import-NAVEncryptionKey -ServerInstance $serverInstance `
                        -ApplicationDatabaseServer $DatabaseServerFull `
                        -ApplicationDatabaseCredentials $DatabaseCredentials `
                        -ApplicationDatabaseName $DatabaseName `
                        -KeyPath $EncryptionKeyPath `
                        -Password $EncryptionSecurePassword `
                        -Force -Verbose

Set-NAVServerInstance      -ServerInstance $serverInstance -Stop
Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName EnableSqlConnectionEncryption -KeyValue "true"
Set-NAVServerConfiguration -ServerInstance $serverInstance -DatabaseCredentials $DatabaseCredentials -Force
Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName DatabaseServer -KeyValue $DatabaseServerFull -Force
Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName DatabaseInstance -KeyValue "" -Force
Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName DatabaseName -KeyValue $DatabaseName
Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName Multitenant -KeyValue $Multitenant.ToString().ToLower()
Set-NAVServerInstance      -ServerInstance $serverInstance -Start

$URLsFile = "C:\Users\Public\Desktop\URLs.txt"("SQL Encryption Password       : $EncryptionPassword") | Add-Content -Path $URLsFile

if ([Environment]::UserName -ne "SYSTEM") {
    Get-Content $URLsFile | Write-Host -ForegroundColor Yellow
}

if ($multitenant) {
    "`$DatabaseServerParams = @{
    'ServerInstance' = '$DatabaseServerFull'
    'UserName' = '$DatabaseUserName'
    'Password' = '$DatabasePassword'
    'QueryTimeout' = 0
    'ea' = 'stop'
    }" | Add-Content 'C:\DEMO\Multitenancy\HardcodeInput.ps1'
}

$licenseinfo = Export-NAVServerLicenseInformation -ServerInstance $ServerInstance -ErrorAction Ignore
if (!($licenseinfo)) {
    # Import license file if new database
    $License = (Join-Path $DVDFolder "SQLDemoDatabase\CommonAppData\Microsoft\Microsoft Dynamics NAV\$NavVersion\Database\Cronus.flf")
    Import-NAVServerLicense    -ServerInstance $serverInstance -LicenseFile $License -Database NavDatabase -Force

    . "C:\DEMO\Multitenancy\install.ps1" 4> "C:\DEMO\Multitenancy\install.log"
}

if ($ExistingAzureSqlDatabase -ne "Yes") {

    if ($multitenant) {
        1..($DatabaseNames.Length-2) | % {
            $DatabaseName = $DatabaseNames[$_]
            $TenantId = $DatabaseName
            Mount-NAVTenant -ServerInstance $serverInstance -DatabaseServer $DatabaseServerFull -DatabaseName $DatabaseName -Id $TenantId -DatabaseCredentials $DatabaseCredentials -Force
        }
    }
}

if ($AzureStorageAccountCreated) {
    Remove-AzureStorageAccount -storageAccountName $StorageAccountName
}
