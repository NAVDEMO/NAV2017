#usage initialize.ps1

param
(
       [string]$PatchPath = ""
      ,[string]$VMAdminUsername = ""
      ,[string]$NAVAdminUsername = ""
      ,[string]$AdminPassword  = ""
      ,[string]$Country = ""
      ,[string]$RestoreAndUseBakFile = "Default"
      ,[string]$CloudServiceName = ""
      ,[string]$LicenseFileUrl = ""
      ,[string]$CertificatePfxUrl = ""
      ,[string]$CertificatePfxPassword = "" 
      ,[string]$PublicMachineName = ""
      ,[string]$bingMapsKey = ""
      ,[string]$clickonce = ""
      ,[string]$powerBI = ""
      ,[string]$Office365UserName = ""
      ,[string]$Office365Password = ""
      ,[string]$Office365CreatePortal = ""
      ,[string]$Multitenancy = ""
      ,[string]$AzureSQL = ""
)

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force
Start-Transcript -Path "C:\DEMO\initialize.txt"

# Wait until NAV Service Tier is Running
#. ("c:\program files\Microsoft Dynamics NAV\100\Service\NavAdminTool.ps1")
#while ((Get-NAVServerInstance -ServerInstance NAV).State -ne "Running") { Start-Sleep -Seconds 5 }

function DownloadFile([string]$sourceUrl, [string]$destinationFile)
{
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    Invoke-WebRequest $sourceUrl -OutFile $destinationFile
}

function PatchFileIfNecessary([string]$baseUrl, [string]$path, $date)
{
    $destinationFile = ("C:\"+$path.Replace("/","\"))
    $sourceUrl = "${baseUrl}$path"
    if (Test-Path -path $destinationFile) {
        if ((get-item $destinationFile).LastAccessTimeUtc.Date.CompareTo($date) -ne -1) { 
            # File is newer - don't patch
            return
        } 
        Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    }
    Invoke-WebRequest $sourceUrl -OutFile $destinationFile
}

# Other variables
$MachineName = [Environment]::MachineName.ToLowerInvariant()
new-item -Path "c:\DEMO\Install" -ItemType Directory -Force -ErrorAction Ignore

# Update RTM files
$date = (Get-Date -Date "2016-11-01 00:00:00Z").ToUniversalTime()
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "DEMO/Initialize/install.ps1"        
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "DEMO/O365 Integration/install.ps1"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "DEMO/O365 Integration/HelperFunctions.ps1"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "DEMO/O365 Integration/O365 Integration.navx"
PatchFileIfNecessary -date $date -baseUrl $PatchPath -path "DEMO/O365 Integration/Deltas/COD51401.DELTA"

# Download files for Task Registration
DownloadFile -SourceUrl "${PatchPath}InstallationTask.xml" -destinationFile "c:\DEMO\Install\InstallationTask.xml"
DownloadFile -SourceUrl "${PatchPath}StartInstallationTask.xml" -destinationFile "c:\DEMO\Install\StartInstallationTask.xml"
DownloadFile -SourceUrl "${PatchPath}InstallAzurePowerShell.cmd" -destinationFile "c:\DEMO\Install\InstallAzurePowerShell.cmd"

$licenseFile = ""
if ($licenseFileUrl -ne "")
{
    $licenseFile = "C:\DEMO\license.flf"
    if ($licenseFileUrl.StartsWith("http://") -or $licenseFileUrl.StartsWith("https://")) {
        Write-Verbose "Downloading $licenseFileUrl to $licenseFile"
        DownloadFile -SourceUrl $LicenseFileUrl -destinationFile $licenseFile
    } else {
        # Assume Base64
        [System.IO.File]::WriteAllBytes($licenseFile, [System.Convert]::FromBase64String($licenseFileUrl))
    }
}

if ($CertificatePfxUrl -eq "")
{
    $PublicMachineName = $CloudServiceName
    $CertificatePfxFile = "default"
} else {
    $CertificatePfxFile = "C:\DEMO\certificate.pfx"
    if ($certificatePfxUrl.StartsWith("http://") -or $certificatePfxUrl.StartsWith("https://")) {
        Write-Verbose "Downloading $certificatePfxUrl to $CertificatePfxFile"
        DownloadFile -SourceUrl $certificatePfxUrl -destinationFile $CertificatePfxFile
    } else {
        # Assume Base64
        [System.IO.File]::WriteAllBytes($CertificatePfxFile, [System.Convert]::FromBase64String($CertificatePfxUrl))
    }
}

$step = 1
$next = $step+1
('Unregister-ScheduledTask -TaskName "Start Installation Task" -Confirm:$false')                 | Add-Content "c:\DEMO\Install\step$step.ps1"
('(''. "c:\DEMO\Install\Step'+$next+'.ps1"'') | Out-File "C:\DEMO\Install\Next-Step.ps1"')       | Add-Content "c:\DEMO\Install\step$step.ps1"
('Register-ScheduledTask -Xml (get-content "c:\DEMO\Install\InstallationTask.xml" | out-string) -TaskName "Installation Task" -User "'+$VMAdminUserName+'" -Password "'+$AdminPassword+'" –Force') | Add-Content "c:\DEMO\Install\step$step.ps1"
('Restart-Computer -Force')                                                                      | Add-Content "c:\DEMO\Install\step$step.ps1"

if ($NAVAdminUsername -ne "") {
    # Initialize Virtual Machine
    $step = $next
    $next++
    ('. ("c:\program files\Microsoft Dynamics NAV\100\Service\NavAdminTool.ps1")')                         | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('while ((Get-NAVServerInstance -ServerInstance NAV).State -ne "Running") { Start-Sleep -Seconds 5 }') | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('try {')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeLanguage = "'+$Country.Substring(0,2)+'"')                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeNavAdminUser = "'+$NAVAdminUsername+'"')                                                    | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeNavAdminPassword = "'+$AdminPassword+'"')                                                   | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeRestoreAndUseBakFile = "'+$RestoreAndUseBakFile+'"')                                        | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeCloudServiceName = "'+$CloudServiceName+'"')                                                | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodePublicMachineName = "'+$PublicMachineName+'"')                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodecertificatePfxFile = "'+$CertificatePfxFile+'"')                                            | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodecertificatePfxPassword = "'+$CertificatePfxPassword+'"')                                    | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('. "c:\DEMO\Initialize\install.ps1" 4> "C:\DEMO\Initialize\install.log"')                             | Add-Content "c:\DEMO\Install\step$step.ps1"
    ("Set-Content -Path ""c:\inetpub\wwwroot\http\$MachineName.rdp"" -Value 'full address:s:${PublicMachineName}:3389
prompt for credentials:i:1'")                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('(''. "c:\DEMO\Install\Step'+$next+'.ps1"'') | Out-File "C:\DEMO\Install\Next-Step.ps1"')             | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Start-Process -FilePath "c:\DEMO\Install\InstallAzurePowerShell.cmd" -Wait -Passthru')               | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('} catch {')                                                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Set-Content -Path "c:\DEMO\initialize\error.txt" -Value $_.Exception.Message')                       | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('}')                                                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
    $step = $next
    $next++
}

if ($Office365UserName -ne "") {
    ('. ("c:\program files\Microsoft Dynamics NAV\100\Service\NavAdminTool.ps1")')                         | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('while ((Get-NAVServerInstance -ServerInstance NAV).State -ne "Running") { Start-Sleep -Seconds 5 }') | Add-Content "c:\DEMO\Install\step$step.ps1"
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
    ('. "c:\DEMO\O365 Integration\install.ps1" 4> "C:\DEMO\O365 Integration\install.log"')                 | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('} catch {')                                                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Set-Content -Path "c:\DEMO\O365 Integration\error.txt" -Value $_.Exception.Message')                 | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('throw')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('}')                                                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
}

if ($bingMapsKey -ne "") {
    # Install BingMaps Integration
    ('try {')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeBingMapsKey = "'+$bingMapsKey+'"')                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('$HardcodeRegionFormat = "default"')                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('. "c:\DEMO\BingMaps\install.ps1" 4> "C:\DEMO\BingMaps\install.log"')                                 | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('} catch {')                                                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Set-Content -Path "c:\DEMO\BingMaps\error.txt" -Value $_.Exception.Message')                         | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('throw')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('}')                                                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
}

if ($powerBI -eq "Yes") {
    # Install PowerBI
    ('try {')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('. "c:\DEMO\PowerBI\install.ps1" 4> "C:\DEMO\PowerBI\install.log"')                                   | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('} catch {')                                                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Set-Content -Path "c:\DEMO\PowerBI\error.txt" -Value $_.Exception.Message')                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('throw')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('}')                                                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
}

if ($clickonce -eq "Yes") {
    # Install ClickOnce
    ('try {')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('. "c:\DEMO\Clickonce\install.ps1" 4> "C:\DEMO\Clickonce\install.log"')                               | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('} catch {')                                                                                          | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('Set-Content -Path "c:\DEMO\Clickonce\error.txt" -Value $_.Exception.Message')                        | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('throw')                                                                                              | Add-Content "c:\DEMO\Install\step$step.ps1"
    ('}')                                                                                                  | Add-Content "c:\DEMO\Install\step$step.ps1"
}

if ($licenseFile -ne "") {
    # Install Extention Development Shell
    
}

if ($Multitenancy -eq "Yes") {
    # Setup Multitenancy

}

if ($AzureSQL -eq "Yes") {
    # Setup Azure SQL

}

('Unregister-ScheduledTask -TaskName "Installation Task" -Confirm:$false')                                 | Add-Content "c:\DEMO\Install\step$step.ps1"
('Remove-Item "c:\DEMO\Install" -Force -Recurse -ErrorAction Ignore')                                      | Add-Content "c:\DEMO\Install\step$step.ps1"
('Remove-Item "c:\DEMO\Initialize.txt" -Force -ErrorAction Ignore')                                        | Add-Content "c:\DEMO\Install\step$step.ps1"

Register-ScheduledTask -Xml (get-content "c:\DEMO\Install\StartInstallationTask.xml" | out-string) -TaskName "Start Installation Task" -User "NT AUTHORITY\SYSTEM" –Force
Restart-Computer -Force
