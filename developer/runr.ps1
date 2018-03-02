

$username = "hqcatalyst\edw_loader"
$password = "P@ssw0rd"
$credentials = New-Object System.Management.Automation.PSCredential -ArgumentList @($username,(ConvertTo-SecureString -String $password -AsPlainText -Force))
Start-Process "C:\Program Files\R\R-3.4.3\bin\Rscript.exe" -Credential ($credentials) -ArgumentList "C:\\himss\\healthcareai_predictingScript_sepsisDemo_20180224.r"

# $pinfo = New-Object System.Diagnostics.ProcessStartInfo
# $pinfo.FileName = "C:\Program Files\R\R-3.4.3\bin\Rscript.exe"
# $pinfo.RedirectStandardError = $true
# $pinfo.RedirectStandardOutput = $true
# # $pinfo.UseShellExecute = $false
# $pinfo.Arguments = "C:\himss\healthcareai_predictingScript_sepsisDemo_20180224.r"
# $pinfo.UserName = $username
# $pinfo.PasswordInClearText = $password
# $p = New-Object System.Diagnostics.Process
# $p.StartInfo = $pinfo
# $p.Start()
# # | Out-Null
# $p.WaitForExit()
# $stdout = $p.StandardOutput.ReadToEnd()
# $stderr = $p.StandardError.ReadToEnd()
# Write-Host "stdout: $stdout"
# Write-Host "stderr: $stderr"
# Write-Host "exit code: " + $p.ExitCode

# "C:\Program Files\R\R-3.4.3\bin\Rscript.exe" "C:\\himss\\healthcareai_predictingScript_sepsisDemo_20180224.r"
