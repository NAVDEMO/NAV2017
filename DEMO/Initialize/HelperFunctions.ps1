function New-SSLWebBinding
{
	Param
	(
		[Parameter(Mandatory=$True)]
		[string]$Name,
		[Parameter(Mandatory=$true)]
		[string]$Thumbprint,
		[Parameter(Mandatory=$false)]
		[string]$IP = '*',
		[Parameter(Mandatory=$false)]
		[int]$Port = '443'

	)
	# Create a new binding to a site
	New-WebBinding -Name $Name -Port $Port -Protocol https -IPAddress $IP
	Write-Verbose "Binding created for $Name"

	# Change location
	$location = Get-Location
	Set-Location -Path IIS:\SslBindings

    # Remove binding
    Get-Item "$IP!$Port" | Remove-Item

	# Bind certificate to site
	Get-Item Cert:\LocalMachine\my\$Thumbprint | New-Item $IP!$Port

	# Change location to former location
	Set-Location -Path IIS:\
	Set-Location -Path $location
	Write-Verbose "Certificate added to binding"
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
        Write-Host "$Text : $reply"
    } else {
        $reply = Read-Host $Text
        if (!$reply) {
            $Default
        } else {
            $reply
        }
    }
}


function Get-MyIp
{
    $url = "http://checkip.dyndns.com" 
    $WebClient = New-Object System.Net.WebClient
    $xml = [xml]($WebClient.DownloadString($url).ToString())
    $ip = $xml.html.body.Split(":")[1].Trim()
    $ip
}

function randomchar([string]$str)
{
    $rnd = Get-Random -Maximum $str.length
    [string]$str[$rnd]
}

function Get-RandomPassword {
    $cons = 'bcdfghjklmnpqrstvwxz'
    $voc = 'aeiouy'
    $numbers = '0123456789'

    ((randomchar $cons).ToUpper() + `
     (randomchar $voc) + `
     (randomchar $cons) + `
     (randomchar $voc) + `
     (randomchar $numbers) + `
     (randomchar $numbers) + `
     (randomchar $numbers) + `
     (randomchar $numbers))
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
