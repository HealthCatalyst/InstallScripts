# this file contains common functions for kubernetes
$versionkubecommon = "2018.03.27.01"

$set = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
$randomstring += $set | Get-Random

Write-Host "Including common-kube.ps1 version $versionkubecommon"
function global:GetCommonKubeVersion() {
    return $versionkubecommon
}

function global:ReadSecretValue([ValidateNotNullOrEmpty()] $secretname, [ValidateNotNullOrEmpty()] $valueName, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    $secretbase64 = kubectl get secret $secretname -o jsonpath="{.data.${valueName}}" -n $namespace --ignore-not-found=true 2> $null

    if (![string]::IsNullOrWhiteSpace($secretbase64)) {
        $secretvalue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretbase64))
        return $secretvalue
    }
    
    return "";
}

function global:ReadSecret([ValidateNotNullOrEmpty()] $secretname, $namespace) {
    return ReadSecretValue -secretname $secretname -valueName "value" -namespace $namespace
}

function global:ReadSecretPassword([ValidateNotNullOrEmpty()] $secretname, $namespace) {
    return ReadSecretValue -secretname $secretname -valueName "password" -namespace $namespace
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

function global:SaveSecretValue([ValidateNotNullOrEmpty()] $secretname, [ValidateNotNullOrEmpty()] $valueName, $value, $namespace) {
    # secretname must be lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    if (![string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {
        kubectl delete secret $secretname -n $namespace
    }

    kubectl create secret generic $secretname --namespace=$namespace --from-literal=${valueName}=$value
}

function global:AskForPassword ([ValidateNotNullOrEmpty()] $secretname, $prompt, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {

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
        Write-Host "$secretname secret already set so will reuse it"
    }
}

function global:AskForPasswordAnyCharacters ([ValidateNotNullOrEmpty()] $secretname, $prompt, $namespace, $defaultvalue) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {

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
        while (($mysqlrootpassword.Length -lt 8 ) -and (!("$mysqlrootpassword" -eq "$defaultvalue")))
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mysqlrootpassword
    }
    else {
        Write-Host "$secretname secret already set so will reuse it"
    }
}

function global:AskForSecretValue ([ValidateNotNullOrEmpty()] $secretname, $prompt, $namespace) {
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}
    if ([string]::IsNullOrWhiteSpace($(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true))) {

        $certhostname = ""
        Do {
            $certhostname = Read-host "$prompt"
        }
        while ($certhostname.Length -lt 1 )
    
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=value=$certhostname
    }
    else {
        Write-Host "$secretname secret already set so will reuse it"
    }    
}

function global:ReadYamlAndReplaceCustomer([ValidateNotNullOrEmpty()] $baseUrl, [ValidateNotNullOrEmpty()] $templateFile, $customerid ) {
    Write-Host "Reading from url: ${baseUrl}/${templateFile}"

    if ($baseUrl.StartsWith("http")) { 
        Invoke-WebRequest -Uri "${baseUrl}/${templateFile}?f=${randomstring}" -UseBasicParsing -ContentType "text/plain; charset=utf-8" `
            | Select-Object -Expand Content `
            | Foreach-Object {$_ -replace 'CUSTOMERID', "$customerid"}
    }
    else {
        #        Write-Host "Reading from local file: $GITHUB_URL/$templateFile"
        Get-Content -Path "$baseUrl/$templateFile" `
            | Foreach-Object {$_ -replace 'CUSTOMERID', "$customerid"} 
    }
}

# $files is a list of files separated by spaces
function global:DownloadAndDeployYamlFiles([ValidateNotNullOrEmpty()] $folder, [ValidateNotNullOrEmpty()] $files, [ValidateNotNullOrEmpty()] $baseUrl, [ValidateNotNullOrEmpty()] $customerid, $public_ip ){
    [hashtable]$Return = @{} 

    foreach ($file in $files.Split(" ")) { 
        if([string]::IsNullOrEmpty($public_ip)){
            ReadYamlAndReplaceCustomer -baseUrl $baseUrl -templateFile "${folder}/${file}" -customerid $customerid | kubectl apply -f -
        }
        else
        {
            ReadYamlAndReplaceCustomer -baseUrl $baseUrl -templateFile "${folder}/${file}" -customerid $customerid `
            | Foreach-Object {$_ -replace 'PUBLICIP', "$publicip"} `
            | kubectl apply -f -
        }
    }

    return $Return
}

# from https://github.com/majkinetor/posh/blob/master/MM_Network/Stop-ProcessByPort.ps1
function global:Stop-ProcessByPort( [ValidateNotNullOrEmpty()] [int] $Port ) {    
    $netstat = netstat.exe -ano | Select-Object -Skip 4
    $p_line = $netstat | Where-Object { $p = ( -split $_ | Select-Object -Index 1) -split ':' | Select-Object -Last 1; $p -eq $Port } | Select-Object -First 1
    if (!$p_line) { Write-Host "No process found using port" $Port; return }    
    $p_id = $p_line -split '\s+' | Select-Object -Last 1
    if (!$p_id) { throw "Can't parse process id for port $Port" }
    
    Read-Host "There is another process running on this port.  Click ENTER to open an elevated prompt to stop that process."

    Start-Process powershell -verb RunAs -ArgumentList "Stop-Process $p_id -Force"
}



function global:CleanOutNamespace([ValidateNotNullOrEmpty()] $namespace) {
    [hashtable]$Return = @{} 

    Write-Host "--- Cleaning out any old resources in $namespace ---"

    # note kubectl doesn't like spaces in between commas below
    kubectl delete --all 'deployments,pods,services,ingress,persistentvolumeclaims,jobs,cronjobs' --namespace=$namespace --ignore-not-found=true

    # can't delete persistent volume claims since they are not scoped to namespace
    kubectl delete 'pv' -l namespace=$namespace --ignore-not-found=true

    $CLEANUP_DONE = "n"
    Do {
        $CLEANUP_DONE = $(kubectl get 'deployments,pods,services,ingress,persistentvolumeclaims,jobs,cronjobs' --namespace=$namespace -o jsonpath="{.items[*].metadata.name}")
        if (![string]::IsNullOrEmpty($CLEANUP_DONE)) {
            Write-Host "Remaining items: $CLEANUP_DONE"
            Start-Sleep 5
        }
    }
    while (![string]::IsNullOrEmpty($CLEANUP_DONE))

    return $Return
}

function global:SwitchToKubCluster([ValidateNotNullOrEmpty()] $kubfolder, [ValidateNotNullOrEmpty()] $clustername) {

    [hashtable]$Return = @{} 

    $fileToUse = "${kubfolder}\${clustername}\temp\.kube\config"

    Write-Host "Checking if file exists: $fileToUse"

    if (Test-Path -Path $fileToUse) {
        Write-Host "Switching kube config to this cluster: $clustername"

        $userKubeConfigFolder = "${env:userprofile}\.kube"
        If (!(Test-Path $userKubeConfigFolder)) {
            Write-Output "Creating $userKubeConfigFolder"
            New-Item -ItemType Directory -Force -Path "$userKubeConfigFolder"
        }            

        $destinationFile = "${userKubeConfigFolder}\config"
        Write-Host "Copying $fileToUse to $destinationFile"
        Copy-Item -Path "$fileToUse" -Destination "$destinationFile"
        # set environment variable KUBECONFIG to point to this location
        $env:KUBECONFIG = "$destinationFile"
        [Environment]::SetEnvironmentVariable("KUBECONFIG", "$destinationFile", [EnvironmentVariableTarget]::User)
        Write-Host "Current cluster: $(kubectl config current-context)"    
    }
    else {
        Write-Error "$fileToUse not found"
    }

    return $Return
}
function global:CleanKubConfig() {
    Write-Host "Clearing out kube config"
    $userKubeConfigFolder = "$env:userprofile\.kube"
    $destinationFile = "${userKubeConfigFolder}\config"
    Remove-Item -Path "$destinationFile" -Force
    # set environment variable KUBECONFIG to point to this location
    $env:KUBECONFIG = ""
    [Environment]::SetEnvironmentVariable("KUBECONFIG", "", [EnvironmentVariableTarget]::User)
}

# --------------------
Write-Host "end common-kube.ps1 version $versioncommon"