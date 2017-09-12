Import-Module WebAdministration
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Add-EnvironmentVariable($variableName, $variableValue, $config){
	Write-Host "Writing $variableName to config"
	$environmentVariablesNode = $config.configuration.'system.webServer'.aspNetCore.environmentVariables
	$environmentVariable = $config.CreateElement("environmentVariable")
	
	$nameAttribute = $config.CreateAttribute("name")
	$nameAttribute.Value = $variableName
	$environmentVariable.Attributes.Append($nameAttribute)
	
	$valueAttribute = $config.CreateAttribute("value")
	$valueAttribute.Value = $variableValue
	$environmentVariable.Attributes.Append($valueAttribute)

	$environmentVariablesNode.AppendChild($environmentVariable)
}

function New-AppRoot($appDirectory, $iisUser){
	# Create the necessary directories for the app
	$logDirectory = "$appDirectory\logs"

	Write-Host "Creating application directory: $appDirectory."
	if(!(Test-Path $appDirectory)) {mkdir $appDirectory}

	Write-Host "Creating applciation log directory: $logDirectory."
	if(!(Test-Path $logDirectory)) {
		mkdir $logDirectory
		Write-Host "Setting Write and Read access for $iisUser on $logDirectory."
		$acl = (Get-Item $logDirectory).GetAccessControl('Access')
		$writeAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($iisUser, "Write", "ContainerInherit,ObjectInherit", "None", "Allow")
		$readAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($iisUser, "Read", "ContainerInherit,ObjectInherit", "None", "Allow")
		$acl.AddAccessRule($writeAccessRule)
		$acl.AddAccessRule($readAccessRule)
		Set-Acl -Path $logDirectory $acl
	}
}

function New-AppPool($appName){
	cd IIS:\AppPools

	if(!(Test-Path $appName -PathType Container))
	{
		Write-Host "AppPool $appName does not exist...creating."
		$appPool = New-WebAppPool $appName
		$appPool | Set-ItemProperty -Name "managedRuntimeVersion" -Value ""
		$appPool.Start()
	}
}

function New-Site($appName, $portNumber, $appDirectory, $hostHeader){
	cd IIS:\Sites

	if(!(Test-Path $appName -PathType Container))
	{
		Write-Host "WebSite $appName does not exist...creating."
		$webSite = New-Website -Name $appName -Port $portNumber -Ssl -PhysicalPath $appDirectory -ApplicationPool $appName -HostHeader $hostHeader
	
		Write-Host "Assigning certificate..."
		$cert = Get-Item Cert:\LocalMachine\My\$sslCertificateThumbprint
		cd IIS:\SslBindings
		$sslBinding = "0.0.0.0!$portNumber"
		if(!(Test-Path $sslBinding)){
			$cert | New-Item $sslBinding
		}
	}
}

function New-App($appName, $siteName, $appDirectory){
	cd IIS:\

	New-WebApplication -Name $appName -Site $siteName -PhysicalPath $appDirectory -ApplicationPool $appName
}

function Publish-WebSite($zipPackage, $appDirectory){
	# Extract the app into the app directory
	Write-Host "Extracting $zipPackage to $appDirectory."
	[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPackage, $appDirectory)
	#Start-Sleep -Seconds 3
}

function Set-EnvironmentVariables($appDirectory, $environmentVariables){
	Write-Host "Writing environment variables to config..."
	$webConfig = [xml](Get-Content $appDirectory\web.config)
	foreach ($variable in $environmentVariables.GetEnumerator()){
		Add-EnvironmentVariable $variable.Name $variable.Value $webConfig
	}

	$webConfig.Save("$appDirectory\web.config")
}

function Get-EncryptedString($signingCert, $stringToEncrypt){
	$encryptedString = [System.Convert]::ToBase64String($signingCert.PublicKey.Key.Encrypt([System.Text.Encoding]::UTF8.GetBytes($stringToEncrypt), $true))
	return "!!enc!!:" + $encryptedString
}

function Get-InstalledApps
{
    if ([IntPtr]::Size -eq 4) {
        $regpath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    }
    else {
        $regpath = @(
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
        )
    }
    Get-ItemProperty $regpath | .{process{if($_.DisplayName -and $_.UninstallString) { $_ } }} | Select DisplayName, Publisher, InstallDate, DisplayVersion, UninstallString |Sort DisplayName
}

function Test-Prerequisite($appName, $minVersion)
{
    $installedAppResults = Get-InstalledApps | where {$_.DisplayName -like $appName}
    if($installedAppResults -eq $null){
        return $false;
    }

    if($minVersion -eq $null)
    {
        return $true;
    }

    $minVersionAsSystemVersion = [System.Version]$minVersion
    Foreach($version in $installedAppResults)
    {
        $installedVersion = [System.Version]$version.DisplayVersion
        if($installedVersion -ge $minVersionAsSystemVersion)
        {
            return $true;
        }
    }
}

export-modulemember -function Add-EnvironmentVariable
export-modulemember -function New-AppRoot
export-modulemember -function New-AppPool
export-modulemember -function New-Site
export-modulemember -function New-App
export-modulemember -function Publish-WebSite
export-modulemember -function Set-EnvironmentVariables
export-modulemember -function Get-EncryptedString
export-modulemember -function Test-Prerequisite