

# You can run this by pasting the following in powershell
# Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/developer/runengine.ps1 | Invoke-Expression;

# Get-Content ./runengine.ps1 -Raw | Invoke-Expression;
Write-output "--- runengine.ps1 Version 2018.03.04.01 ----"

$dpsUrl = "http://localhost/DataProcessingService"
$metadataUrl = "http://localhost/MetadataService" 

$ewSepsisDataMartName = "Early Warning Sepsis"
$ewSepsisEntityName = "EWSSummaryPatientRisk"
#$ewsRScriptFile = "C:\\himss\\sepsis\\test.r"
$ewsRScriptFile = "C:\\himss\\healthcareai_predictingScript_sepsisDemo_20180224.r"

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

function getdataMartIDbyName($datamartName){
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
        $attributeId=$($result.value.Id)
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
        LoadType          = "All"
        OverrideLoadType  = "Full"
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

function executeJsonDataMart() {
    [hashtable]$Return = @{} 

    $api = "${dpsUrl}/v1/ExecuteDataMart"
    $body = Get-Content ./datamart.json -Raw
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
    createBatchDefinitionForDataMart -datamartName "SharedPersonSourcePatient"
    createBatchDefinitionForDataMart -datamartName "SharedPersonSourceProvider"
    createBatchDefinitionForDataMart -datamartName "SharedPersonProvider"
    createBatchDefinitionForDataMart -datamartName "SharedPersonPatient"
    createBatchDefinitionForDataMart -datamartName "SharedClinical"
    createBatchDefinitionForDataMart -datamartName "Sepsis"
    createBatchDefinitionForDataMart -datamartName "Hospital Account to Facility Account"
    
    createBatchDefinitionForDataMart -datamartName "Early Warning Sepsis"
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
    $result = runAndWaitForDatamart -datamartName "Early Warning Sepsis"   
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

    $result = runAndWaitForDatamart -datamartName "Early Warning Sepsis"    
    if ($($result.Status) -ne "Succeeded") {return; }    
}

function runSql([ValidateNotNull()] $sql){
    Invoke-Sqlcmd -Query $sql -ConnectionString $connectionString -Verbose
}

function createNodeUserOnSqlDatabase(){
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
    Invoke-Sqlcmd -Query $sql -ConnectionString $connectionString -Verbose
    $sql = 
@"
USE [SAM];
GO
CREATE USER [nodeuser] FOR LOGIN [nodeuser]
GO
"@
    Invoke-Sqlcmd -Query $sql -ConnectionString $connectionString -Verbose
    $sql = 
@"
USE [SAM];
GO
exec sp_addrolemember 'db_datareader', 'nodeuser';
GO
"@
    Invoke-Sqlcmd -Query $sql -ConnectionString $connectionString -Verbose
}
$userinput = ""
while ($userinput -ne "q") {
    Write-Host "================ Health Catalyst Developer Tools ================"
    Write-Host "0: Setup HIMSS Demo"
    Write-Host "1: List data marts"
    Write-Host "2: List Batch definitions"
    Write-Host "-----------"
    Write-Host "10: Create batch definitions"
    Write-Host "11: Run Shared Datamarts"
    Write-Host "12: Run Shared Datamarts + Sepsis"
    Write-Host "13: Run Sepsis and EW Sepsis"
    Write-Host "14: Run EW Sepsis Only"
    Write-Host "---------------------"
    Write-Host "21: Run R datamart"
    Write-Host "22: Set binding to R on EWS datamart"
    Write-Host "23: Set binding to SQL on EWS datamart"
    Write-Host "24: Download EWS datamart as json"
    Write-Host "-------- Troubleshooting ------"
    Write-Host "32: fix discovery service url"
    Write-Host "33: Show EWS Risk binding"
    Write-Host "q: Quit"
    $userinput = Read-Host "Please make a selection"
    switch ($userinput) {
        '0' {
            createNodeUserOnSqlDatabase
        } 
        '1' {
            listdatamarts
        } 
        '2' {
            listBatchDefinitions
        } 
        '10' {
            createBatchDefinitions
        } 
        '11' {
            runSharedDataMarts
        } 
        '12' {
            runSharedDataMarts
            runSepsis
        } 
        '13' {
            runSepsis
            runEarlyWarningSepsis
        } 
        '14' {
            runEarlyWarningSepsis
        } 
        '21' {
            executeJsonDataMart
        } 
        '22' {
            setBindingTypeForPatientRisk "R" $ewsRScriptFile
        } 
        '23' {
            setBindingTypeForPatientRisk "SQL" $ewsRScriptFile
        } 
        '24' {
            downloaddataMartIDbyName $ewSepsisDataMartName
        } 
        '32' {
            runSql "update [EDWAdmin].[CatalystAdmin].[ObjectAttributeBASE] set AttributeValueTXT = 'http://localhost/DiscoveryService/v1' where AttributeNM = 'DiscoveryServiceUri'"
        } 
        '33' {
            $result = showBindingForPatientRisk $ewSepsisDataMartName
            Write-Host "Binding Type: $($result.Binding.BindingType)"
        } 
        'q' {
            return
        }
    }
    $userinput = Read-Host -Prompt "Press Enter to continue or q to exit"
    if ($userinput -eq "q") {
        return
    }
    [Console]::ResetColor()
    Clear-Host
}
