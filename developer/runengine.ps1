

# You can run this by pasting the following in powershell
# Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/developer/runengine.ps1 | Invoke-Expression;

# Get-Content ./runengine.ps1 -Raw | Invoke-Expression;

$dpsUrl = "http://localhost/DataProcessingService"
$metadataUrl = "http://localhost/MetadataService" 
function listdatamarts() {
    $api = "${metadataUrl}/v1/DataMarts"
    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    Write-Host "Datamarts"
    ForEach ($def in $result.value) {
        Write-Host "$($def.Id) $($def.Name)"
    }
}

function getdataMartIDbyName([ValidateNotNull()] $datamartName){
    [hashtable]$Return = @{} 

    $api = "${metadataUrl}/v1/DataMarts" + '?$filter=Name eq ' + "'$datamartName'"
    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    

    $Return.Id = $result.value.Id
    $Return.Name = $result.value.Name

    Write-Host "Found datamart id=$($Return.Id) for $datamartName"
    
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

    $api = "${dpsUrl}" + '/v1/BatchExecutions?$filter=Id eq ' + $batchExecutionId

    $result = Invoke-Restmethod $api -UseDefaultCredentials 
    # Write-Host $result.value
    # $batchDefinitionId = $result.value[0].BatchDefinitionId

    $lastExecution = $($result.value | Sort-Object CreationDateTime -Descending)[0]
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
        Start-Sleep -Seconds 10
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

function createBatchDefinitionForDataMart([ValidateNotNull()] $datamartName){

    $result = $(getdataMartIDbyName $datamartName)
    $datamartId = $result.Id
    $batchDefinitionId = $(getBatchDefinitionForDataMart $datamartId).BatchDefinitionId
    if ($batchDefinitionId -eq $null){
        Write-Host "Creating batch definition for datamart $datamartName with Id: $datamartId"
        createNewBatchDefinition -datamartId $datamartId -datamartName $datamartName
    } else {
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
    createBatchDefinitionForDataMart -datamartName "Early Warning Sepsis"
}

function runAndWaitForDatamart([ValidateNotNull()] $datamartName){
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


function runSharedDataMarts(){
    createBatchDefinitions

    $result = runAndWaitForDatamart -datamartName "SharedPersonSourceProvider"
    if($($result.Status) -ne "Succeeded") {return;}
    $result = runAndWaitForDatamart -datamartName "SharedPersonSourcePatient"
    if($($result.Status) -ne "Succeeded") {return;}
    $result = runAndWaitForDatamart -datamartName "SharedPersonProvider"
    if($($result.Status) -ne "Succeeded") {return;}
    $result = runAndWaitForDatamart -datamartName "SharedPersonPatient"
    if($($result.Status) -ne "Succeeded") {return;}
    $result = runAndWaitForDatamart -datamartName "SharedClinical"
    if($($result.Status) -ne "Succeeded") {return;}
}

function runEarlyWarningSepsis(){
    createBatchDefinitionForDataMart -datamartName "Sepsis"
    createBatchDefinitionForDataMart -datamartName "Early Warning Sepsis"

    $result = runAndWaitForDatamart -datamartName "Early Warning Sepsis"    
    if($($result.Status) -ne "Succeeded") {return;}  
}

function runSepsis(){
    createBatchDefinitionForDataMart -datamartName "Sepsis"
    createBatchDefinitionForDataMart -datamartName "Early Warning Sepsis"
    
    $result = runAndWaitForDatamart -datamartName "Sepsis"
    if($($result.Status) -ne "Succeeded") {return;}
    $result = runAndWaitForDatamart -datamartName "Early Warning Sepsis"    
    if($($result.Status) -ne "Succeeded") {return;}    
}

$userinput = ""
while ($userinput -ne "q") {
    Write-Host "================ Health Catalyst Developer Tools ================"
    Write-Host "1: List data marts"
    Write-Host "2: List Batch definitions"
    Write-Host "-----------"
    Write-Host "11: Run Shared Datamarts"
    Write-Host "12: Run Shared Clinical + Sepsis"
    Write-Host "13: Run EW Sepsis Only"
    Write-Host "---------------------"
    Write-Host "21: Run R datamart"
    Write-Host "q: Quit"
    $userinput = Read-Host "Please make a selection"
    switch ($userinput) {
        '0' {
        } 
        '1' {
            listdatamarts
        } 
        '2' {
            listBatchDefinitions
        } 
        '11' {
            runSharedDataMarts
        } 
        '12' {
            runSharedDataMarts
            runSepsis
        } 
        '13' {
            runEarlyWarningSepsis
        } 
        '21' {
            executeJsonDataMart
        } 
        'q' {
            return
        }
    }
    $userinput = Read-Host -Prompt "Press Enter to continue or q to exit"
    if($userinput -eq "q"){
        return
    }
    [Console]::ResetColor()
    Clear-Host
}
