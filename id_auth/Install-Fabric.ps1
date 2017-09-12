param(
    [String]$identityVersion,
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

Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/common/Fabric-Install-Utilities.psm1 -OutFile Fabric-Install-Utilities.psm1
Import-Module -Name .\Fabric-Install-Utilities.psm1 -Verbose
Add-Type -AssemblyName System.IO.Compression.FileSystem


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
    Write-Host "CouchDB not installed, installing CouchDB Version 2.1.0.0"
    Invoke-WebRequest -Uri https://dl.bintray.com/apache/couchdb/win/2.1.0/apache-couchdb-2.1.0.msi -OutFile $env:Temp\apache-couchdb-2.1.0.msi
    Start-Process $env:Temp\apache-couchdb-2.1.0.msi -Wait
    Remove-Item $env:Temp\apache-couchdb-2.1.0.msi
}elseif (!(Test-Prerequisite '*CouchDB*' 2.0.0.1)) {
    Write-Host "CouchDB is installed but does not meet the minimum version requirements, you must have CouchDB 2.0.0.1 or greater installed: https://dl.bintray.com/apache/couchdb/win/2.1.0/apache-couchdb-2.1.0.msi"
    exit 1
}

$outFile = "$env:Temp\Fabric.Identity.$identityVersion.zip"
$targetDirectory = "$env:Temp\Fabric.Identity.$identityVersion"
Write-Host "Downloading Fabric.Identity.$identityVersion.zip to $outFile"
if(Test-Path $targetDirectory){
    Remove-Item $targetDirectory -Force -Recurse
}
Invoke-WebRequest -Uri https://github.com/HealthCatalyst/Fabric.Identity/releases/download/v$identityVersion/Fabric.Identity.$identityVersion.zip -OutFile $outFile
[System.IO.Compression.ZipFile]::ExtractToDirectory($outFile, $targetDirectory)

Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/Fabric.Identity/master/Fabric.Identity.API/scripts/Install-Identity-Windows.ps1 -OutFile $env:Temp\Install-Identity-Windows.ps1
$args = @()
$args += ("-zipPackage", "$targetDirectory\drop\Fabric.Identity.Api.zip")
$args += ("-sslCertificateThumbprint", $sslCertificateThumbprint)
$args += ("-couchDbServer", $couchDbServer)
$args += ("-couchDbUsername", $couchDbUsername)
$args += ("-couchDbPassword", $couchDbPassword)
$args += ("-appInsightsInstrumentationKey", $appInsightsInstrumentationKey)
$args += ("-hostUrl", $hostUrl)
if($webroot){
    $args += ("-webroot", $webroot)
}
if($iisUser){
    $args += ("-iisUser", $iisUser)
}
Invoke-Expression "$env:Temp\Install-Identity-Windows.ps1 $args"

  