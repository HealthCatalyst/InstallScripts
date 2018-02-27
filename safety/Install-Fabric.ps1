param([switch]$installDatabase)

if($installDatabase){
    $dacPacPath = "C:\Program Files (x86)\Microsoft SQL Server\110\DAC\bin\SqlPackage.exe"
    if(!(Test-Path $dacPacPath))
    {
        Write-Error "SqlPackage.exe does not exist at $dacPacPath. Halting installation." -ErrorAction Stop
    }
    $databaseServer = "localhost"
    $userEnteredDatabaseServer = Read-Host  "Enter the database server name to install the databases on or accept the default [$databaseServer]"
    Write-Host ""
    if(![string]::IsNullOrEmpty($userEnteredDatabaseServer)){   
        $databaseServer = $userEnteredDatabaseServer
    }

    $identityDb = "Identity"
    $userEnteredIdentityDb = Read-Host  "Enter the Identity db name or accept the default [$identityDb]"
    Write-Host ""
    if(![string]::IsNullOrEmpty($userEnteredIdentityDb)){   
        $identityDb = $userEnteredIdentityDb
    }

    $authorizationDb = "Authorization"
    $userEnteredAuthorizationDb = Read-Host  "Enter the Authorization db name or accept the default [$authorizationDb]"
    Write-Host ""
    if(![string]::IsNullOrEmpty($userEnteredAuthorizationDb)){   
        $authorizationDb = $userEnteredAuthorizationDb
    }

    Write-Host "Deploying Fabric.Identity datbase..."
    .$dacPacPath /a:Publish /Profile:"Fabric.Identity.SqlServerIncludingTables.publish.xml" /SourceFile:"Fabric.Identity.SqlServer.dacpac" /TargetServerName:$databaseServer /TargetDatabaseName:$identityDb
    Write-Host ""

    Write-Host "Deploying Fabric.Authorization datbase..."
    .$dacPacPath /a:Publish /Profile:"Fabric.Authorization.SqlServer.publish.xml" /SourceFile:"Fabric.Authorization.SqlServer.dacpac" /TargetServerName:$databaseServer /TargetDatabaseName:$authorizationDb
    Write-Host ""
}

Write-Host "Installing Fabric.Identity..."
./Install-Identity-Windows.ps1 -noDiscoveryService
Write-Host ""

Write-Host "Installing Fabric.Authorization..."
./Install-Authorization-Windows.ps1 -noDiscoveryService
Write-Host ""

Write-Host "Registering Safety Surveillance..."
./Register-Patient-Safety.ps1
Write-Host ""

