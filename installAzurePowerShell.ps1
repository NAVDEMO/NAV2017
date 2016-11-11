Write-Verbose “Using WebPI to install Microsoft Azure PowerShell"
$tempPICmd = $env:programfiles + “\microsoft\web platform installer\webpicmd.exe”
$tempPIParameters = “/install /accepteula /Products:WindowsAzurePowerShellGet"
Start-Process -FilePath $tempPICmd -ArgumentList $tempPIParameters -Wait -Passthru
