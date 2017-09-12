Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/common/Fabric-Install-Utilities.psm1 -OutFile Fabric-Install-Utilities.psm1
Import-Module -Name .\Fabric-Install-Utilities.psm1 -Verbose

if(!(Test-Prerequisite '*.NET Core*Windows Server Hosting*' 1.1.30327.81))
{
    Write-Host "Windows Server Hosting Bundle minimum version 1.1.30327.81 not installed...installing version 1.1.30327.81"
    Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/?linkid=844461 -OutFile bundle.exe
    Start-Process bundle.exe -Wait -ArgumentList '/quiet /install'
    net stop was /y
    net start w3svc
}

if(!(Test-Prerequisite '*CouchDB*'))
{
    Write-Host "CouchDB not installed, installing CouchDB Version 2.1.0.0"
    Invoke-WebRequest -Uri https://dl.bintray.com/apache/couchdb/win/2.1.0/apache-couchdb-2.1.0.msi -OutFile apache-couchdb-2.1.0.msi
    Start-Process apache-couchdb-2.1.0.msi -Wait
}elseif (!(Test-Prerequisite '*CouchDB*' 2.0.0.1)) {
    Write-Host "CouchDB is installed but does not meet the minimum version requirements, you must have CouchDB 2.0.0.1 or greater installed: https://dl.bintray.com/apache/couchdb/win/2.1.0/apache-couchdb-2.1.0.msi"
    exit 1
}
  