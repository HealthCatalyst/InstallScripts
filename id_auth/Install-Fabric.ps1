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
    Move-Item -Path "$targetDirectory\drop\Fabric.$appName.API.zip" -Destination "$targetDirectory\Fabric.$appName.API.zip"
    if(Test-Path "$targetDirectory\drop"){
        Remove-Item "$targetDirectory\drop" -Force -Recurse
    }
    Remove-Item $outFile -Force
    return "$targetDirectory\Fabric.$appName.API.zip"
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

function Test-RegistrationComplete($authUrl)
{
    $url = "$authUrl/api/client/fabric-installer"
    $headers = @{"Accept" = "application/json"}
    
    try {
        Invoke-RestMethod -Method Get -Uri $url -Headers $headers
    } catch {
        $exception = $_.Exception
    }

    if($exception -ne $null -and $exception.Response.StatusCode.value__ -eq 401)
    {
        Write-Host "Fabric registration is already complete."
        return $true
    }

    return $false
}

if(!(Test-Prerequisite '*.NET Core*Windows Server Hosting*' 1.1.30327.81))
{
    Write-Host ".NET Core Windows Server Hosting Bundle minimum version 1.1.30327.81 not installed...downloading version 1.1.30327.81"
    Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/?linkid=844461 -OutFile $env:Temp\bundle.exe
    Write-Host "Installing .NET Core Windows Server Hosting Bundle..."
    Start-Process $env:Temp\bundle.exe -Wait -ArgumentList '/quiet /install'
    net stop was /y
    net start w3svc
    Remove-Item $env:Temp\bundle.exe
}else{
    Write-Host ".NET Core Windows Server Hosting Bundle installed and meets expectations."
}

if(!(Test-Prerequisite '*CouchDB*'))
{
    #add check to see if couchdb url is reachable
    Write-Host "CouchDB not installed locally, testing to see if is installed on a remote server using $couchDbServer"
    $remoteInstallationStatus = Get-CouchDbRemoteInstallationStatus $couchDbServer 2.0.0
    if($remoteInstallationStatus -eq "NotInstalled")
    {
        Write-Host "CouchDB not installed, downloading CouchDB Version 2.1.0.0"
        Invoke-WebRequest -Uri https://dl.bintray.com/apache/couchdb/win/2.1.0/apache-couchdb-2.1.0.msi -OutFile $env:Temp\apache-couchdb-2.1.0.msi
        Write-Host "Launching CouchDB interactive installation..."
        Start-Process $env:Temp\apache-couchdb-2.1.0.msi -Wait
        Remove-Item $env:Temp\apache-couchdb-2.1.0.msi
        $couchDbServer = "http://127.0.0.1:5984"
        try{
            Invoke-RestMethod -Method Put -Uri "$couchDbServer/_node/couchdb@localhost/_config/admins/$couchDbUsername" -Body "`"$couchDbPassword`""
        } catch{
            $exception = $_.Exception
            Write-Host "Failed to create admin user for CouchDB. Exception $exception"
        }

    }elseif($remoteInstallationStatus -eq "MinVersionNotMet"){
        Write-Host "CouchDB is installed on $couchDbServer but does not meet the minimum version requirements, you must have CouchDB 2.0.0.1 or greater installed: https://dl.bintray.com/apache/couchdb/win/2.1.0/apache-couchdb-2.1.0.msi"
        exit 1
    }else{
        Write-Host "CouchDB installed and meets specifications"
    }
}elseif (!(Test-Prerequisite '*CouchDB*' 2.0.0.1)) {
    Write-Host "CouchDB is installed but does not meet the minimum version requirements, you must have CouchDB 2.0.0.1 or greater installed: https://dl.bintray.com/apache/couchdb/win/2.1.0/apache-couchdb-2.1.0.msi"
    exit 1
}else{
    Write-Host "CouchDB installed and meets specifications"
}

$identityServerUrl = "$hostUrl/identity"

$identityZipPackage = Get-FabricRelease Identity $identityVersion
$identityArgs = Get-CommonArguments
$identityArgs += ("-zipPackage", $identityZipPackage)
$identityArgs += ("-hostUrl", $hostUrl)
Install-FabricRelease Identity $identityArgs
Remove-Item $identityZipPackage -Force

Set-Location $workingDirectory

$authorizationZipPackage = Get-FabricRelease Authorization $authorizationVersion
$authorizationArgs = Get-CommonArguments
$authorizationArgs += ("-zipPackage", $authorizationZipPackage)
$authorizationArgs += ("-identityServerUrl", $identityServerUrl)
Install-FabricRelease Authorization $authorizationArgs
Remove-Item $authorizationZipPackage -Force

Set-Location $workingDirectory

if(Test-RegistrationComplete $identityServerUrl)
{
    Write-Host "Installation complete, exiting."
    Remove-Item .\Fabric-Install-Utilities.psm1
    exit 0
}

#Register registration api
$body = @'
{
    "name":"registration-api",
    "userClaims":["name","email","role","groups"],
    "scopes":[{"name":"fabric/identity.manageresources"}]
}
'@

Write-Host "Registering Fabric.Identity registration api."
$registrationApiSecret = Add-ApiRegistration -authUrl $identityServerUrl -body $body

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

Write-Host "Registering Fabric.Installer."
$installerClientSecret = Add-ClientRegistration -authUrl $identityServerUrl -body $body

$accessToken = Get-AccessToken -authUrl $identityServerUrl -clientId "fabric-installer" -scope "fabric/identity.manageresources" -secret $installerClientSecret

#Register authorization api
$body = @'
{
    "name":"authorization-api",
    "userClaims":["name","email","role","groups"],
    "scopes":[{"name":"fabric/authorization.read"}, {"name":"fabric/authorization.write"}, {"name":"fabric/authorization.manageclients"}]
}
'@

Write-Host "Registering Fabric.Authorization."
$authorizationApiSecret = Add-ApiRegistration -authUrl $identityServerUrl -body $body -accessToken $accessToken

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

Write-Host "Registering Fabric.GroupFetcher."
$groupFetcherSecret = Add-ClientRegistration -authUrl $identityServerUrl -body $body -accessToken $accessToken

Write-Host "Please keep the following secrets in a secure place:"
Write-Host "Fabric.Installer clientSecret: $installerClientSecret"
Write-Host "Fabric.GroupFetcher clientSecret: $groupFetcherSecret"
Write-Host "Fabric.Authorization apiSecret: $authorizationApiSecret"
Write-Host "Fabric.Registration apiSecret: $registrationApiSecret"
Write-Host ""
Write-Host "The Fabric.Installer clientSecret will be needed in subsequent installations:"
Write-Host "Fabric.Installer clientSecret: $installerClientSecret"

Remove-Item .\Fabric-Install-Utilities.psm1
Write-Host "Installation complete, exiting."

  