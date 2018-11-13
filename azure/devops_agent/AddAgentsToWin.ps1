[CmdletBinding()]
Param(
    [String[]]
    $VSTSToken,
    $VSTSUrl,
    $VSTSPool,
    $windowsLogonAccount,
    $windowsLogonPassword
)

$ErrorActionPreference="Stop";

# Extends OS Disk Space since Azure Pipeline agents use a lot of storage for packages
foreach($disk in Get-Disk)
{
    # Check if the disk in context is a Boot and System disk
    if((Get-Disk -Number $disk.number).IsBoot -And (Get-Disk -Number $disk.number).IsSystem)
    {
        # Get the drive letter assigned to the disk partition where OS is installed
        $driveLetter = (Get-Partition -DiskNumber $disk.Number | where {$_.DriveLetter}).DriveLetter
        Write-verbose "Current OS Drive: $driveLetter :\"

        # Get current size of the OS parition on the Disk
        $currentOSDiskSize = (Get-Partition -DriveLetter $driveLetter).Size
        Write-verbose "Current OS Partition Size: $currentOSDiskSize"

        # Get Partition Number of the OS partition on the Disk
        $partitionNum = (Get-Partition -DriveLetter $driveLetter).PartitionNumber
        Write-verbose "Current OS Partition Number: $partitionNum"

        # Get the available unallocated disk space size
        $unallocatedDiskSize = (Get-Disk -Number $disk.number).LargestFreeExtent
        Write-verbose "Total Unallocated Space Available: $unallocatedDiskSize"

        # Get the max allowed size for the OS Partition on the disk
        $allowedSize = (Get-PartitionSupportedSize -DiskNumber $disk.Number -PartitionNumber $partitionNum).SizeMax
        Write-verbose "Total Partition Size allowed: $allowedSize"

        if ($unallocatedDiskSize -gt 0 -And $unallocatedDiskSize -le $allowedSize)
        {
            $totalDiskSize = $allowedSize

            # Resize the OS Partition to Include the entire Unallocated disk space
            $resizeOp = Resize-Partition -DriveLetter C -Size $totalDiskSize
            Write-verbose "OS Drive Resize Completed $resizeOp"
        }
        else {
            Write-Verbose "There is no Unallocated space to extend OS Drive Partition size"
        }
    }
}

# Add Agents to Pipeline

If(-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
{
     throw "Run command in Administrator PowerShell Prompt"
};

if(-NOT (Test-Path $env:SystemDrive\'vstsagent'))
{
    mkdir $env:SystemDrive\'vstsagent'
};

Set-Location $env:SystemDrive\'vstsagent';

for($i=1; $i -lt 100; $i++)
{
    $destFolder="A"+$i.ToString();
    if(-NOT (Test-Path ($destFolder)))
    {
        mkdir $destFolder;
        Set-Location $destFolder;
        break;
    }
};

$agentZip="$PWD\agent.zip";

$DefaultProxy=[System.Net.WebRequest]::DefaultWebProxy;
$WebClient=New-Object Net.WebClient;

$creds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($(":$VSTSToken")))
$encodedAuthValue = "Basic " + $creds
$acceptHeaderValue = "application/json;api-version=3.0-preview"
$headers = @{Authorization = $encodedAuthValue;Accept = $acceptHeaderValue }
$vstsUrl = $VSTSUrl + "_apis/distributedtask/packages/agent?platform=win-x64&`$top=1"
$response = Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $vstsUrl -UserAgent $useragent
$response = ConvertFrom-Json $response.Content

$WebClient.DownloadFile($response.value[0].downloadUrl, $agentZip);

# $Uri='https://vstsagentpackage.azureedge.net/agent/2.141.1/vsts-agent-win-x86-2.141.1.zip';

# $WebClient.DownloadFile($Uri, $agentZip);

Add-Type -AssemblyName System.IO.Compression.FileSystem;[System.IO.Compression.ZipFile]::ExtractToDirectory($agentZip, "$PWD");

.\config.cmd --unattended `
             --url $VSTSUrl `
             --auth PAT `
             --token $VSTSToken `
             --pool $VSTSPool `
             --agent "$($env:COMPUTERNAME)-$(Get-Random)" `
             --replace `
             --runasservice `
             --work '_work' `
             --windowsLogonAccount $windowsLogonAccount `
             --windowsLogonPassword $windowsLogonPassword

Remove-Item $agentZip;
