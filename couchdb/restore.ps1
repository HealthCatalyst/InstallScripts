[CmdletBinding()]
param(
    [Parameter(Mandatory=$True)]
    [String] $couchDbHost,

    [Parameter(Mandatory=$True)]
    [String] $couchDbPort,

    [Parameter(Mandatory=$True)]
    [String] $couchDbAdminUsername,

    [Parameter(Mandatory=$True)]
    [String] $databaseToRestore,

    [Parameter(Mandatory=$True)]
    [String] $backupFile
)

Import-Module -Name .\couchdb-utilities.psm1 -Force

$encryptedPasswordFile = Get-EncryptedPasswordFile $couchDbAdminUsername
if(!(Test-Path $encryptedPasswordFile)){
    Write-Warning "Password file not found."
    Write-Warning "Please ensure you have run the setcouchdbcredentials.ps1 prior to running couchbackup.ps1"
    exit 1
}

if(!(Test-Path $backupFile))
{
    Write-Warning "Backup file not found."
    Write-Warning "Please ensure the backup you are trying to restore exists"
    exit 1
}

npm install -g @cloudant/couchbackup

$password = Get-DecryptedFileContent $encryptedPasswordFile

$couchDbUrl = Get-CouchDbUrl $couchDbHost $couchDbPort $couchDbAdminUsername $password

$content = Get-DecryptedFileContent $backupFile
$content | couchrestore --url $couchDbUrl --db $databaseToRestore