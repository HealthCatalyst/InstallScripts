#!/bin/sh
set -e
#
# This script is meant for quick & easy install via:
#   curl -sSL https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/nlp/installnlpkubernetes.sh | sh
#
GITHUB_URL="https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

# source <(curl -s http://mywebsite.com/myscript.txt)

if [[ -z $(kubectl get namespace fabricnlp --ignore-not-found=true) ]]; then
    echo "Creating namespace: fabricnlp"
    kubectl create namespace fabricnlp
else
    while read -s -p "Namespace exists.  Do you want to delete passwords and ALL data stored in this namespace? (y/n)" deleteSecrets && [[ -z "$deleteSecrets" ]] ; do
        echo "No-no, please, no blank passwords"
    done

    if [[ $deleteSecrets == "y" ]]; then    
        kubectl delete secret mysqlrootpassword -n fabricnlp --ignore-not-found=true
        kubectl delete secret mysqlpassword -n fabricnlp --ignore-not-found=true
        kubectl delete secret smtprelaypassword -n fabricnlp --ignore-not-found=true
               
    fi
fi

$customerid = ReadSecret -secretname customerid
$customerid = $customerid.ToLower().Trim()
Write-Output "Customer ID: $customerid"

function ReadSecretValue() {
    secretname=$1
    valueName=$2
    namespace=$3
    if ([string]::IsNullOrWhiteSpace($namespace)) { $namespace = "default"}

    $secretbase64 = kubectl get secret $secretname -o jsonpath="{.data.${valueName}}" -n $namespace --ignore-not-found=true

    if (![string]::IsNullOrWhiteSpace($secretbase64)) {
        $secretvalue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secretbase64))
        return $secretvalue
    }
    
    return "";

}

function global:ReadSecret($secretname, $namespace) {
    return ReadSecretValue -secretname $secretname -valueName "value" -namespace $namespace
}

function global:ReadSecretPassword($secretname, $namespace) {
    return ReadSecretValue -secretname $secretname -valueName "password" -namespace $namespace
}
