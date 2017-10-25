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

function Get-Salt()
{
    begin{
        $salt = New-Object Byte[] 16
        $crypto = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    }

    process{
        $crypto.GetBytes($salt)
        return $salt
    }

    end{
        $crypto.Dispose()
    }

}
function Invoke-EncryptFile([string] $inputFile, [string] $password)
{
    $outputFile = $inputFile + ".aes"

    try{
        #Create Encryption Key
        $saltBytes = Get-Salt
        $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($password)
        $key = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passwordBytes, $saltBytes, 1000)

        #Create Crypto Provider
        $crypto = Get-CryptoProvider $key

        #Setup input and output streams
        $fileStreamWriter = New-Object System.IO.FileStream($outputFile, [System.IO.FileMode]::Create)
        $fileStreamReader = New-Object System.IO.FileStream($inputFile, [System.IO.FileMode]::Open)
        
        #Write the salt
        $fileStreamWriter.Write($saltBytes, 0, $saltBytes.Length)

        #Encrypt
        $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($fileStreamWriter, $crypto.CreateEncryptor(), [System.Security.Cryptography.CryptoStreamMode]::Write)
        $fileStreamReader.CopyTo($cryptoStream)

        #Close handles
        $cryptoStream.FlushFinalBlock()
        $cryptoStream.Close()
        $fileStreamReader.Close()
        $fileStreamWriter.Close()
    }catch{
        Write-Error $_
        if($fileStreamWriter){
            $fileStreamWriter.Close()
        }
        if(Test-Path $outputFile){
            Remove-Item $outputFile -Force
        }
    }finally{
        if($cryptoStream){
            $cryptoStream.Close()
        }
        if($fileStreamReader){
            $fileStreamReader.Close()
        }
        if($fileStreamWriter){
            $fileStreamWriter.Close()
        }
    }
}

function Invoke-DecryptFile([string] $inputFile, [string] $password)
{
    $outputFile = $inputFile.Replace(".aes", "")

    try{
        
        #Create Encryption Key using salt from file
        $fileStreamReader = New-Object System.IO.FileStream($inputFile, [System.IO.FileMode]::Open)
        $passwordBytes = [System.Text.Encoding]::UTF8.GetBytes($password)
        $saltBytes = New-Object Byte[] 16
        $fileStreamReader.Read($saltBytes, 0, $saltBytes.Length)
        $key = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passwordBytes, $saltBytes, 1000)

        #Create Crypto Provider
        $crypto = Get-CryptoProvider $key
        
        #Setup output file stream
        $fileStreamWriter = New-Object System.IO.FileStream($outputFile, [System.IO.FileMode]::Create)

        #Decrypt
        $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($fileStreamWriter, $crypto.CreateDecryptor(), [System.Security.Cryptography.CryptoStreamMode]::Write)
        $fileStreamReader.CopyTo($cryptoStream)
    
        #Clean up handles
        $cryptoStream.FlushFinalBlock()
        $cryptoStream.Close()
        $fileStreamReader.Close()
        $fileStreamWriter.Close()

    }catch{
        
        Write-Error $_
        if($fileStreamWriter){
            $fileStreamWriter.Close()
        }
        if(Test-Path $outputFile){
            Remove-Item $outputFile -Force
        }
        
    }finally{
        if($cryptoStream){
            $cryptoStream.Close()
        }
        if($fileStreamReader){
            $fileStreamReader.Close()
        }
        if($fileStreamWriter){
            $fileStreamWriter.Close()
        }
    }
    
}

function Get-CryptoProvider($key)
{
    $crypto = New-Object System.Security.Cryptography.RijndaelManaged
    $crypto.KeySize = 256
    $crypto.BlockSize = 128
    $crypto.Key = $key.GetBytes($crypto.KeySize/8)
    $crypto.IV = $key.GetBytes($crypto.BlockSize/8)
    return $crypto
}

Export-ModuleMember -Function Get-EncryptedPasswordFile
Export-ModuleMember -Function Get-DecryptedFileContent
Export-ModuleMember -Function Get-CouchDbUrl
Export-ModuleMember -Function Invoke-EncryptFile
Export-ModuleMember -Function Invoke-DecryptFile