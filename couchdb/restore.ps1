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
    [String] $backupFile,

    [switch] $skipDecryption
)

Import-Module -Name .\utilities.psm1 -Force

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

if($skipDecryption){
    Get-Content $backupFile | couchrestore --url $couchDbUrl --db $databaseToRestore
}else{
    Invoke-DecryptFile $backupFile $password
    $decryptedFile = $backupFile.Replace(".aes", "")
    Get-Content $decryptedFile | couchrestore --url $couchDbUrl --db $databaseToRestore
    Remove-Item -Path $decryptedFile
}