param(
    [String]$identityVersion,
    [String]$authorizationVersion,
    [String]$webroot = "C:\inetpub\wwwroot", 
	[String]$iisUser = "IIS_IUSRS", 
	[String]$sslCertificateThumbprint,
	[String]$couchDbServer,
	[String]$couchDbUsername,
	[String]$couchDbPassword,
	[String]$appInsightsInstrumentationKey,
	[String]$siteName = "Default Web Site",
	[String]$hostUrl
)
#default auth and identity versions to latest
Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/common/Fabric-Install-Utilities.psm1 -OutFile Fabric-Install-Utilities.psm1
Import-Module -Name .\Fabric-Install-Utilities.psm1
Add-Type -AssemblyName System.IO.Compression.FileSystem
$workingDirectory = Split-Path $script:MyInvocation.MyCommand.Path

function Get-FabricRelease($appName, $appVersion)
{
    $outFile = "$env:Temp\Fabric.$appName.$appVersion.zip"
    $targetDirectory = "$env:Temp\Fabric.$appName.$appVersion"
    Write-Host "Downloading Fabric.$appName.$appVersion.zip to $outFile"
    if(Test-Path $targetDirectory){
        Remove-Item $targetDirectory -Force -Recurse
    }
    Invoke-WebRequest -Uri https://github.com/HealthCatalyst/Fabric.$appName/releases/download/v$appVersion/Fabric.$appName.$appVersion.zip -OutFile $outFile
    [System.IO.Compression.ZipFile]::ExtractToDirectory($outFile, $targetDirectory)
    return "$targetDirectory\drop\Fabric.$appName.API.zip"
}

function Install-FabricRelease($appName, $installArgs)
{
    Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/Fabric.$appName/master/Fabric.$appName.API/scripts/Install-$appName-Windows.ps1 -OutFile "$env:Temp\Install-$appName-Windows.ps1"
    Invoke-Expression "$env:Temp\Install-$appName-Windows.ps1 $installArgs"
}

function Get-CommonArguments()
{
    $installArgs = @()
    $installArgs += ("-sslCertificateThumbprint", $sslCertificateThumbprint)
    $installArgs += ("-couchDbServer", $couchDbServer)
    $installArgs += ("-couchDbUsername", $couchDbUsername)
    $installArgs += ("-couchDbPassword", $couchDbPassword)
    $installArgs += ("-appInsightsInstrumentationKey", $appInsightsInstrumentationKey)
    if($webroot){
        $installArgs += ("-webroot", $webroot)
    }
    if($iisUser){
        $installArgs += ("-iisUser", $iisUser)
    }
    return $installArgs
}

function Get-AccessToken($authUrl, $cliendId, $scope, $secret)
{
    $url = "$authUrl/connect/token"
    $body = @{
        client_id = $clientId
        grant_type = "client_credentials"
        scope = $scope
        client_secret = $secret
    }
    $accessTokenResponse = Invoke-RestMethod -Method Post -Uri $url -Body $body
    return $accessTokenResponse.access_token
}

function Create-ApiRegistration($authUrl, $body, $accessToken)
{
    $url = "$authUrl/api/apiresource"
    $headers = @{ "Accept" = "application/json"}
    if($accessToken){
        $headers.Add("Authorization", "Bearer $accessToken")
    }
    $registrationResponse = Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/json"
    return $registrationResponse.apiSecret    
}

function Create-ClientRegistration($authUrl, $body, $accessToken)
{
    $url = "$authUrl/api/client"
    $headers = @{ "Accept" = "application/json"}
    if($accessToken){
        $headers.Add("Authorization", "Bearer $accessToken")
    }
    $registrationResponse = Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/json"
    return $registrationResponse.clientSecret
}

if(!(Test-Prerequisite '*.NET Core*Windows Server Hosting*' 1.1.30327.81))
{
    Write-Host "Windows Server Hosting Bundle minimum version 1.1.30327.81 not installed...installing version 1.1.30327.81"
    Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/?linkid=844461 -OutFile $env:Temp\bundle.exe
    Start-Process $env:Temp\bundle.exe -Wait -ArgumentList '/quiet /install'
    net stop was /y
    net start w3svc
    Remove-Item $env:Temp\bundle.exe
}

if(!(Test-Prerequisite '*CouchDB*'))
{
    #add check to see if couchdb url is reachable
    Write-Host "CouchDB not installed, installing CouchDB Version 2.1.0.0"
    Invoke-WebRequest -Uri https://dl.bintray.com/apache/couchdb/win/2.1.0/apache-couchdb-2.1.0.msi -OutFile $env:Temp\apache-couchdb-2.1.0.msi
    Start-Process $env:Temp\apache-couchdb-2.1.0.msi -Wait
    Remove-Item $env:Temp\apache-couchdb-2.1.0.msi
    #add ability to create admin user
}elseif (!(Test-Prerequisite '*CouchDB*' 2.0.0.1)) {
    Write-Host "CouchDB is installed but does not meet the minimum version requirements, you must have CouchDB 2.0.0.1 or greater installed: https://dl.bintray.com/apache/couchdb/win/2.1.0/apache-couchdb-2.1.0.msi"
    exit 1
}

$identityServerUrl = "$hostUrl/identity"
$authorizationServerUrl = "$hostUrl/authorization"

$identityZipPackage = Get-FabricRelease Identity $identityVersion
$identityArgs = Get-CommonArguments
$identityArgs += ("-zipPackage", $identityZipPackage)
$identityArgs += ("-hostUrl", $hostUrl)
Install-FabricRelease Identity $identityArgs

cd $workingDirectory

$authorizationZipPackage = Get-FabricRelease Authorization $authorizationVersion
$authorizationArgs = Get-CommonArguments
$authorizationArgs += ("-zipPackage", $authorizationZipPackage)
$authorizationArgs += ("-identityServerUrl", $identityServerUrl)
Install-FabricRelease Authorization $authorizationArgs

cd $workingDirectory

#Register registration api
$body = @'
{
    "name":"registration-api",
    "userClaims":["name","email","role","groups"],
    "scopes":[{"name":"fabric/identity.manageresources"}]
}
'@
$registrationApiSecret = Create-ApiRegistration -authUrl $identityServerUrl -body $body

#Register Fabric.Installer
$body = @'
{
    "clientId":"fabric-installer", 
    "clientName":"Fabric Installer", 
    "requireConsent":"false", 
    "allowedGrantTypes": ["client_credentials"], 
    "allowedScopes": ["fabric/identity.manageresources", "fabric/authorization.read", "fabric/authorization.write", "fabric/authorization.manageclients"]
}
'@
$installerClientSecret = Create-ClientRegistration -authUrl $identityServerUrl -body $body

$accessToken = Get-AccessToken -authUrl $identityServerUrl -cliendId "fabric-installer" -scope "fabric/identity.manageresources" -secret $installerClientSecret

#Register authorization api
$body = @'
{
    "name":"authorization-api",
    "userClaims":["name","email","role","groups"],
    "scopes":[{"name":"fabric/authorization.read"}, {"name":"fabric/authorization.write"}, {"name":"fabric/authorization.manageclients"}]
}
'@
$authorizationApiSecret = Create-ApiRegistration -authUrl $identityServerUrl -body $body -accessToken $accessToken

#Register group fetcher client
$body = @'
{
    "clientId":"fabric-group-fetcher", 
    "clientName":"Fabric Group Fetcher", 
    "requireConsent":"false", 
    "allowedGrantTypes": ["client_credentials"], 
    "allowedScopes": ["fabric/authorization.read", "fabric/authorization.write", "fabric/authorization.manageclients"]
}
'@
$groupFetcherSecret = Create-ClientRegistration -authUrl $identityServerUrl -body $body -accessToken $accessToken

Write-Host "Please keep the following secrets in a secure place:"
Write-Host "Fabric.Installer clientSecret: $installerClientSecret"
Write-Host "Fabric.GroupFetcher clientSecret: $groupFetcherSecret"
Write-Host "Fabric.Authorization apiSecret: $authorizationApiSecret"
Write-Host "Fabric.Registration apiSecret: $registrationApiSecret"
Write-Host ""
Write-Host "The Fabric.Installer clientSecret will be needed in subsequent installations:"
Write-Host "Fabric.Installer clientSecret: $installerClientSecret"



  