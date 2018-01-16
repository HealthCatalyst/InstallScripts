$version = "2018.01.16.1"

Write-Host "Installed Common functions version $version"
function global:GetCommonVersion(){
    return $version
}

function global:CreateShare($resourceGroup, $sharename, $deleteExisting) {
    $AKS_PERS_STORAGE_ACCOUNT_NAME_BASE64 = kubectl get secret azure-secret -o jsonpath='{.data.azurestorageaccountname}'
    $AKS_PERS_STORAGE_ACCOUNT_NAME = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($AKS_PERS_STORAGE_ACCOUNT_NAME_BASE64))
    
    $AZURE_STORAGE_CONNECTION_STRING = az storage account show-connection-string -n $AKS_PERS_STORAGE_ACCOUNT_NAME -g $resourceGroup -o tsv
    
    if ($deleteExisting) {
        if ($(az storage share exists -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --query "exists" -o tsv)) {
            Write-Output "Deleting the file share: $sharename"
            az storage share delete -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING
        
            
            Write-Output "Waiting for completion of delete for the file share: $sharename"        
            Do {
                Start-Sleep -Seconds 5 
                $SHARE_EXISTS = $(az storage share exists -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --query "exists" -o tsv)
                Write-Host "."
            }
            while ($SHARE_EXISTS)
        }
    }

    if (!$(az storage share exists -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --query "exists" -o tsv)) {
        Write-Output "Creating the file share: $sharename"        
        az storage share create -n $sharename --connection-string $AZURE_STORAGE_CONNECTION_STRING --quota 512       
    }
}


function global:ReadSecret($secretname, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    $secretbase64 = kubectl get secret $secretname -o jsonpath='{.data.value}' -n $namespace
    $secretvalue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretbase64))
    return $secretvalue
}

function global:ReadSecretPassword($secretname, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    $secretbase64 = kubectl get secret $secretname -o jsonpath='{.data.password}' -n $namespace
    $secretvalue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretbase64))
    return $secretvalue
}

function global:GeneratePassword() {
    $Length = 3
    $set1 = "abcdefghijklmnopqrstuvwxyz".ToCharArray()
    $set2 = "0123456789".ToCharArray()
    $set3 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".ToCharArray()
    $set4 = "!.*@".ToCharArray()        
    $result = ""
    for ($x = 0; $x -lt $Length; $x++) {
        $result += $set1 | Get-Random
        $result += $set2 | Get-Random
        $result += $set3 | Get-Random
        $result += $set4 | Get-Random
    }
    return $result
}

function global:AskForPassword ($secretname, $prompt, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.password}' --ignore-not-found=true))) {

        $mysqlrootpassword = ""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        Do {
            $mysqlrootpasswordsecure = Read-host "$prompt (leave empty for auto-generated)" -AsSecureString 
            if ($mysqlrootpasswordsecure.Length -lt 1) {
                $mysqlrootpassword = GeneratePassword
            }
            else {
                $mysqlrootpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlrootpasswordsecure))                
            }
        }
        while (($mysqlrootpassword -notmatch "^[a-z0-9!.*@\s]+$") -or ($mysqlrootpassword.Length -lt 8 ))
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mysqlrootpassword
    }
    else {
        Write-Output "$secretname secret already set so will reuse it"
    }
}

function global:AskForPasswordAnyCharacters ($secretname, $prompt, $namespace, $defaultvalue) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.password}' --ignore-not-found=true))) {

        $mysqlrootpassword = ""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        Do {
            $mysqlrootpasswordsecure = Read-host "$prompt (leave empty for default)" -AsSecureString 
            if ($mysqlrootpasswordsecure.Length -lt 1) {
                $mysqlrootpassword = $defaultvalue
            }
            else {
                $mysqlrootpassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($mysqlrootpasswordsecure))                
            }
        }
        while ($mysqlrootpassword.Length -lt 8 )
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mysqlrootpassword
    }
    else {
        Write-Output "$secretname secret already set so will reuse it"
    }
}

function global:AskForSecretValue ($secretname, $prompt, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.value}' --ignore-not-found=true))) {

        $certhostname = ""
        Do {
            $certhostname = Read-host "$prompt"
        }
        while ($certhostname.Length -lt 1 )
    
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=value=$certhostname
    }
    else {
        Write-Output "$secretname secret already set so will reuse it"
    }    
}

function global:ReadYmlAndReplaceCustomer($templateFile, $customerid ) {
    if ($GITHUB_URL.StartsWith("http")) { 
        #        Write-Output "Reading from url: $GITHUB_URL/$templateFile"
        Invoke-WebRequest -Uri "$GITHUB_URL/$templateFile" -UseBasicParsing -ContentType "text/plain; charset=utf-8" `
            | Select-Object -Expand Content `
            | Foreach-Object {$_ -replace 'CUSTOMERID', "$customerid"}
    }
    else {
        #        Write-Output "Reading from local file: $GITHUB_URL/$templateFile"
        Get-Content -Path "$GITHUB_URL/$templateFile" `
            | Foreach-Object {$_ -replace 'CUSTOMERID', "$customerid"} 
    }
}

# helper functions for subnet match
# from https://gallery.technet.microsoft.com/scriptcenter/Start-and-End-IP-addresses-bcccc3a9
function global:Get-FirstIP {
    <# 
  .SYNOPSIS  
    Get the IP addresses in a range 
  .EXAMPLE 
   Get-IPrange -start 192.168.8.2 -end 192.168.8.20 
  .EXAMPLE 
   Get-IPrange -ip 192.168.8.2 -mask 255.255.255.0 
  .EXAMPLE 
   Get-IPrange -ip 192.168.8.3 -cidr 24 
#> 
 
    param 
    ( 
        [string]$start, 
        [string]$end, 
        [string]$ip, 
        [string]$mask, 
        [int]$cidr 
    ) 
 
    function IP-toINT64 () { 
        param ($ip) 
 
        $octets = $ip.split(".") 
        return [int64]([int64]$octets[0] * 16777216 + [int64]$octets[1] * 65536 + [int64]$octets[2] * 256 + [int64]$octets[3]) 
    } 
 
    function INT64-toIP() { 
        param ([int64]$int) 

        return (([math]::truncate($int / 16777216)).tostring() + "." + ([math]::truncate(($int % 16777216) / 65536)).tostring() + "." + ([math]::truncate(($int % 65536) / 256)).tostring() + "." + ([math]::truncate($int % 256)).tostring() )
    } 
 
    if ($ip.Contains("/")) {
        $Temp = $ip.Split("/")
        $ip = $Temp[0]
        $cidr = $Temp[1]
    }

    if ($ip) {$ipaddr = [Net.IPAddress]::Parse($ip)} 
    if ($cidr) {$maskaddr = [Net.IPAddress]::Parse((INT64-toIP -int ([convert]::ToInt64(("1" * $cidr + "0" * (32 - $cidr)), 2)))) } 
    if ($mask) {$maskaddr = [Net.IPAddress]::Parse($mask)} 
    if ($ip) {$networkaddr = new-object net.ipaddress ($maskaddr.address -band $ipaddr.address)} 
    if ($ip) {$broadcastaddr = new-object net.ipaddress (([system.net.ipaddress]::parse("255.255.255.255").address -bxor $maskaddr.address -bor $networkaddr.address))} 
 
    if ($ip) { 
        $startaddr = IP-toINT64 -ip $networkaddr.ipaddresstostring 
        $endaddr = IP-toINT64 -ip $broadcastaddr.ipaddresstostring 
    }
    else { 
        $startaddr = IP-toINT64 -ip $start 
        $endaddr = IP-toINT64 -ip $end 
    } 
 
    # https://github.com/Azure/acs-engine/blob/master/docs/kubernetes/features.md#feat-custom-vnet
    $startaddr = $startaddr + 239 # skip the first few since they are reserved
    INT64-toIP -int $startaddr
}
