# Powershell functions for DOS
This is not production ready code!  This is currently for us to use in our developer machines.

These are Powershell functions that wrap the REST APIs of MDS and v2 engine.  In addition there are functions that do some of the common developer tasks like showing permissions, logs, fixing discovery service url etc.

To bring up the main menu, just open PowerShell and paste:
`Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/3/developer/runengine.ps1 | Invoke-Expression;`

This uses a library of functions that automate some parts of DOS.  You can just pull in the library only by pasting:
`Invoke-WebRequest -useb https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/3/developer/doslibrary.ps1 | Invoke-Expression;`

Here's some of the functions available in this Powershell library:
1. List all datamarts on your system: listdatamarts
2. List all batch definitions in your system: listBatchDefinitions
3. Get ID of DataMart by Name: getdataMartIDbyName <name of datamart>
4. Create a batch definition for a datamart: createBatchDefinitionForDataMart <datamart name>
5. Get last batch execution for a datamart: getLastBatchExecutionForDatamart <datamart id>
6. Run a normal batch: executeBatch <batch definition id>
7. Run a streaming batch: executeBatchAsStreaming <batch definitinon id>
8. Cancel a batch: cancelBatch <batch execution id>
9. Execute a JSON based datamart: executeJsonDataMart <filename>
10. Run and wait for a datamart: runAndWaitForDatamart <datamart name>
11. Download the json for a data mart: downloaddataMartIDbyName <name of datamart>
  
Other helpful developer stuff:
12. Show discovery service urls: showDiscoveryServiceUrls
13. Show user permissions: showDiscoveryServiceUrls
14. set ETLObjectAttributeBASE: setETLObjectAttribute <attributeName> <attributeValueTXT> <attributeValueNBR>
15. Show websites installed on my machine: listWebSites

Not completely working yet that you can feel free to make work:
16. Deploy a dacpac: DeployDACPAC
17. Download latest build from VSO: downloadArtifactFromLatestBuild

Feel free to just check in additional helpful stuff for developers.

