function Install-DACFx
{
    $packageName = "Microsoft.SqlServer.DacFx.x64"
    if (Get-Package -Name $packageName) {
        Log "$PackageName Powershell module already installed"
    } else {
        Log "Install $PackageName PowerShell Module"
        Register-PackageSource -Name NuGet -Location https://www.nuget.org/api/v2 -Provider NuGet -Trusted -Verbose | Out-Null
        Install-Package -Name $packageName -MinimumVersion 130.3485.1 -ProviderName NuGet -Force | Out-Null
    }
    (Get-Package -name $packageName).Version
}

function Copy-NavDatabase
(
    [Parameter(Mandatory=$true)]
    [string]$SourceDatabaseName,
    [Parameter(Mandatory=$true)]
    [string]$DestinationDatabaseName,
    [string]$DatabaseServer = 'localhost\NAVDEMO'
)
{
  try
  {
    if (Test-NavDatabase($DestinationDatabaseName))
    {
      Remove-NavDatabase $DestinationDatabaseName
    }

    Invoke-Sqlcmd -ServerInstance $DatabaseServer -Query ("ALTER DATABASE [{0}] SET OFFLINE WITH ROLLBACK IMMEDIATE" -f $SourceDatabaseName)

    #copy database files for .mdf and .ldf
    $DatabaseFiles = @()
    (Invoke-Sqlcmd -ServerInstance $DatabaseServer -Query ("SELECT Physical_Name as filename FROM sys.master_files WHERE DB_NAME(database_id) = '{0}'" -f $SourceDatabaseName)).filename | ForEach-Object {
          $FileInfo = Get-Item -Path $_
          $DestinationFile = "{0}\{1}{2}" -f $FileInfo.DirectoryName, $DestinationDatabaseName, $FileInfo.Extension

          Copy-Item -Path $FileInfo.FullName -Destination $DestinationFile -Force

          $DatabaseFiles = $DatabaseFiles + $DestinationFile
        }

    $Files = "(FILENAME = N'{0}'), (FILENAME = N'{1}')" -f $DatabaseFiles[0], $DatabaseFiles[1]

    Invoke-Sqlcmd -ServerInstance $DatabaseServer -Query ("CREATE DATABASE [{0}] ON {1} FOR ATTACH" -f $DestinationDatabaseName, $Files.ToString())
  }
  finally
  {
    Invoke-Sqlcmd -ServerInstance $DatabaseServer -Query ("ALTER DATABASE [{0}] SET ONLINE" -f $SourceDatabaseName)
  }
}

function Test-NavDatabase
(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    [string]$DatabaseServer = 'localhost\NAVDEMO'
)
{
        $sqlCommandText = @"
        USE MASTER
        SELECT '1' FROM SYS.DATABASES WHERE NAME = '$DatabaseName'
        GO
"@

    return ((Invoke-SqlCmd -ServerInstance $DatabaseServer -Query $sqlCommandText) -ne $null)
}

function Remove-NavDatabase
(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    [string]$DatabaseServer = 'localhost\NAVDEMO',
    [switch]$Force
)
{
    # Get database files in case they are not removed by the DROP
    $DatabaseFiles = Get-NavDatabaseFiles -DatabaseServer $DatabaseServer -DatabaseName $DatabaseName

    # To forcefully drop a database we can take it offline first
    if($Force)
    {
        Disable-NavDatabase -DatabaseServer $DatabaseServer -DatabaseName $DatabaseName
    }
    Invoke-Sqlcmd -ServerInstance $DatabaseServer -Query "DROP DATABASE [$DatabaseName]"

    # According to MSDN database files are not removed after dropping an offline database, we need to manually delete them
    $DatabaseFiles | ? { Test-Path $_ } | Remove-Item -Force
}

function Disable-NavDatabase
(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    [string]$DatabaseServer = 'localhost\NAVDEMO'
)
{
    Invoke-SqlCmd -ServerInstance $DatabaseServer -Query "ALTER DATABASE [$DatabaseName] SET OFFLINE WITH ROLLBACK IMMEDIATE"
}

function Get-NavDatabaseFiles
(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    [string]$DatabaseServer = 'localhost\NAVDEMO'
)
{
    Invoke-SqlCmd -ServerInstance $DatabaseServer -Query "SELECT f.physical_name FROM sys.sysdatabases db INNER JOIN sys.master_files f ON f.database_id = db.dbid WHERE db.name = '$DatabaseName'" |
        % {
            $file = $_.physical_name
            if (Test-Path $file)
            {
                $file = Resolve-Path $file
            }
            $file
        }
}

function Remove-NetworkServiceUser
(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    [string]$DatabaseServer = 'localhost\NAVDEMO'
)
{
    Log "Remove Network Service User from $DatabaseName"
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName]
       IF EXISTS (SELECT 'X' FROM sysusers WHERE name = 'NT AUTHORITY\NETWORK SERVICE' and isntuser = 1)
         BEGIN DROP USER [NT AUTHORITY\NETWORK SERVICE] END"
}

function Remove-NavDatabaseSystemTableData
(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    [string]$DatabaseServer = 'localhost\NAVDEMO'
)
{
    Log "Remove data from System Tables database $DatabaseName"
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[Server Instance]" 
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[$("$")ndo$("$")cachesync]"
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[$("$")ndo$("$")tenants]"
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[Object Tracking]" 

    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName]
      IF EXISTS ( SELECT 'X' FROM [sys].[tables] WHERE name = 'Active Session' AND type = 'U' )
        BEGIN Delete from dbo.[Active Session] END" 
    
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName]
      IF EXISTS ( SELECT 'X' FROM [sys].[tables] WHERE name = 'Session Event' AND type = 'U' )
        BEGIN Delete from dbo.[Session Event] END" 

    Remove-NetworkServiceUser -DatabaseServer $DatabaseServer -DatabaseName $DatabaseName
}

function Remove-NavTenantDatabaseUserData
(        
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName,
    [string]$DatabaseServer = 'localhost\NAVDEMO',
    [bool]$RemoveUserData = $true
)
{
    Log "Remove data from User table and related tables in $DatabaseName database."
    if ($RemoveUserData) {
        Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[Access Control]" 
        Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[User Property]" 
        Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[User Personalization]" 
        Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[User Metadata]" 
        Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[User Default Style Sheet]" 
        Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[User]" 
    }
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[Active Session]" 
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DELETE FROM dbo.[Session Event]" 

#    Log "Remove the tenantid from $DatabaseName"
#    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] UPDATE dbo.[$("$")ndo$("$")tenantproperty] SET tenantid = ''" 

    Log "Drop triggers from $DatabaseName"
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DROP TRIGGER [dbo].[RemoveOnLogoutActiveSession]" 
    Invoke-Sqlcmd -ea Ignore -ServerInstance $DatabaseServer -Query "USE [$DatabaseName] DROP TRIGGER [dbo].[DeleteActiveSession]" 

    Remove-NetworkServiceUser -DatabaseServer $DatabaseServer -DatabaseName $DatabaseName
}

function ExtractCollationInformationFromNAVBacpac($bacpacFileName)
{
    $tempFolder = "c:\demo\AzureSQL"
    $tempZipName = "$tempFolder\bacpac.zip"
    $modelXmlName = "$tempFolder\model.xml"
    Copy-Item -Path $bacpacFileName -Destination $tempZipName
    $shell = new-object -com shell.application
    $bacpacZip = $shell.NameSpace($tempZipName)
    $modelItem = $bacpacZip.Items() | Where-Object { $_.Name -eq "model" }
    $shell.NameSpace($tempFolder).Copyhere($modelItem, 16+4)

    $XPathForDBCollationNode = "/*[local-name()='DataSchemaModel']/*[local-name()='Model']/*[local-name()='Element'][@Type='SqlDatabaseOptions']/*[local-name()='Property'][@Name='Collation']/@Value"
    $dbCollationNode = Select-Xml -Path $modelXmlName -XPath $XPathForDBCollationNode
    Remove-Item $modelXmlName
    Remove-Item $tempZipName
    return $dbCollationNode.Node.Value

}

Function GetFileName($title, $initialDirectory, $fileType)
{   
 [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null

 $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
 $OpenFileDialog.initialDirectory = $initialDirectory
 $OpenFileDialog.Title = $title
 $OpenFileDialog.filter = "All files (*.$fileType)| *.$fileType"
 $OpenFileDialog.ShowDialog() | Out-Null
 $OpenFileDialog.filename
} 

function SetAzureSubscription
{
    Add-AzureAccount | Out-Null
    $subscriptions = Get-AzureSubscription
    if ($subscriptions -isnot [System.Array]) {
        $UseSubscription = $subscriptions.SubscriptionId
    } else {
        $UseSubscription = (Get-AzureSubscription -Default).SubscriptionId
        Log -OnlyInfo -kind Emphasis "Available Subscriptions:"
        $subscriptions | % { 
            if ($_.SubscriptionId -eq $useSubscription) { $kind = "Emphasis" } else { $kind = "Info" }
            Log -OnlyInfo -kind $kind ($_.SubscriptionId + " : " + $_.SubscriptionName)
        }
        $UseSubscription = Get-UserInput -Id UseSubscription -Text "Subscription ID to use" -Default $UseSubscription
    }
    Set-AzureSubscription -SubscriptionId $UseSubscription -Environment AzureCloud
    Select-AzureSubscription -SubscriptionId $UseSubscription -Current
}

function GetDefaultAzureLocation([string]$Hostname) {

    $locationMapping = @{
        "europewest" = "West Europe";
        "useast" = "East US";
        "useast2" = "East US 2";
        "uswest" = "West US";
        "usnorth" = "North Central US";
        "europenorth" = "North Europe";
        "uscentral" = "Central US";
        "asiaeast" = "East Asia";
        "asiasoutheast" = "Southeast Asia";
        "ussouth" = "South Central US";
        "japanwest" = "Japan West";
        "japaneast" = "Japan East";
        "brazilsouth" = "Brazil South";
        "australiaeast" = "Australia East";
        "australiasoutheast" = "Australia Southeast";
        "indiacentral" = "Central India";
        "indiawest" = "West India";
        "indiasouth" = "South India";
        "canadaeast" = "Canada East";
        "canadacentral" = "Canada Central";
        "uswest2" = "West US 2";
        "uswestcentral" = "West Central US";
        "ukwest" = "UK West";
        "uksouth" = "UK South";
    }

    try {
        $dnsrecord = Resolve-DnsName $Hostname -Type A
        if ($dnsrecord -is [System.Array]) {
            $MyIP = $dnsrecord[$dnsrecord.Count-1].IPAddress
        } else {
            $MyIP = $dnsrecord.IPAddress
        }
        $MyIParray = [IPAddress]::Parse($MyIP).GetAddressBytes()
        if([BitConverter]::IsLittleEndian) {
            [Array]::Reverse($MyIParray)
        }
        $MyIPint = [BitConverter]::ToUInt32($MyIParray,0)
        $wc = New-Object System.Net.WebClient
        $s = $wc.DownloadString("http://www.microsoft.com/en-us/download/confirmation.aspx?id=41653")
        $sf = "meta http-equiv=""refresh"" content=""0;url="
        $idx = $s.IndexOf($sf)
        if ($idx -gt 0) {
            $s = $s.Substring($idx + $sf.Length)
            $s = $s.Substring(0, $s.IndexOf(""""))
            $IPranges = [xml]$wc.DownloadString($s)
            $IPranges.SelectNodes("/AzurePublicIpAddresses/Region/IpRange") | % {
                $IP = $_.Subnet.Split("/")[0]
                $Subnet = $_.Subnet.Split("/")[1]
                $IPaddresses = [Math]::Pow(2,32-[int]::Parse($Subnet))
                $IParray = [IPAddress]::Parse($IP).GetAddressBytes()
                if([BitConverter]::IsLittleEndian) {
                    [Array]::Reverse($IParray)
                }
                $IPint = [BitConverter]::ToUInt32($IParray,0)
                if (($MyIPint -ge $IPint) -and ($MyIPint -lt ($IPint+$IPaddresses))) {
                    $locationMapping[$_.ParentNode.Name]
                    return
                }
            }
        }
    } catch {
    }
}
