function Get-EncryptedPasswordFile([string] $userName)
{
    return $userName + "-password.txt"
}

function Get-DecryptedFileContent([string] $encryptedFile)
{
    $secureContent = Get-Content $encryptedFile | ConvertTo-SecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureContent)
    $content = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    return $content
}

function Get-CouchDbUrl([string] $couchDbHost, [string] $couchDbPort, [string] $couchDbAdminUsername, [string] $password)
{
    $couchDbUrl = "http://" + $couchDbAdminUsername + ":" + $password + "@" + $couchDbHost + ":" + $couchDbPort
    return $couchDbUrl
}

Export-ModuleMember -Function Get-EncryptedPasswordFile
Export-ModuleMember -Function Get-DecryptedFileContent
Export-ModuleMember -Function Get-CouchDbUrl