Write-Output "Version 2018.03.27.01"

# curl -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/realtime/installrealtimekubernetes.ps1 | iex;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"
# $GITHUB_URL = "."

Invoke-WebRequest -useb ${GITHUB_URL}/kubernetes/common-kube.ps1 | Invoke-Expression;
# Get-Content ./kubernetes/common-kube.ps1 -Raw | Invoke-Expression;

Invoke-WebRequest -useb $GITHUB_URL/azure/common.ps1 | Invoke-Expression;
# Get-Content ./azure/common.ps1 -Raw | Invoke-Expression;

DownloadAzCliIfNeeded
$userInfo = $(GetLoggedInUserInfo)

$namespace = "fabricrealtime"

CreateAzureStorage -namespace $namespace

Invoke-WebRequest -useb "$GITHUB_URL/realtime/installyaml.ps1?f=$randomstring" | Invoke-Expression;

WaitForLoadBalancers -resourceGroup $(GetResourceGroup).ResourceGroup