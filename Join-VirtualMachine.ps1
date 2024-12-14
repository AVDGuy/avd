################################################################################
##  File:  Join-VirtualMachine.ps1
##  Desc:  Joins the Virtual Machine to a Host Pool.
################################################################################

Param
(
    [Parameter (Mandatory = $false)][boolean] $isAzureADJoined = $false,
    [Parameter (Mandatory = $false)][boolean] $isIntuneManaged = $false,
    [Parameter (Mandatory = $true)][string] $avdRegistrationKey
)

$BuildFolder = "C:\ImageBuild"
$Logfile = "$BuildFolder\ImageBuild.log"
$BuildingBlock = "AVDAgent"
$BuildingBlockPath = Join-Path -Path $BuildFolder -ChildPath "$BuildingBlock"
 
$ErrorActionPreference = 'stop'

try {
    if (Test-Path $BuildFolder -PathType Container ) {
        Write-Host "$BuildFolder exists, not creating BuildFolder"

    }
    else {
        Write-Host "Creating BuildFolder"
        New-Item -Path ($BuildFolder) -ItemType Directory -Force  
    }
    Set-Location $BuildFolder

    Start-Transcript -Path (Join-Path -Path $BuildFolder -ChildPath "$BuildingBlock.log")

    if ($isAzureADJoined -eq "true") {
        LogWriter("Azure AD Joined Registry settings")
        $registryPath = "HKLM:\SOFTWARE\Microsoft\RDInfraAgent\AzureADJoin"
        if (Test-Path -Path $registryPath) {
            LogWriter("Setting reg key JoinAzureAd")
            New-ItemProperty -Path $registryPath -Name JoinAzureAD -PropertyType DWord -Value 0x01 -Force
        }
        else {
            LogWriter("Creating path for azure ad join registry keys: $registryPath")
            New-item -Path $registryPath -Force | Out-Null
            LogWriter("Setting reg key JoinAzureAD")
            New-ItemProperty -Path $registryPath -Name JoinAzureAD -PropertyType DWord -Value 0x01 -Force 
        }
        if ($isIntuneManaged -eq "true") {
            LogWriter("Setting reg key MDMEnrollmentId")
            New-ItemProperty -Path $registryPath -Name MDMEnrollmentId -PropertyType String -Value "0000000a-0000-0000-c000-000000000000" - Force
        }
    }

    $BootLoaderInstaller = $BuildingBlockPath + "Microsoft.RDInfra.RDAgentBootLoader.msi"
    $AgentInstaller = $BuildingBlockPath + "\Microsoft.RDInfra.RDAgent.msi"

    $files = @(
        @{url = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrmXv"; path = $AgentInstaller }
        @{url = "https://query.prod.cms.rt.microsoft.com/cms/api/am/binary/RWrxrH"; path = $BootLoaderInstaller }
    )

    $workers = foreach ($f in $files) { 
        $wc = New-Object System.Net.WebClient
        Write-Output $wc.DownloadFileTaskAsync($f.url, $f.path)
    }
    $workers.Result
  
    Write-Output "Installing AVD boot loader - current path is ${PSScriptRoot}"
    Start-Process -wait -FilePath $BootLoaderInstaller -ArgumentList "/q"
    Write-Output "Installing AVD agent"
    Start-Process -wait -FilePath $AgentInstaller -ArgumentList "/q RegistrationToken=${avdRegistrationKey}"

    Out-File -InputObject "Installed $BuildingBlock" -FilePath $Logfile -Append
 
    Stop-Transcript
}
catch {
    Out-File -InputObject "!Install $BuildingBlock Failed" -FilePath $Logfile -Append
    Out-File -InputObject $_.Exception.Message -FilePath $Logfile -Append
    throw "Install $BuildingBlock Failed: $($_.Exception.Message)"
}
