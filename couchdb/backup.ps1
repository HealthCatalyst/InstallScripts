[CmdletBinding()]
param(
    [Parameter(Mandatory=$True)]
    [String] $couchDbHost,
    
    [Parameter(Mandatory=$True)]
    [String] $couchDbPort,
    
    [Parameter(Mandatory=$True)]
    [String] $couchDbAdminUsername,
    
    [Parameter(Mandatory=$True)]
    [String[]] $databaseNames,

    [Parameter(Mandatory=$True)]
    [String] $backupDirectory,

    [switch]$skipEncryption
)

Import-Module -Name .\utilities.psm1 -Force

$encryptedPasswordFile = Get-EncryptedPasswordFile $couchDbAdminUsername
if(!(Test-Path $encryptedPasswordFile)){
    Write-Warning "Password file not found."
    Write-Warning "Please ensure you have run the setcouchdbcredentials.ps1 prior to running couchbackup.ps1"
    exit 1
}

npm install -g @cloudant/couchbackup

$password = Get-DecryptedFileContent $encryptedPasswordFile

$couchDbUrl = Get-CouchDbUrl $couchDbHost $couchDbPort $couchDbAdminUsername $password

foreach($databaseName in $databaseNames)
{
    $dateSuffix = Get-Date -Format yyyyMMddHHmmss
    $backupFileName = $databaseName + "_" + $dateSuffix +".db"
    $backupFilePath = [System.IO.Path]::Combine($backupDirectory, $backupFileName)
    couchbackup --url $couchDbUrl --db $databaseName > $backupFilePath
    
    if(!$skipEncryption){
        Invoke-EncryptFile $backupFilePath $password
        Remove-Item -Path $backupFilePath
    }
}