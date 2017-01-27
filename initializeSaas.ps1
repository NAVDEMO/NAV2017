#usage initialize.ps1

param
(
       [string]$ScriptPath = ""
      ,[string]$StorageAccountName = ""
      ,[string]$StorageAccountKey = ""
      ,[string]$VMAdminUsername = ""
      ,[string]$NAVAdminUsername = ""
      ,[string]$AdminPassword  = ""
      ,[string]$NavDvdUri = ""
      ,[string]$Country = "US"
      ,[string]$RestoreAndUseBakFile = "Default"
      ,[string]$CloudServiceName = ""
      ,[string]$LicenseFileUri = ""
      ,[string]$CertificatePfxUri = ""
      ,[string]$CertificatePfxPassword = "" 
      ,[string]$PublicMachineName = ""
      ,[string]$bingMapsKey = ""
      ,[string]$clickonce = "No"
      ,[string]$powerBI = "No"
      ,[string]$Office365UserName = ""
      ,[string]$Office365Password = ""
      ,[string]$Office365CreatePortal = "No"
      ,[string]$Multitenancy = ""
      ,[string]$sqlAdminUsername = ""
      ,[string]$sqlServerName = ""
	  ,[int]$noOfTestTenants = 1
)

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force
Start-Transcript -Path "C:\DEMO\initialize.txt"
([DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " Starting VM Initialization") | Add-Content -Path "c:\demo\status.txt"

function Log([string]$line) { ('<font color="Gray">' + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" }

function DownloadFile([string]$sourceUrl, [string]$destinationFile)
{
    Log("Downloading '$sourceUrl' to '$destinationFile'")
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    Invoke-WebRequest $sourceUrl -OutFile $destinationFile
}

function PatchFileIfNecessary([string]$baseUrl, [string]$path, $date)
{
    $destinationFile = ("C:\"+$path.Replace("SAAS/","DEMO/").Replace("/","\"))
    $sourceUrl = "${baseUrl}$path"
    if (Test-Path -path $destinationFile) {
        if ((get-item $destinationFile).LastAccessTimeUtc.Date.CompareTo($date) -ne -1) { 
            # File is newer - don't patch
            Log("Do not patch '$destinationFile' with '$sourceUrl'")
            return
        } 
        Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    }
    Log("Patching '$destinationFile' with '$sourceUrl'")
    Invoke-WebRequest $sourceUrl -OutFile $destinationFile
}

# Other variables
$MachineName = [Environment]::MachineName.ToLowerInvariant()
new-item -Path "c:\DEMO\Install" -ItemType Directory -Force -ErrorAction Ignore
Log("Machine Name is $MachineName")

# Update CU2 files
$date = (Get-Date -Date "2017-01-11 00:00:00Z").ToUniversalTime()
$PatchPath = $ScriptPath.SubString(0,$ScriptPath.LastIndexOf('/')+1)
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "SAAS/AzureSQL/install.ps1"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "SAAS/Multitenancy/HelperFunctions.ps1"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "SAAS/Multitenancy/MTDemoAdminShell.psm1"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "SAAS/Common/HelperFunctions.ps1"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "SAAS/O365 Integration/US Prereq.fob"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "SAAS/O365 Integration/install.ps1"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "SAAS/Initialize/Default.aspx"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "SAAS/Initialize/install.ps1"

# Set $isSaaS to true
$file = "C:\DEMO\Common\HelperFunctions.ps1"
[System.IO.File]::WriteAllText($file, [System.IO.File]::ReadAllText($file).Replace('$isSaaS = $false','$isSaaS = $true'))

if ($VMAdminUsername -eq "") {
    Log("Restart computer and stop installation")
    Restart-Computer -Force
}

# Download files for Task Registration
DownloadFile -SourceUrl "${PatchPath}InstallationTask.xml"      -destinationFile "c:\DEMO\Install\InstallationTask.xml"
DownloadFile -SourceUrl "${PatchPath}StartInstallationTask.xml" -destinationFile "c:\DEMO\Install\StartInstallationTask.xml"

if ($CertificatePfxUri -eq "")
{
    $PublicMachineName = $CloudServiceName
    $CertificatePfxFile = "default"
} else {
    $CertificatePfxFile = "C:\DEMO\certificate.pfx"
    if ($certificatePfxUri.StartsWith("http://") -or $certificatePfxUri.StartsWith("https://")) {
        Write-Verbose "Downloading $certificatePfxUri to $CertificatePfxFile"
        DownloadFile -SourceUrl $certificatePfxUri -destinationFile $CertificatePfxFile
    } else {
        Log("Unpack base64 encoded Certificate Pfx File to $certificatePfxFile")
        # Assume Base64
        [System.IO.File]::WriteAllBytes($CertificatePfxFile, [System.Convert]::FromBase64String($CertificatePfxUri))
    }
}

if ($LicenseFileUri -ne "")
{
    $LicenseFile = "C:\DEMO\license.flf"
    if ($LicenseFileUri.StartsWith("http://") -or $LicenseFileUri.StartsWith("https://")) {
        Write-Verbose "Downloading $LicenseFileUri to $LicenseFile"
        DownloadFile -SourceUrl $LicenseFileUri -destinationFile $LicenseFile
    } else {
        Log("Unpack base64 encoded Certificate Pfx File to $LicenseFile")
        # Assume Base64
        [System.IO.File]::WriteAllBytes($LicenseFile, [System.Convert]::FromBase64String($LicenseFileUri))
    }
}

Log("Creating Installation Scripts")

$step = 1
$next = $step+1
('Unregister-ScheduledTask -TaskName "Start Installation Task" -Confirm:$false')                           | Add-Content "c:\DEMO\Install\step$step.ps1"
('(''. "c:\DEMO\Install\Step'+$next+'.ps1"'') | Out-File "C:\DEMO\Install\Next-Step.ps1"')                 | Add-Content "c:\DEMO\Install\step$step.ps1"
('Register-ScheduledTask -Xml (get-content "c:\DEMO\Install\InstallationTask.xml" | out-string) -TaskName "Installation Task" -User "'+$VMAdminUserName+'" -Password "'+$AdminPassword+'" –Force') | Add-Content "c:\DEMO\Install\step$step.ps1"
('Restart-Computer -Force')                                                                                | Add-Content "c:\DEMO\Install\step$step.ps1"
$step = $next
$next++
('function Log([string]$line) { ([DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line") | Add-Content -Path "c:\demo\status.txt" }') | Add-Content "c:\DEMO\Install\step$step.ps1"

if ($NAVAdminUsername -ne "") {
    # Initialize Virtual Machine
    ('try {')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeNavDvdUri = "'+$NavDvdUri+'"')                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeLanguage = "'+$Country.Substring(0,2)+'"')                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeNavAdminUser = "'+$NAVAdminUsername+'"')                                                    | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeNavAdminPassword = "'+$AdminPassword+'"')                                                   | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeRestoreAndUseBakFile = "'+$RestoreAndUseBakFile+'"')                                        | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeCloudServiceName = "'+$CloudServiceName+'"')                                                | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodePublicMachineName = "'+$PublicMachineName+'"')                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodecertificatePfxFile = "'+$CertificatePfxFile+'"')                                            | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodecertificatePfxPassword = "'+$CertificatePfxPassword+'"')                                    | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Log("Initializing Virtual Machine")')                                                                | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('. "c:\DEMO\Initialize\install.ps1" 4> "C:\DEMO\Initialize\install.log"')                             | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Log("Done initializing Virtual Machine")')                                                           | Add-Content "c:\DEMO\Install\step$step.ps1"
    ("Set-Content -Path ""c:\inetpub\wwwroot\http\$MachineName.rdp"" -Value 'full address:s:${PublicMachineName}:3389
prompt for credentials:i:1'")                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('} catch {')                                                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Set-Content -Path "c:\DEMO\initialize\error.txt" -Value $_.Exception.Message')                       | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Log("ERROR (Initialize): "+$_.Exception.Message+" ("+($Error[0].ScriptStackTrace -split "\r\n")[0]+")")')  | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('}')                                                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
}

if ($Office365UserName -ne "") {
    ('try {')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeNavAdminUser = "'+$NAVAdminUsername+'"')                                                    | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeSharePointAdminLoginname = "'+$Office365UserName+'"')                                       | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeSharePointAdminPassword = "'+$Office365Password+'"')                                        | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeCreateSharePointPortal = "'+$Office365CreatePortal+'"')                                     | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeSharePointUrl = "default"')                                                                 | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeSharePointSite = "' + ($PublicMachineName.Split('.')[0])+'"')                               | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeSharePointLanguage = "default"')                                                            | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeSharePointTimezoneId = "default"')                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeSharePointAppCatalogUrl = "default"')                                                       | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeSharePointMultitenant = "No"')                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Log("Installing O365 integration")')                                                                 | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('. "c:\DEMO\O365 Integration\install.ps1" 4> "C:\DEMO\O365 Integration\install.log"')                 | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Log("Done installing O365 integration")')                                                            | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('} catch {')                                                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Set-Content -Path "c:\DEMO\O365 Integration\error.txt" -Value $_.Exception.Message')                 | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Log("ERROR (O365): "+$_.Exception.Message+" ("+($Error[0].ScriptStackTrace -split "\r\n")[0]+")")')  | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('throw')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('}')                                                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
}

# Setup Azure SQL
('try {')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
('Log("Setting up Azure SQL and Multitenancy")')                                                       | Add-Content "c:\DEMO\Install\step$step.ps1"
('$HardcodeExistingAzureSqlDatabase = "Yes"')                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
('$HardcodeDatabaseServer = "'+$sqlServerName+'"')                                                     | Add-Content "c:\DEMO\Install\step$step.ps1"
('$HardcodeDatabaseUserName = "'+$sqlAdminUsername+'"')                                                | Add-Content "c:\DEMO\Install\step$step.ps1"
('$HardcodeDatabasePassword = "'+$adminPassword+'"')                                                   | Add-Content "c:\DEMO\Install\step$step.ps1"
('$HardcodeDatabaseName = "default"')                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
('. "c:\DEMO\AzureSQL\install.ps1" 4> "C:\DEMO\AzureSQL\install.log"')                                 | Add-Content "c:\DEMO\Install\step$step.ps1"
('Log("Done setting up Azure SQL and Multitenancy")')                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
if ($noOfTestTenants -gt 0) {
    ('Log("Adding '+$noOfTestTenants+' test tenants")')                                                | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('1..'+$noOfTestTenants+' | % {')                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('    Log("Add test tenant Tenant$_")')                                                            | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('    New-DemoTenant Tenant$_')                                                                    | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('}')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Log("Done adding '+$noOfTestTenants+' test tenants")')                                           | Add-Content "c:\DEMO\Install\step$step.ps1"
}
('} catch {')                                                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
('Set-Content -Path "c:\DEMO\AzureSQL\error.txt" -Value $_.Exception.Message')                         | Add-Content "c:\DEMO\Install\step$step.ps1"
('Log("ERROR (AzureSQL): "+$_.Exception.Message+" ("+($Error[0].ScriptStackTrace -split "\r\n")[0]+")")')  | Add-Content "c:\DEMO\Install\step$step.ps1"
('throw')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
('}')                                                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"

# Install License
# Install entitlements

('Log("Cleaning up")')                                                                                     | Add-Content "c:\DEMO\Install\step$step.ps1"
('Remove-Item "c:\DEMO\Install" -Force -Recurse -ErrorAction Ignore')                                      | Add-Content "c:\DEMO\Install\step$step.ps1"
('Remove-Item "c:\DEMO\Initialize.txt" -Force -ErrorAction Ignore')                                        | Add-Content "c:\DEMO\Install\step$step.ps1"
('Unregister-ScheduledTask -TaskName "Installation Task" -Confirm:$false -ErrorAction Ignore')             | Add-Content "c:\DEMO\Install\step$step.ps1"
('Log("Installation complete")')                                                                           | Add-Content "c:\DEMO\Install\step$step.ps1"
('Restart-Computer -Force')                                                                                | Add-Content "c:\DEMO\Install\step$step.ps1"

Log("Register installation task")
Register-ScheduledTask -Xml (get-content "c:\DEMO\Install\StartInstallationTask.xml" | out-string) -TaskName "Start Installation Task" -User "NT AUTHORITY\SYSTEM" –Force
Log("Restart computer and start Installation tasks")
Restart-Computer -Force
