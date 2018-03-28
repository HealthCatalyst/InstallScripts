Write-Output "Version 2018.03.27.02"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtime.onprem.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1 | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

$namespace = "fabricrealtime"

CreateOnPremStorage -namespace $namespace

LoadStack -namespace $namespace -baseUrl $GITHUB_URL -appfolder "realtime" -isAzure $false

# curl -sSL -o installrealtime.onprem.ps1 https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtime.onprem.ps1?p=ff
# pwsh -f installrealtime.onprem.ps1 -NonInteractive