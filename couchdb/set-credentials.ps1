$couchAdminUserName = Read-Host "Enter the CouchDb administrator username"
$securePassword = Read-Host "Enter the CouchDb administrator password" -AsSecureString

$encryptedPasswordFile = $couchAdminUserName + "-password.txt"
 ConvertFrom-SecureString $securePassword > $encryptedPasswordFile
