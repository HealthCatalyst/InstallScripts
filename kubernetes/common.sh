
versioncommon="2018.02.13.03"

echo "Including common.ps1 version $versioncommon"
function GetCommonVersion() {
    echo $versioncommon
}

function Write-Output()
{
    echo $1
}

function Write-Host()
{
    echo $1
}

function ReplaceText(){
    local currentText=$1
    local replacementText=$2

# have to do this to preserve the tabs in the file per https://askubuntu.com/questions/267384/using-read-without-losing-the-tab
    old_IFS=$IFS      # save the field separator           
    IFS=$'\n'     # new field separator, the end of line

    while read -r line || [[ -n $line ]]; do echo "${line//$1/$2}"; done

    IFS=$old_IFS     # restore default field separator
}

function ReadYmlAndReplaceCustomer () {
    local baseUrl=$1
    local templateFile=$2
    local customerid=$3

    curl -sSL "$baseUrl/$templateFile" \
        | ReplaceText CUSTOMERID $customerid

}

function ReadSecretValue() {
    local secretname=$1
    local valueName=$2
    local namespace=$3
    if [[ -z "$namespace" ]]; then 
        namespace="default"
    fi

    secretbase64=$(kubectl get secret $secretname -o jsonpath="{.data.${valueName}}" -n $namespace --ignore-not-found=true)

    if [[ ! -z "$secretbase64" ]]; then 
        secretvalue=$(echo $secretbase64 | base64 --decode)
        echo $secretvalue
        return
    else
        echo "";
    fi
}

function ReadSecret() {
    local secretname=$1
    local namespace=$2
    ReadSecretValue $secretname "value" $namespace
}

function ReadSecretPassword() {
    local secretname=$1
    local namespace=$2

    return ReadSecretValue $secretname "password" $namespace
}

function SaveSecretValue() {
    local secretname=$1
    local valueName=$2
    local myvalue=$3
    local namespace=$4

    # secretname must be lower case alphanumeric characters, '-' or '.', and must start and end with an alphanumeric character
    if [[ -z "$namespace" ]]; then
        namespace="default"
    fi

    if [[ ! -z  "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data}' --ignore-not-found=true)" ]]; then
        kubectl delete secret $secretname -n $namespace
    fi

    kubectl create secret generic $secretname --namespace=$namespace --from-literal=${valueName}=$myvalue
}

function GeneratePassword() {
    local Length=3
    local set1="abcdefghijklmnopqrstuvwxyz"
    local set2="0123456789"
    local set3="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local set4='!.*@'
    local result=""

    # bash loops: https://www.cyberciti.biz/faq/bash-for-loop/
    for (( c=1; c<$Length; c++ ))
    do  
        result="${result}${set1:RANDOM%${#set1}:1}"
        result="${result}${set2:RANDOM%${#set2}:1}"
        result="${result}${set3:RANDOM%${#set3}:1}"
        result="${result}${set4:RANDOM%${#set4}:1}"
    done
    echo $result
}

function AskForPassword () {
    local secretname=$1
    local prompt=$2
    local namespace=$3

    if [[ -z "$namespace" ]]; then
        namespace="default"
    fi

    if [[ -z "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.password}' --ignore-not-found=true)" ]]; then
        mysqlrootpassword=""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        read -s -p "$prompt (leave empty for auto-generated)" mypasswordsecure < /dev/tty
        if [[ -z  "$mypasswordsecure" ]]; then
            mypassword="$(GeneratePassword)"
        else
            mypassword=$mypasswordsecure
        fi

        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mypassword
    else 
        Write-Output "$secretname secret already set so will reuse it"
    fi
}

function AskForPasswordAnyCharacters () {
    local secretname=$1
    local prompt=$2
    local namespace=$3
    local defaultvalue=$4

    if [[ -z "$namespace" ]]; then
        namespace="default"
    fi

    if [[ -z "$(kubectl get secret $secretname -n $namespace -o jsonpath='{.data.password}' --ignore-not-found=true)" ]]; then
        mysqlrootpassword=""
        # MySQL password requirements: https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
        # we also use sed to replace configs: https://unix.stackexchange.com/questions/32907/what-characters-do-i-need-to-escape-when-using-sed-in-a-sh-script
        read -s -p "$prompt (leave empty for auto-generated)" mypasswordsecure < /dev/tty
        if [[ -z  "$mypasswordsecure" ]]; then
            mypassword="$defaultvalue"
        else
            mypassword=$mypasswordsecure
        fi
        kubectl create secret generic $secretname --namespace=$namespace --from-literal=password=$mypassword
    else 
        Write-Output "$secretname secret already set so will reuse it"
    fi
}
