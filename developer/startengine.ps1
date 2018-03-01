

$username = "hqcatalyst\edw_loader"
$password = "P@ssw0rd"
$credentials = New-Object System.Management.Automation.PSCredential -ArgumentList @($username,(ConvertTo-SecureString -String $password -AsPlainText -Force))
Start-Process "C:\Catalyst\git\CAP\Catalyst.DataProcessing\DataProcessingSolution\DataProcessing.Engine.WindowsService\bin\Debug\CatalystDPE.WindowsService.exe" -Credential ($credentials)
