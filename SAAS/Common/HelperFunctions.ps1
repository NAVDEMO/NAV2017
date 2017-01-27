function global:Write-Host() {}
function global:Write-Warning() {}

function Log {
    Param (
        [Parameter(ValueFromPipeline=$true)]
        [string]$line,
        [Parameter(Mandatory=$false)]
        [switch]$OnlyInfo,
        [Parameter(Mandatory=$false)]
        [ValidateSet("Info","Emphasis","Success","Warning","Error")]
        [string]$kind = "Info"
    )
    
    process {
        $timestamp = [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss"))
        switch ($kind) {
            "Success"  { $color = "Green"  }
            "Warning"  { $color = "Yellow" }
            "Error"    { $color = "Red"    }
            "Emphasis" { $color = "White"  }
            default    { $color = "Gray"   }
        }
        if ([Environment]::UserName -ne "SYSTEM") {
            Microsoft.PowerShell.Utility\Write-Host "$line" -ForegroundColor $color
        }
        if (!$OnlyInfo) {
            "<font color=""$color"">$timestamp $line</font>" | Add-Content -Path "c:\demo\status.txt"
        }
        if ($kind -eq "Error") {
            Start-Sleep -Seconds 30
        }
    }
}

function New-DesktopShortcut
{
	Param
	(
		[Parameter(Mandatory=$true)]
		[string]$Name,
		[Parameter(Mandatory=$true)]
		[string]$TargetPath,
		[Parameter(Mandatory=$false)]
		[string]$WorkingDirectory,
		[Parameter(Mandatory=$false)]
		[string]$IconLocation,
		[Parameter(Mandatory=$false)]
		[string]$Arguments
	)

    $filename = "C:\Users\Public\Desktop\$Name.lnk"
    if (!(Test-Path -Path $filename)) {
        $Shell =  New-object -comobject WScript.Shell
        $Shortcut = $Shell.CreateShortcut($filename)
        $Shortcut.TargetPath = $TargetPath
        if (!$WorkingDirectory) {
            $WorkingDirectory = Split-Path $TargetPath
        }
        $Shortcut.WorkingDirectory = $WorkingDirectory
        if ($Arguments) {
            $Shortcut.Arguments = $Arguments
        }
        if ($IconLocation) {
            $Shortcut.IconLocation = $IconLocation
        }
        $Shortcut.save()
    }
}

function Remove-DesktopShortcut
{
	Param
	(
		[Parameter(Mandatory=$true)]
		[string]$Name
        )

    $filename = "C:\Users\Public\Desktop\$Name.lnk"
    Remove-Item $filename -Force -ErrorAction Ignore
}

function Get-UserInput
{
	Param
	(
		[Parameter(Mandatory=$True)]
		[string]$Id,
		[Parameter(Mandatory=$True)]
		[string]$Text,
		[Parameter(Mandatory=$false)]
		[string]$Default
	)
    
    if ($Default) {
        $Text = ($Text + " (Default " + $Default + ")")
    }
    $reply = Get-Variable -name "Hardcode$Id" -ValueOnly -ErrorAction SilentlyContinue
    if ($reply) {
        if ($reply -eq 'default') {
            $Default
        } else {
            $reply
        }
        Log "$Text : $reply"
    } else {
        $reply = Read-Host $Text
        if (!$reply) {
            $Default
        } else {
            $reply
        }
    }
}

function Get-SecureUserInput
{
	Param
	(
		[Parameter(Mandatory=$True)]
		[string]$Id,
		[Parameter(Mandatory=$True)]
		[string]$Text
	)

    $reply =Get-Variable -name "Hardcode$Id" -ValueOnly -ErrorAction SilentlyContinue
    if ($reply) {
        Log "$Text : Specified"
    } else {
        $securestring = Read-Host $Text -AsSecureString
        $reply = Decrypt-SecureString $securestring
    }
    $reply
}

function Get-RandomChar([string]$str)
{
    $rnd = Get-Random -Maximum $str.length
    [string]$str[$rnd]
}

function Get-RandomPassword {
    $cons = 'bcdfghjklmnpqrstvwxz'
    $voc = 'aeiouy'
    $numbers = '0123456789'

    ((Get-RandomChar $cons).ToUpper() + `
     (Get-RandomChar $voc) + `
     (Get-RandomChar $cons) + `
     (Get-RandomChar $voc) + `
     (Get-RandomChar $numbers) + `
     (Get-RandomChar $numbers) + `
     (Get-RandomChar $numbers) + `
     (Get-RandomChar $numbers))
}

function Decrypt-SecureString {
    param(
        [Parameter(Mandatory=$true)]
        [System.Security.SecureString]
        $sstr
    )

    $marshal = [System.Runtime.InteropServices.Marshal]
    $ptr = $marshal::SecureStringToBSTR( $sstr )
    $str = $marshal::PtrToStringBSTR( $ptr )
    $marshal::ZeroFreeBSTR( $ptr )
    $str
} 

function UnzipFolder($file, $destination)
{
    $shell = new-object -com shell.application
    $zip = $shell.NameSpace($file)
    foreach($item in $zip.items())
    {
        $shell.Namespace($destination).copyhere($item)
    }
}

function TranslateText {

    Param (
        [string]$apiKey,
        [string]$from,
        [string]$to,
        [string]$text
    )

    $AuthHeaders = @{"Content-Type"="application/json"; "Accept"="application/jwt"; "Ocp-Apim-Subscription-Key"="$apiKey"}
    $AuthResult = Invoke-WebRequest -Uri "https://api.cognitive.microsoft.com/sts/v1.0/issueToken" -Headers $AuthHeaders -Method POST
    if ($AuthResult.StatusCode -eq 200) {
        $AccessToken = [System.Text.Encoding]::ASCII.GetString($AuthResult.Content)
        $Headers = @{"Accept"="application/xml"}
        $encodedText = [Uri]::EscapeDataString($text)
        $Result = Invoke-WebRequest -Uri "https://api.microsofttranslator.com/v2/http.svc/Translate?appid=Bearer ${AccessToken}&from=$from&to=$to&text=$encodedText"
        if ($Result.StatusCode -eq 200) {
            $xml = [xml]$Result.Content
            $xml.string.InnerText
        }
    }
}

$isSaaS = $false
