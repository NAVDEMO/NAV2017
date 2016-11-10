#usage initialize.ps1

param
(
       [string]$VMAdminUsername = ""
      ,[string]$NAVAdminUsername = ""
      ,[string]$AdminPassword  = ""
      ,[string]$Country = ""
      ,[string]$RestoreAndUseBakFile = "Default"
      ,[string]$CloudServiceName = ""
      ,[string]$CertificatePfxUrl = ""
      ,[string]$CertificatePfxPassword = "" 
      ,[string]$PublicMachineName = ""
      ,[string]$bingMapsKey = ""
      ,[string]$clickonce = ""
      ,[string]$powerBI = ""
      ,[string]$Office365UserName = ""
      ,[string]$Office365Password = ""
      ,[string]$Office365CreatePortal = ""
)

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force
Start-Transcript -Path "C:\DEMO\initialize.txt"

# Wait until NAV Service Tier is Running
. ("c:\program files\Microsoft Dynamics NAV\100\Service\NavAdminTool.ps1")
while ((Get-NAVServerInstance -ServerInstance NAV).State -ne "Running") { Start-Sleep -Seconds 5 }

# Other variables
If ($CertificatePfxUrl -eq "")
{
    $PublicMachineName = $CloudServiceName
    $CertificatePfxFile = "default"
} else {
    if ($certificatePfxUrl.StartsWith("http://") -or $certificatePfxUrl.StartsWith("https://")) {
        $CertificatePfxFile = "C:\DEMO\certificate.pfx"
        Write-Verbose "Downloading $certificatePfxUrl to $CertificatePfxFile"
        Invoke-WebRequest $certificatePfxUrl -OutFile $CertificatePfxFile
    } else {
        Write-Verbose "Error downloading '$certificatePfxUrl'"
        throw "Error downloading '$certificatePfxUrl'"
    }
}

$MachineName = [Environment]::MachineName.ToLowerInvariant()
$failure = $false

try {
    # Initialize Virtual Machine
    ('$HardcodeLanguage = "'+$Country.Substring(0,2)+'"')               | Add-Content "c:\DEMO\Initialize\HardcodeInput.ps1"
    ('$HardcodeNavAdminUser = "'+$NAVAdminUsername+'"')                 | Add-Content "c:\DEMO\Initialize\HardcodeInput.ps1"
    ('$HardcodeNavAdminPassword = "'+$AdminPassword+'"')                | Add-Content "c:\DEMO\Initialize\HardcodeInput.ps1"
    ('$HardcodeRestoreAndUseBakFile = "'+$RestoreAndUseBakFile+'"')     | Add-Content "c:\DEMO\Initialize\HardcodeInput.ps1"
    ('$HardcodeCloudServiceName = "'+$CloudServiceName+'"')             | Add-Content "c:\DEMO\Initialize\HardcodeInput.ps1"
    ('$HardcodePublicMachineName = "'+$PublicMachineName+'"')           | Add-Content "c:\DEMO\Initialize\HardcodeInput.ps1"
    ('$HardcodecertificatePfxFile = "'+$CertificatePfxFile+'"')         | Add-Content "c:\DEMO\Initialize\HardcodeInput.ps1"
    ('$HardcodecertificatePfxPassword = "'+$CertificatePfxPassword+'"') | Add-Content "c:\DEMO\Initialize\HardcodeInput.ps1"
    . 'c:\DEMO\Initialize\install.ps1' 4> 'C:\DEMO\Initialize\install.log'
} catch {
    Set-Content -Path "c:\DEMO\initialize\error.txt" -Value $_.Exception.Message
    Write-Verbose $_.Exception.Message
    throw
}

Set-Content -Path "c:\inetpub\wwwroot\http\$MachineName.rdp" -Value ('full address:s:' + $PublicMachineName + ':3389
prompt for credentials:i:1')

if ($Office365UserName -ne "") {
    try {
        ('$HardcodeNavAdminUser = "'+$NAVAdminUsername+'"')                      | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        ('$HardcodeSharePointAdminLoginname = "'+$Office365UserName+'"')         | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        ('$HardcodeSharePointAdminPassword = "'+$Office365Password+'"')          | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        ('$HardcodeCreateSharePointPortal = "'+$Office365CreatePortal+'"')       | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        ('$HardcodeSharePointUrl = "default"')                                   | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        ('$HardcodeSharePointSite = "' + ($PublicMachineName.Split('.')[0])+'"') | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        ('$HardcodeSharePointLanguage = "default"')                              | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        ('$HardcodeSharePointTimezoneId = "default"')                            | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        ('$HardcodeSharePointAppCatalogUrl = "default"')                         | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        ('$HardcodeSharePointMultitenant = "No"')                                | Add-Content "c:\DEMO\O365 Integration\HardcodeInput.ps1"
        . 'c:\DEMO\O365 Integration\install.ps1' 4> 'C:\DEMO\O365 Integration\install.log'

        Sync-NavTenant -ServerInstance NAV -Tenant default -Force
        Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "PublicWebBaseUrl" -KeyValue $publicWebBaseUrl
        Set-NAVServerInstance -ServerInstance $serverInstance -Restart

    } catch {
        Set-Content -Path "c:\DEMO\O365 Integration\error.txt" -Value $_.Exception.Message
        Write-Verbose $_.Exception.Message
        $failure = $true
    }
}

if ($bingMapsKey -ne "") {
    try {
        ('$HardcodeBingMapsKey = "'+$bingMapsKey+'"') | Add-Content "c:\DEMO\BingMaps\HardcodeInput.ps1"
        ('$HardcodeRegionFormat = "default"')         | Add-Content "c:\DEMO\BingMaps\HardcodeInput.ps1"
        . 'c:\DEMO\BingMaps\install.ps1' 4> 'C:\DEMO\BingMaps\install.log'
    } catch {
        Set-Content -Path "c:\DEMO\BingMaps\error.txt" -Value $_.Exception.Message
        Write-Verbose $_.Exception.Message
        $failure = $true
    }
}

if ($powerBI -eq "Yes") {
    try {
        . 'c:\DEMO\PowerBI\install.ps1' 4> 'C:\DEMO\PowerBI\install.log'
    } catch {
        Set-Content -Path "c:\DEMO\PowerBI\error.txt" -Value $_.Exception.Message
        Write-Verbose $_.Exception.Message
        $failure = $true
    }
}

if ($clickonce -eq "Yes") {
    try {
        . 'c:\DEMO\Clickonce\install.ps1' 4> 'C:\DEMO\Clickonce\install.log'
    } catch {
        Set-Content -Path "c:\DEMO\Clickonce\error.txt" -Value $_.Exception.Message
        Write-Verbose $_.Exception.Message
        $failure = $true
    }
}

if ($failure) {
    throw "Error installing demo packages"
}
