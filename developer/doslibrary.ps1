

# You can run this by pasting the following in powershell
# Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/developer/doslibrary.ps1 | Invoke-Expression;

Write-output "--- doslibrary.ps1 Version 2018.04.24.01 ----"

$dpsUrl = "http://localhost/DataProcessingService"
$metadataUrl = "http://localhost/MetadataService" 

$ewSepsisDataMartName = "Early Warning Sepsis Risk"
$ewSepsisEntityName = "EWSSummaryPatientRisk"

$connectionString = "Server=(local);Database=EdwAdmin;Trusted_Connection=True;"

# http://localhost/MetadataService/swagger/ui/index#/
function listdatamarts() {
    $api = "${metadataUrl}/v1/DataMarts"
    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    Write-Host "Datamarts"
    ForEach ($def in $result.value) {
        Write-Host "$($def.Id) $($def.Name)"
    }
}

function getdataMartIDbyName($datamartName) {
    [hashtable]$Return = @{} 

    $api = "${metadataUrl}/v1/DataMarts" + '?$filter=Name eq ' + "'$datamartName'"
    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    

    $Return.Id = $result.value.Id
    $Return.Name = $result.value.Name

    Write-Host "Found datamart id=$($Return.Id) for $datamartName"
    
    return $Return
}
function downloaddataMartIDbyName([ValidateNotNull()] $datamartName) {
    [hashtable]$Return = @{} 

    $result = $(getdataMartIDbyName $datamartName)
    $datamartId = $result.Id

    $api = "${metadataUrl}/v1/DataMarts($datamartId)" + '?$expand=Entities($expand=SourceBindings)'
    $result = Invoke-Restmethod $api -UseDefaultCredentials 

    Write-Host $result
    $file = "c:\himss\sepsis\mysam.json"
    $result | ConvertTo-Json | Out-File $file

    Write-Host "Wrote datamart json to $file"
    
    # notepad.exe $file
    return $Return
}

# EWSSummaryPatientRisk
# http://localhost/MetadataService/v1/DataMarts(24)/Entities(1427)/SourceBindings

function getIdForEntity([ValidateNotNull()] $datamartid, [ValidateNotNull()] $entityname) {
    [hashtable]$Return = @{} 

    $api = "${metadataUrl}/v1/DataMarts($datamartId)/Entities" + '?$filter=EntityName eq ' + "'$entityname'"
    $result = Invoke-Restmethod $api -UseDefaultCredentials 

    # Write-Host $result
    $Return.EntityId = $result.value.Id
    return $Return    
}

function getBinding([ValidateNotNull()] $datamartid, [ValidateNotNull()] $entityId) {
    # http://localhost/MetadataService/v1/DataMarts(24)/Entities(1427)/SourceBindings
    [hashtable]$Return = @{} 

    $api = "${metadataUrl}/v1/DataMarts($datamartid)/Entities($entityId)/SourceBindings" + '?$expand=AttributeValues'
    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    
    Write-Host "Binding: $($result.value)"
    $Return.Binding = $($result.value)
    return $Return    
}

function getIdForBinding([ValidateNotNull()] $datamartid, [ValidateNotNull()] $entityId) {
    # http://localhost/MetadataService/v1/DataMarts(24)/Entities(1427)/SourceBindings
    [hashtable]$Return = @{} 

    $api = "${metadataUrl}/v1/DataMarts($datamartid)/Entities($entityId)/SourceBindings"
    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    
    Write-Host "Binding: $result.value"
    $Return.BindingId = $result.value.Id
    return $Return    
}

function updateBindingType([ValidateNotNull()] $datamartid, [ValidateNotNull()] $entityId, [ValidateNotNull()] $bindingId, [ValidateNotNull()] $bindingType) {
    # /v1/DataMarts({dataMartId})/Entities({entityId})/SourceBindings({id})
    [hashtable]$Return = @{} 

    $api = "${metadataUrl}/v1/DataMarts($datamartid)/Entities($entityId)/SourceBindings($bindingId)"  
    $body = @{
        BindingType = "$bindingType"
    }
    $bodyAsJson = $body | ConvertTo-Json
    $headerJSON = @{ "content-type" = "application/json;odata=verbose"}

    Write-Host "API: $api"
    Write-Host "Body: $bodyAsJson"

    Invoke-RestMethod -Uri $api -UseDefaultCredentials `
        -Headers $headerJSON -Method PATCH `
        -Body $bodyAsJson    
    
    Invoke-Restmethod $api -UseDefaultCredentials 
    return $Return    

}

function setAttributeInBinding([ValidateNotNull()] $datamartid, [ValidateNotNull()] $entityId, [ValidateNotNull()] $bindingId, $attributeName, $attributeValue) {
    # POST /v1/DataMarts({dataMartId})/Entities({entityId})/SourceBindings({bindingId})/AttributeValues

    # see if binding exists
    $api = "${metadataUrl}/v1/DataMarts($datamartid)/Entities($entityId)/SourceBindings($bindingId)/AttributeValues" + '?$filter=AttributeName eq ' + "'$attributeName'"
    $result = Invoke-Restmethod $api -UseDefaultCredentials 

    $bodyAsJson = "{
        'AttributeName': '$attributeName',
        'AttributeValue': '$attributeValue'
      }"
    $headerJSON = @{ "content-type" = "application/json;odata=verbose"}

    # if result is null then add else patch
    if ($($result.value) -eq $null) {
        Write-Host "Attribute $attributeName does not exist, adding it"
        $api = "${metadataUrl}/v1/DataMarts($datamartid)/Entities($entityId)/SourceBindings($bindingId)/AttributeValues"  

        Invoke-RestMethod -Uri $api -UseDefaultCredentials `
            -Headers $headerJSON -Method POST `
            -Body $bodyAsJson    
    }
    else {
        $attributeId = $($result.value.Id)
        Write-Host "Attribute $attributeName already exists with id: $attributeId so patching it"
        $api = "${metadataUrl}/v1/DataMarts($datamartid)/Entities($entityId)/SourceBindings($bindingId)/AttributeValues($attributeId)"  
        
        Invoke-RestMethod -Uri $api -UseDefaultCredentials `
            -Headers $headerJSON -Method PATCH `
            -Body $bodyAsJson    
    }
}

function setBindingTypeForPatientRisk($bindingType, $scriptFile) {
    $datamartName = $ewSepsisDataMartName
    $entityname = $ewSepsisEntityName
    $result = $(getdataMartIDbyName $datamartName)
    $datamartId = $result.Id

    $entityId = $(getIdForEntity $datamartid $entityname).EntityId
    $bindingId = $(getIdForBinding $datamartid $entityId).BindingId

    Write-Host "Updating binding type to R"

    setAttributeInBinding $datamartid $entityId $bindingId "Script" $scriptFile 

    updateBindingType $datamartid $entityId $bindingId $bindingType

}
function showBindingForPatientRisk() {

    [hashtable]$Return = @{} 

    $datamartName = $ewSepsisDataMartName
    $entityname = $ewSepsisEntityName
    $result = $(getdataMartIDbyName $datamartName)
    $datamartId = $result.Id

    $entityId = $(getIdForEntity $datamartid $entityname).EntityId
    # $bindingId = $(getIdForBinding $datamartid $entityId).BindingId

    

    $Return.Binding = $(getBinding $datamartId $entityId).Binding

    return $Return
}


function listBatchDefinitions() {
    $api = "${dpsUrl}/v1/BatchDefinitions"
    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    # Write-Host $result.value
    Write-Host "Batch Definitions"
    ForEach ($def in $result.value) {
        Write-Host "$($def.Id) $($def.DataMartId) $($def.DataMartName) $($def.LastRunStats) $($def.LastRunDateTime)"
    }
}

function createNewBatchDefinition([ValidateNotNull()] $datamartId, [ValidateNotNull()] $datamartName) {

    [hashtable]$Return = @{} 

    # create a new batch definition
    $api = "${dpsUrl}/v1/BatchDefinitions"
    $body = @{
        Id           = -1
        DataMartId   = $datamartId
        Name         = "$datamartName"
        Status       = "Active"
        LoadType     = "All"
        EmailFrom    = "imran.qureshi@healthcatalyst.com"
        EmailTo      = "imran.qureshi@healthcatalyst.com"
        LoggingLevel = "Minimal"
        PipelineType = "Batch"
    }
    # $accessTokenResponse = Invoke-RestMethod -Method Post -Uri $url -Body $body
    $result = Invoke-RestMethod -Uri $api -UseDefaultCredentials -Method POST -Body $body

    $batchDefinitionId = $result.Id
    Write-Host "batchdefinitionId = $batchDefinitionId"

    $Return.BatchDefinitionId = $batchDefinitionId
    return $Return      
}

function getBatchDefinitionForDataMart([ValidateNotNull()] $dataMartId) {
    [hashtable]$Return = @{} 

    $api = "${dpsUrl}" + '/v1/BatchDefinitions?$filter=DataMartId eq ' + $dataMartId

    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    # Write-Host $result

    if ($result.value.Count -eq 0) {
        # no definitions found
        Write-Host "No definitions found"
    }
    else {
        $lastExecution = $($result.value | Sort-Object CreationDateTime -Descending)[0]
        $batchDefinitionId = $lastExecution.Id
        # Write-Host $lastExecution
        Write-Host "batchdefinitionId = $batchDefinitionId"
    
        $Return.BatchDefinitionId = $batchDefinitionId
    }
    return $Return  
}

function getLastBatchExecutionForDatamart([ValidateNotNull()] $dataMartId) {
    [hashtable]$Return = @{} 

    $api = "${dpsUrl}" + '/v1/BatchExecutions?$filter=DataMartId eq ' + $dataMartId

    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    # Write-Host $result.value
    # $batchDefinitionId = $result.value[0].BatchDefinitionId

    $lastExecution = $($result.value | Sort-Object CreationDateTime -Descending)[0]
    $batchExecutionId = $lastExecution.Id
    $batchDefinitionId = $lastExecution.BatchDefinitionId
    $status = $lastExecution.Status
    $startDateTime = $lastExecution.StartDateTime
    $endDateTime = $lastExecution.EndDateTime


    # Write-Host $lastExecution
    Write-Host "batchExecutionId: $batchExecutionId"
    Write-Host "batchdefinitionId = $batchDefinitionId"
    Write-Host "Status: $status"
    Write-Host "Start: $startDateTime"
    Write-Host "End: $endDateTime"

    $Return.BatchExecutionId = $batchExecutionId
    $Return.BatchDefinitionId = $batchDefinitionId
    $Return.Status = $status
    $Return.StartDateTime = $startDateTime
    $Return.EndDateTime = $endDateTime
    return $Return  
}

function getBatchExecution([ValidateNotNull()] $batchExecutionId) {
    [hashtable]$Return = @{} 

    $api = "${dpsUrl}/v1/BatchExecutions($batchExecutionId)"

    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    # Write-Host $result
    # $batchDefinitionId = $result.value[0].BatchDefinitionId

    $lastExecution = $($result)
    $batchDefinitionId = $lastExecution.BatchDefinitionId
    $status = $lastExecution.Status
    $startDateTime = $lastExecution.StartDateTime
    $endDateTime = $lastExecution.EndDateTime

    # Write-Host $lastExecution
    # Write-Host "batchdefinitionId = $batchDefinitionId"
    # Write-Host "Status: $status"
    # Write-Host "Start: $startDateTime"
    # Write-Host "End: $endDateTime"

    $Return.BatchDefinitionId = $batchDefinitionId
    $Return.Status = $status
    $Return.StartDateTime = $startDateTime
    $Return.EndDateTime = $endDateTime
    return $Return  
}

function waitForBatchExecution([ValidateNotNull()] $batchExecutionId) {
    [hashtable]$Return = @{} 

    Do {
        $result = getBatchExecution($batchExecutionId)
        $status = $result.Status
        Write-Host "Status: $status"
        Start-Sleep -Seconds 1
    }
    while ($status -ne "Succeeded" -and $status -ne "Failed" -and $status -ne "Canceled")

    $Return.Status = $status
    return $Return      
}

function executeBatch([ValidateNotNull()] $batchdefinitionId) {
    [hashtable]$Return = @{} 

    #then execute the batch definiton
    $api = "${dpsUrl}/v1/BatchExecutions"
    $body = @{
        BatchDefinitionId = $batchDefinitionId
        Status            = "Queued"
        PipelineType      = "Batch"
        LoggingLevel      = "Diagnostic"
        # LoadType          = "All"
        # OverrideLoadType  = "Full"
    }
    $result = Invoke-RestMethod -Uri $api -UseDefaultCredentials -Method POST -Body $body

    $batchExecutionId = $result.Id
    Write-Host "Batch execution id=$batchExecutionId"

    $Return.BatchExecutionId = $batchExecutionId
    return $Return  
}
function executeBatchAsStreaming([ValidateNotNull()] $batchdefinitionId) {
    [hashtable]$Return = @{} 

    #then execute the batch definiton
    $api = "${dpsUrl}/v1/BatchExecutions"
    $body = @{
        BatchDefinitionId = $batchDefinitionId
        Status            = "Queued"
        PipelineType      = "Streaming"
        LoggingLevel      = "Diagnostic"
        # LoadType          = "All"
        # OverrideLoadType  = "Full"
    }
    $result = Invoke-RestMethod -Uri $api -UseDefaultCredentials -Method POST -Body $body

    $batchExecutionId = $result.Id
    Write-Host "Batch execution id=$batchExecutionId"

    $Return.BatchExecutionId = $batchExecutionId
    return $Return  
}

function cancelBatch([ValidateNotNull()] $batchExecutionId) {
    [hashtable]$Return = @{} 

    #then execute the batch definiton
    $api = "${dpsUrl}/v1/BatchExecutions($batchExecutionId)"
    $body = @{
        Status = "Canceling"
    }
    $bodyAsJson = $body | ConvertTo-Json
    $headerJSON = @{ "content-type" = "application/json;odata=verbose"}
    $result = Invoke-RestMethod -Uri $api -UseDefaultCredentials `
        -Headers $headerJSON -Method PATCH `
        -Body $bodyAsJson

    $batchExecutionId = $result.Id
    Write-Host "Batch execution id=$batchExecutionId"

    $Return.BatchExecutionId = $batchExecutionId
    return $Return  
}

function executeJsonDataMart($file) {
    [hashtable]$Return = @{} 

    $api = "${dpsUrl}/v1/ExecuteDataMart"
    $body = Get-Content $file -Raw
    $result = Invoke-RestMethod -Uri $api -UseDefaultCredentials -Method POST -Body $body -ContentType 'application/json'

    $batchExecutionId = $result.value.Id
    Write-Host "Batch execution id=$batchExecutionId"

    $Return.BatchExecutionId = $batchExecutionId
    return $Return  
}

function createBatchDefinitionForDataMart([ValidateNotNull()] $datamartName) {

    $result = $(getdataMartIDbyName $datamartName)
    $datamartId = $result.Id
    $batchDefinitionId = $(getBatchDefinitionForDataMart $datamartId).BatchDefinitionId
    if ($batchDefinitionId -eq $null) {
        Write-Host "Creating batch definition for datamart $datamartName with Id: $datamartId"
        createNewBatchDefinition -datamartId $datamartId -datamartName $datamartName
    }
    else {
        Write-Host "Batch definition already found for datamart $datamartName with Id: $datamartId"
    }
    
}

function createBatchDefinitions() {
    createBatchDefinitionForDataMart -datamartName "HL7Demo"

    createBatchDefinitionForDataMart -datamartName "SharedPersonSourcePatient"
    createBatchDefinitionForDataMart -datamartName "SharedPersonSourceProvider"
    createBatchDefinitionForDataMart -datamartName "SharedPersonProvider"
    createBatchDefinitionForDataMart -datamartName "SharedPersonPatient"
    createBatchDefinitionForDataMart -datamartName "SharedClinical"
    createBatchDefinitionForDataMart -datamartName "Sepsis"
    createBatchDefinitionForDataMart -datamartName "Hospital Account to Facility Account"
    
    createBatchDefinitionForDataMart -datamartName "Early Warning Sepsis Risk"
}

function runAndWaitForDatamart([ValidateNotNull()] $datamartName) {
    [hashtable]$Return = @{} 

    $result = $(getdataMartIDbyName $datamartName)
    $datamartId = $result.Id

    $batchdefinitionId = $(getBatchDefinitionForDataMart -dataMartId $datamartId).BatchDefinitionId
    Write-Host "Running batch definition $batchdefinitionId for datamart $datamartName id: $datamartId"
    $batchExecutionId = $(executeBatch -batchdefinitionId $batchdefinitionId).BatchExecutionId
    $status = $(waitForBatchExecution -batchExecutionId $batchExecutionId).Status

    $Return.Status = $status
    return $Return
}

function runSharedTerminologyDataMarts() {
    $result = runAndWaitForDatamart -datamartName "Terminology Normalize View"
    if ($($result.Status) -ne "Succeeded") {return; }

}

function runSharedDataMarts() {
    $result = runAndWaitForDatamart -datamartName "SharedPersonSourceProvider"
    if ($($result.Status) -ne "Succeeded") {return; }
    $result = runAndWaitForDatamart -datamartName "SharedPersonSourcePatient"
    if ($($result.Status) -ne "Succeeded") {return; }
    $result = runAndWaitForDatamart -datamartName "SharedPersonProvider"
    if ($($result.Status) -ne "Succeeded") {return; }
    $result = runAndWaitForDatamart -datamartName "SharedPersonPatient"
    if ($($result.Status) -ne "Succeeded") {return; }
    $result = runAndWaitForDatamart -datamartName "SharedClinical"
    if ($($result.Status) -ne "Succeeded") {return; }
}

function runEarlyWarningSepsis() {

    $StartDateTime = Get-Date
    $result = runAndWaitForDatamart -datamartName "Early Warning Sepsis Risk"   
    $EndDateTime = Get-Date 
    $duration = $EndDateTime - $StartDateTime
    Write-Host "Runtime in seconds: $($duration.TotalSeconds)"
    if ($($result.Status) -ne "Succeeded") {return; }  
}

function runSepsis() {

    $result = runAndWaitForDatamart -datamartName "Hospital Account to Facility Account"
    if ($($result.Status) -ne "Succeeded") {return; }

    $result = runAndWaitForDatamart -datamartName "Sepsis"
    if ($($result.Status) -ne "Succeeded") {return; }

    $result = runAndWaitForDatamart -datamartName "Early Warning Sepsis Risk"    
    if ($($result.Status) -ne "Succeeded") {return; }    
}

function runHL7Sourcemart() {
    $datamartName = "HL7Demo"
    $result = $(getdataMartIDbyName $datamartName)
    $datamartId = $result.Id

    $batchdefinitionId = $(getBatchDefinitionForDataMart -dataMartId $datamartId).BatchDefinitionId
    Write-Host "Running batch definition $batchdefinitionId for datamart $datamartName id: $datamartId"
    $(executeBatchAsStreaming -batchdefinitionId $batchdefinitionId).BatchExecutionId
}
function runSql([ValidateNotNull()][string] $sql) {
#    Invoke-Sqlcmd -Query $sql -ConnectionString $connectionString
    Invoke-Sqlcmd -Query $sql -Database "EdwAdmin"

}

function downloadCerts() {
    $url = "http://localhost:8081/client/fabricrabbitmquser_client_cert.p12"
    Write-Host "Download: $url"
    Write-Host "Double-click and install in Local Machine. password: roboconf2"
    Write-Host "Open Certificate Management, right click on cert and give everyone access to key"
    $url = "http://localhost:8081/client/fabric_ca_cert.p12"
}
function createNodeUserOnSqlDatabase() {
    # https://docs.microsoft.com/en-us/powershell/module/sqlserver/invoke-sqlcmd?view=sqlserver-ps

    $sql = 
    @"
IF NOT EXISTS 
    (SELECT name  
     FROM master.sys.server_principals
     WHERE name = 'nodeuser')
BEGIN
CREATE LOGIN [nodeuser] WITH PASSWORD=N'ILoveNode2017', DEFAULT_DATABASE=[SAM], DEFAULT_LANGUAGE=[us_english], CHECK_EXPIRATION=ON, CHECK_POLICY=ON
END
"@
    runSql -Query $sql -ConnectionString $connectionString -Verbose
    $sql = 
    @"
USE [SAM];
GO
CREATE USER [nodeuser] FOR LOGIN [nodeuser]
GO
"@
    runSql -sql $sql -Verbose
    $sql = 
    @"
USE [SAM];
GO
exec sp_addrolemember 'db_datareader', 'nodeuser';
GO
"@
    runSql -sql $sql -Verbose
}

function runFabricEHRDocker() {
    docker run -d --rm -p 3000:3000 --name fabric.ehr healthcatalyst/fabric.ehr
}

function startFabricEHRNodeJs() {
}

function showDiscoveryServiceUrls() {
    $sql = "SELECT [ServiceNM],[ServiceUrl] FROM [EDWAdmin].[CatalystAdmin].[DiscoveryServiceBASE]"
    runSql -sql $sql    
}

function showUserPermissions() {
    $sql =
    @"
    select ib.IdentityID, ib.IdentityNM, rb.RoleID
    from [EDWAdmin].[CatalystAdmin].[IdentityRoleBASE] rb
    inner join [EDWAdmin].[CatalystAdmin].[IdentityBASE] ib
    on rb.IdentityID = ib.IdentityID
    ORDER BY ib.IdentityID    
"@

    $rows = runSql -sql $sql

    foreach ($row in $rows) {
        Write-Host $row
    }
}

function setETLObjectAttribute($attributeName, $attributeValueTXT, $attributeValueNBR){
    [hashtable]$Return = @{} 

    $sql =
@"
IF NOT EXISTS(SELECT 1 FROM [EDWAdmin].[CatalystAdmin].[ETLObjectAttributeBASE] WHERE [AttributeNM] = '$attributeName')
BEGIN
	INSERT INTO [EDWAdmin].[CatalystAdmin].[ETLObjectAttributeBASE]([ObjectID], [ObjectTypeCD],[AttributeNM],[AttributeValueTXT],[AttributeValueNBR])
	VALUES(0, 'System', '$attributeName','$attributeValueTXT',$attributeValueNBR)
END
ELSE
BEGIN
	UPDATE [EDWAdmin].[CatalystAdmin].[ETLObjectAttributeBASE]
	SET [AttributeValueTXT] = '$attributeValueTXT', [AttributeValueNBR]=$attributeValueNBR
	WHERE [AttributeNM] = '$attributeName'
END
"@
    # Write-Host $sql
    runSql $sql

    return $Return
}

function setETLObjectAttributeText($attributeName, $attributeValueTXT){
    [hashtable]$Return = @{} 

    setETLObjectAttribute "$attributeName" "$attributeValueTXT" "NULL"
    Write-Host "setETLObjectAttributeText: '$attributeName' '$attributeValueTXT'"

    return $Return
}
function setETLObjectAttributeNumber($attributeName, $attributeValueNBR){
    [hashtable]$Return = @{} 

    setETLObjectAttribute "$attributeName" "NULL" $attributeValueNBR
    Write-Host "setETLObjectAttributeNumber: '$attributeName' $attributeValueNBR"

    return $Return
}

function listWebSites() {
    # https://octopus.com/blog/iis-powershell
    Get-Website
}

Function DeployDACPAC {
    # http://www.systemcentercentral.com/deploying-sql-dacpac-t-sql-script-via-powershell/ 
    param( 
        [string]$sqlserver = $( throw "Missing required parameter sqlserver"), 
        [string]$dacpac = $( throw "Missing required parameter dacpac"), 
        [string]$dbname = $( throw "Missing required parameter dbname") )
     
    Write-Host "Deploying the DB with the following settings" 
    Write-Host "sqlserver:   $sqlserver" 
    Write-Host "dacpac: $dacpac" 
    Write-Host "dbname: $dbname"
     
    # load in DAC DLL, This requires config file to support .NET 4.0.
    # change file location for a 32-bit OS 
    #make sure you
    add-type -path "C:\Program Files (x86)\Microsoft SQL Server\110\DAC\bin\Microsoft.SqlServer.Dac.dll"
     
    # Create a DacServices object, which needs a connection string 
    $dacsvcs = new-object Microsoft.SqlServer.Dac.DacServices "server=$sqlserver"
     
    # register event. For info on this cmdlet, see http://technet.microsoft.com/en-us/library/hh849929.aspx 
    register-objectevent -in $dacsvcs -eventname Message -source "msg" -action { out-host -in $Event.SourceArgs[1].Message.Message } | Out-Null
     
    # Load dacpac from file & deploy database
    $dp = [Microsoft.SqlServer.Dac.DacPackage]::Load($dacpac) 
    $dacsvcs.Deploy($dp, $dbname, $true) 
     
    # clean up event 
    unregister-event -source "msg" 
     
}

function foo() {
    # https://docs.microsoft.com/en-us/sql/relational-databases/data-tier-applications/deploy-a-data-tier-application
    
    ## Set a SMO Server object to the default instance on the local computer.  
    Set-Location SQLSERVER:\SQL\localhost\DEFAULT  
    $srv = get-item .  

    ## Open a Common.ServerConnection to the same instance.  
    $serverconnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection($srv.ConnectionContext.SqlConnectionObject)  
    $serverconnection.Connect()  
    $dacstore = New-Object Microsoft.SqlServer.Management.Dac.DacStore($serverconnection)  

    ## Load the DAC package file.  
    $dacpacPath = "C:\MyDACs\MyApplication.dacpac"  
    $fileStream = [System.IO.File]::Open($dacpacPath, [System.IO.FileMode]::OpenOrCreate)  
    $dacType = [Microsoft.SqlServer.Management.Dac.DacType]::Load($fileStream)  

    ## Subscribe to the DAC deployment events.  
    $dacstore.add_DacActionStarted( {Write-Host `n`nStarting at $(get-date) :: $_.Description})  
    $dacstore.add_DacActionFinished( {Write-Host Completed at $(get-date) :: $_.Description})  

    ## Deploy the DAC and create the database.  
    $dacName = "MyApplication"  
    $evaluateTSPolicy = $true  
    $deployProperties = New-Object Microsoft.SqlServer.Management.Dac.DatabaseDeploymentProperties($serverconnection, $dacName)  
    $dacstore.Install($dacType, $deployProperties, $evaluateTSPolicy)  
    $fileStream.Close()      
}


# https://blog.ehn.nu/2016/01/downloading-build-artifacts-in-tfs-build-vnext/
function downloadArtifactFromLatestBuild() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $True)]
        [string]$buildDefinitionName,
        [Parameter()]
        [string]$artifactDestinationFolder = $Env:BUILD_STAGINGDIRECTORY,
        [Parameter()]
        [switch]$appendBuildNumberVersion = $false
    )

    # buildDefinitionName
    # This is a mandatory parameter where you can specify the name of the build definition from which you want to download the artifacts from. 
    # This script assumes that the build definition is located in the same team project as the build definition in which this script is running. 
    # If this is not the case, you need to add a parameter for the team project.
    Write-Verbose -Verbose ('buildDefinitionName: ' + $buildDefinitionName)
    # artifactsDestinationFolder
    # This is an optional parameter that let’s you specify the folder where the artifacts should be downloaded to. If you leave it empty, 
    # it will be downloaded to the staging directory of the build (BUILD_STAGINGDIRECTORY)        
    Write-Verbose -Verbose ('artifactDestinationFolder: ' + $artifactDestinationFolder)
    Write-Verbose -Verbose ('appendBuildNumberVersion: ' + $appendBuildNumberVersion)
    
    # appendBuildNumberVersion
    # A switch that indicates if you want to append the version number of the linked build to the build number of the running build. 
    # Since you are actually releasing the build version that you are downloading artifacts from, it often makes sense to use this version number for the
    #  deployment build. The script will extract a 4 digit version (x.x.x.x) from the build number and then append it to the build number of the running build.
    $tfsUrl = $Env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI + $Env:SYSTEM_TEAMPROJECT
    
    $buildDefinitions = Invoke-RestMethod -Uri ($tfsURL + '/_apis/build/definitions?api-version=2.0&name=' + $buildDefinitionName) -Method GET -UseDefaultCredentials
    $buildDefinitionId = ($buildDefinitions.value).id;
        
    $tfsGetLatestCompletedBuildUrl = $tfsUrl + '/_apis/build/builds?definitions=' + $buildDefinitionId + '&statusFilter=completed&resultFilter=succeeded&$top=1&api-version=2.0'
    
    $builds = Invoke-RestMethod -Uri $tfsGetLatestCompletedBuildUrl -Method GET -UseDefaultCredentials
    $buildId = ($builds.value).id;
    
    if ( $appendBuildNumberVersion) {
        $buildNumber = ($builds.value).buildNumber
        $versionRegex = "\d+\.\d+\.\d+\.\d+"
    
        # Get and validate the version data
        $versionData = [regex]::matches($buildNumber, $versionRegex)
        switch ($versionData.Count) {
            0 { 
                Write-Error "Could not find version number data in $buildNumber."
                exit 1
            }
            1 {}
            default { 
                Write-Warning "Found more than instance of version data in buildNumber." 
                Write-Warning "Will assume first instance is version."
            }
        }
        $buildVersionNumber = $versionData[0]
        $newBuildNumber = $Env:BUILD_BUILDNUMBER + $buildVersionNumber
        Write-Verbose -Verbose "Version: $newBuildNumber"
        Write-Verbose -Verbose "##vso[build.updatebuildnumber]$newBuildNumber"
    }
    
    $dropArchiveDestination = Join-path $artifactDestinationFolder "drop.zip"
    
    
    #build URI for buildNr
    $buildArtifactsURI = $tfsURL + '/_apis/build/builds/' + $buildId + '/artifacts?api-version=2.0'
        
    #get artifact downloadPath
    $artifactURI = (Invoke-RestMethod -Uri $buildArtifactsURI -Method GET -UseDefaultCredentials).Value.Resource.downloadUrl
    
    #download ZIP
    Invoke-WebRequest -uri $artifactURI -OutFile $dropArchiveDestination -UseDefaultCredentials
    
    #unzip
    Add-Type -assembly 'system.io.compression.filesystem'
    [io.compression.zipfile]::ExtractToDirectory($dropArchiveDestination, $artifactDestinationFolder)
    
    Write-Verbose -Verbose ('Build artifacts extracted into ' + $Env:BUILD_STAGINGDIRECTORY)    
}

function global:startDockerService(){
    # net start "com.docker.service"
    # "C:\Program Files\Docker\Docker\Docker for Windows.exe"
}