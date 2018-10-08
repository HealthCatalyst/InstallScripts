<#
    .SYNOPSIS

    Sets up the DOS File Service.  Reads from install.config.

    .PARAMETER quiet

    Indicates that this script suppresses all user input. If a required value is not provided, the script will exit with an error

    .EXAMPLE

    .\setfileshare.ps1 -quiet
#>

param(
    [switch] $quiet
)

# https://stackoverflow.com/questions/9948517/how-to-stop-a-powershell-script-on-the-first-error
Set-StrictMode -Version latest
$ErrorActionPreference="Continue"

$myreleaseversion="1"

Write-Output "script version: 1.0.0"

docker swarm init | Out-Null

docker stack rm fabricrealtime | Out-Null

 Write-Output "waiting until network is removed"

while (docker network inspect -f "{{ .Name }}" fabricrealtime_realtimenet | Out-Null)
{
    Write-Output "."; 
	Start-Sleep 1; 
}	

docker secret rm CertPassword | Out-Null
"roboconf2" |  docker secret create CertPassword -

docker secret rm RabbitMqMgmtUiPassword | Out-Null
'roboconf2' | docker secret create RabbitMqMgmtUiPassword -

$env:CERT_HOSTNAME="$env:COMPUTERNAME.$env:USERDNSDOMAIN"

docker secret rm CertHostName | Out-Null
"localrealtime" |  docker secret create CertHostName -

# username
$dockerServiceAccountDefault=$env:UserName
$dockerServiceAccount = Read-Host "Press Enter to accept the default user account for Docker [$dockerServiceAccountDefault] or enter a new user account"
if ([string]::IsNullOrWhiteSpace($dockerServiceAccount)) {
    $dockerServiceAccount = $dockerServiceAccountDefault
}
Write-Output "Setting username to $dockerServiceAccount"
docker secret rm SqlServerUserName | Out-Null
$dockerServiceAccount | docker secret create SqlServerUserName -    

# password
$dockerServiceAccountPassword=""
while ([string]::IsNullOrWhiteSpace($dockerServiceAccountPassword)) {
    Do {$dockerServiceAccountPassword = Read-Host -assecurestring -Prompt "Please type in password for [$dockerServiceAccount]"} while ($($dockerServiceAccountPassword.Length) -lt 1)
    $dockerServiceAccountPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dockerServiceAccountPassword))
}
docker secret rm SqlServerPassword | Out-Null
$dockerServiceAccountPassword | docker secret create SqlServerPassword -

# dns domain
$dockerServiceAccountDomainDefault=$env:USERDNSDOMAIN
$dockerServiceAccountDomain = Read-Host "Press Enter to accept the default user account for Docker [$dockerServiceAccountDomainDefault] or enter a new domain"
if ([string]::IsNullOrWhiteSpace($dockerServiceAccountDomain)) {
    $dockerServiceAccountDomain = $dockerServiceAccountDomainDefault
}
Write-Output "Setting domain to $dockerServiceAccountDomain"
docker secret rm SqlServerDomain | Out-Null
$dockerServiceAccountDomain | docker secret create SqlServerDomain -

# AD url
$dockerServiceAccountAdUrlDefault=$env:LOGONSERVER
$dockerServiceAccountAdUrlDefault = $($dockerServiceAccountAdUrlDefault -replace "\\","")
$dockerServiceAccountAdUrl = Read-Host "Please type in Windows Active Directory URL to use to connect to SQL Server [$dockerServiceAccountAdUrlDefault]"
if ([string]::IsNullOrWhiteSpace($dockerServiceAccountAdUrl)) {
    $dockerServiceAccountAdUrl = $dockerServiceAccountAdUrlDefault
}
Write-Output "Setting AD url to $dockerServiceAccountAdUrl"
docker secret rm SqlServerADUrl | Out-Null
$dockerServiceAccountAdUrl | docker secret create SqlServerADUrl -

# Sql Server
$sqlServerNameDefault="$env:COMPUTERNAME"
$sqlServerName=""
$sqlServerName = Read-Host "Please type in SQL Server to connect to (default: $sqlServerNameDefault)"
if ([string]::IsNullOrWhiteSpace($sqlServerName)) {
    $sqlServerName = $sqlServerNameDefault
}
docker secret rm SqlServerName | Out-Null
$sqlServerName | docker secret create SqlServerName -

# Sql Database
$sqlServerDatabaseDefault="FabricRealtime"
$sqlServerDatabase = Read-Host "Please type in SQL Database to use (default: $sqlServerDatabaseDefault)"
if ([string]::IsNullOrWhiteSpace($sqlServerDatabase)) {
    $sqlServerDatabase = $sqlServerDatabaseDefault
}
docker secret rm SqlServerDatabase | Out-Null
$sqlServerDatabase | docker secret create SqlServerDatabase -

# $env:DISABLE_SSL="false"

# shared folder
$sharedFolderDefault="c:/tmp/fabricrealtime"
$sharedFolder=""
$sharedFolder = Read-Host "Please type in folder to store files (e.g., $sharedFolderDefault)"
if ([string]::IsNullOrWhiteSpace($sharedFolder)) {
    $sharedFolder = $sharedFolderDefault
}
$env:SHARED_DRIVE=$sharedFolder
New-Item -Path $env:SHARED_DRIVE -ItemType Directory -Force

$env:SHARED_DRIVE_CERTS="$env:SHARED_DRIVE/certs"
New-Item -Path $env:SHARED_DRIVE_CERTS -ItemType Directory -Force

$env:SHARED_DRIVE_RABBITMQ="$env:SHARED_DRIVE/rabbitmq"
New-Item -Path $env:SHARED_DRIVE_RABBITMQ -ItemType Directory -Force

$env:SHARED_DRIVE_MYSQL="$env:SHARED_DRIVE/mysql"
New-Item -Path $env:SHARED_DRIVE_MYSQL -ItemType Directory -Force

$env:SHARED_DRIVE_LOGS="$env:SHARED_DRIVE/fluentd"
New-Item -Path $env:SHARED_DRIVE_LOGS -ItemType Directory -Force

# docker stack deploy -c realtime-stack.yml fabricrealtime

# use docker stack deploy to start up all the services
$stackfilename="realtime-stack-sqlserver.yml"

# make sure we can pull an image
docker pull healthcatalyst/fabric.docker.interfaceengine:$myreleaseversion
docker pull healthcatalyst/fabric.certificateserver:$myreleaseversion
docker pull healthcatalyst/fabric.realtime.rabbitmq:$myreleaseversion
docker pull healthcatalyst/fabric.realtime.mysql:$myreleaseversion

Write-Output "running stack: $stackfilename"

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/$myreleaseversion"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$result += $set | Get-Random

Write-Output "Downloading from ${GITHUB_URL}/realtime/${stackfilename}?f=$result"

$Script = Invoke-WebRequest -useb ${GITHUB_URL}/realtime/${stackfilename}?f=$result;

$Script | docker stack deploy --orchestrator swarm --compose-file - fabricrealtime
