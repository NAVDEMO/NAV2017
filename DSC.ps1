Configuration NAVDSC
{
    param(
        [string[]]$ComputerName="localhost"
    )

    Node $ComputerName
    {
        Package WindowsAzurePowershellGet_Installation
        {
            Ensure = "Present"
            Name = "Microsoft Azure PowerShell"
            Path = "$env:ProgramFiles\Microsoft\Web Platform Installer\WebPiCmd-x64.exe"
            ProductId = ''
            Arguments = "/install /products:WindowsAzurePowershellGet /AcceptEula /ForceReboot"
        }
    }
}