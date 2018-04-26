

# You can run this by pasting the following in powershell
# Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/developer/runengine.ps1 | Invoke-Expression;
# Get-Content ./runengine.ps1 -Raw | Invoke-Expression;

$GITHUB_URL = "https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master"

# Invoke-WebRequest -useb ${GITHUB_URL}/developer/doslibrary.ps1 | Invoke-Expression;
Get-Content ./developer/doslibrary.ps1 -Raw | Invoke-Expression;

Write-output "--- runengine.ps1 Version 2018.03.14.01 ----"

$userinput = ""
while ($userinput -ne "q") {
    Write-Host "================ Health Catalyst Developer Tools ================"
    Write-Host "0: Setup HIMSS Demo"
    Write-Host "1: List data marts"
    Write-Host "2: List Batch definitions"
    Write-Host "3: Show Discovery Service Urls"
    Write-Host "4: Show Permissions"
    Write-Host "-----------"
    Write-Host "10: Create batch definitions"
    Write-Host "11: Run HL7 Source mart"
    Write-Host "12: Run Shared Datamarts"
    Write-Host "13: Run Shared Datamarts + Sepsis"
    Write-Host "14: Run Sepsis and EW Sepsis"
    Write-Host "15: Run EW Sepsis Only"
    Write-Host "---------------------"
    Write-Host "21: Run R datamart"
    Write-Host "22: Set binding to R on EWS datamart"
    Write-Host "23: Set binding to SQL on EWS datamart"
    Write-Host "24: Download EWS datamart as json"
    Write-Host "-------- Troubleshooting ------"
    Write-Host "31: Download RabbitMq certs"
    Write-Host "32: fix discovery service url"
    Write-Host "33: Show EWS Risk binding"
    Write-Host "34: Set Config for AI"
    Write-Host "q: Quit"
    $userinput = Read-Host "Please make a selection"
    switch ($userinput) {
        '0' {

            startDockerService
            
            runFabricEHRDocker

            createNodeUserOnSqlDatabase
        } 
        '1' {
            listdatamarts
        } 
        '2' {
            listBatchDefinitions
        } 
        '3' {
            showDiscoveryServiceUrls
        } 
        '4' {
            showUserPermissions
        } 
        '10' {
            createBatchDefinitions
        } 
        '11' {
            runHL7Sourcemart
        } 
        '12' {
            runSharedDataMarts
        } 
        '13' {
            runSharedDataMarts
            runSepsis
        } 
        '14' {
            runSepsis
            runEarlyWarningSepsis
        } 
        '15' {
            runEarlyWarningSepsis
        } 
        '21' {
            executeJsonDataMart "./datamart.json"
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
        '31' {
            downloadCerts
        } 
        '32' {
            runSql "update [EDWAdmin].[CatalystAdmin].[ObjectAttributeBASE] set AttributeValueTXT = 'http://localhost/DiscoveryService/v1' where AttributeNM = 'DiscoveryServiceUri'"
        } 
        '33' {
            $result = showBindingForPatientRisk $ewSepsisDataMartName
            Write-Host "Binding Type: $($result.Binding.BindingType)"
        } 
        '34' {
            setETLObjectAttributeText "PathToRExecutable" "C:\Program Files\R\R-3.4.3\bin\Rscript.exe"
            setETLObjectAttributeText "PathToRModelFolder" "C:/himss/R"            
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
