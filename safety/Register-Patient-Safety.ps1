#
# Install_Authorization_Windows.ps1
#
function Get-IdentityServiceUrl()
{
    return "https://$env:computername.$($env:userdnsdomain.tolower())/Identity"
}

function Get-AuthorizationServiceUrl()
{
    return "https://$env:computername.$($env:userdnsdomain.tolower())/Authorization"
}

function Get-SafetySurveillanceUrl()
{
    return "https://$env:computername.$($env:userdnsdomain.tolower())/SafetySurveillance"
}

function Invoke-Post($url, $body, $accessToken)
{
    $headers = @{"Accept" = "application/json"}
    if($accessToken){
        $headers.Add("Authorization", "Bearer $accessToken")
    }
    $body = (ConvertTo-Json $body)
    try{
        $postResponse = Invoke-RestMethod -Method Post -Uri $url -Body $body -ContentType "application/json" -Headers $headers
        Write-Success "Success."
        Write-Host ""
        return $postResponse
    }catch{
        $exception = $_.Exception
        if($exception -ne $null -and $exception.Response.StatusCode.value__ -eq 409)
        {
            Write-Success "Entity: "
            Write-Success $body
            Write-Success "already exists, skipping creation."
            Write-Host ""
        }else{
            $result = $exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($result)
            $reader.BaseStream.Position = 0
            $reader.DiscardBufferedData()
            $responseBody = $reader.ReadToEnd();
            Write-Error $responseBody
            throw $exception
        }
    }
}

function Add-AuthorizationRegistration($authUrl, $clientId, $clientName, $accessToken)
{
    $url = "$authUrl/clients"
    $body = @{
        id = "$clientId"
        name = "$clientName"
    }
    return Invoke-Post $url $body $accessToken
}

function Add-Permission($authUrl, $name, $grain, $securableItem, $accessToken)
{
    $url = "$authUrl/permissions"
    $body = @{
        name = "$name"
        grain = "$grain"
        securableItem = "$securableItem"
    }
    return Invoke-Post $url $body $accessToken
}

function Add-Role($authUrl, $name, $grain, $securableItem, $accessToken)
{
    $url = "$authUrl/roles"
    $body = @{
        name = "$name"
        grain = "$grain"
        securableItem = "$securableItem"
    }
    return Invoke-Post $url $body $accessToken
}

function Add-Group($authUrl,$name, $source, $accessToken)
{
    $url = "$authUrl/groups"
    $body = @{
        id = "$name"
        groupName = "$name"
        groupSource = "$source"
    }
    return Invoke-Post $url $body $accessToken
}

function Add-PermissionToRole($authUrl, $roleId, $permission, $accessToken)
{
    $url = "$authUrl/roles/$roleId/permissions"
    $body = @($permission)
    return Invoke-Post $url $body $accessToken
}

function Add-RoleToGroup($authUrl, $groupName, $role, $accessToken)
{
    $encodedGroupName = [System.Web.HttpUtility]::UrlEncode($groupName)
    $url = "$authUrl/groups/$encodedGroupName/roles"
    $body = $role
    return Invoke-Post $url $body $accessToken
}

if(!(Test-Path .\Fabric-Install-Utilities.psm1)){
	Invoke-WebRequest -Uri https://raw.githubusercontent.com/HealthCatalyst/InstallScripts/master/common/Fabric-Install-Utilities.psm1 -OutFile Fabric-Install-Utilities.psm1
}
Import-Module -Name .\Fabric-Install-Utilities.psm1 -Force

if(!(Test-IsRunAsAdministrator))
{
    Write-Error "You must run this script as an administrator. Halting configuration." -ErrorAction Stop
}

$installSettings = Get-InstallationSettings "registration"
$fabricInstallerSecret = $installSettings.fabricInstallerSecret
$authorizationServiceURL =  $installSettings.authorizationService
$identityServiceUrl = $installSettings.identityService
$safetySurveillanceUrl = $installSettings.safetySurveillanceService
$groupName = $installSettings.groupName

if([string]::IsNullOrEmpty($installSettings.identityService))  
{
	$identityServiceUrl = Get-IdentityServiceUrl
} else
{
	$identityServiceUrl = $installSettings.identityService
}

if([string]::IsNullOrEmpty($installSettings.authorizationService))  
{
	$authorizationServiceURL = Get-AuthorizationServiceUrl
} else
{
	$authorizationServiceURL = $installSettings.authorizationService
}

if([string]::IsNullOrEmpty($installSettings.safetySurveillanceService))  
{
	$safetySurveillanceUrl = Get-SafetySurveillanceUrl
} else
{
	$safetySurveillanceUrl = $installSettings.safetySurveillanceService
}

try{
	$encryptionCert = Get-Certificate $encryptionCertificateThumbprint
}catch{
	Write-Host "Could not get encryption certificate with thumbprint $encryptionCertificateThumbprint. Please verify that the encryptionCertificateThumbprint setting in install.config contains a valid thumbprint for a certificate in the Local Machine Personal store. Halting installation."
	throw $_.Exception
}


$userEnteredFabricInstallerSecret = Read-Host  "Enter the Fabric Installer Secret or hit enter to accept the default [$fabricInstallerSecret]"
Write-Host ""
if(![string]::IsNullOrEmpty($userEnteredFabricInstallerSecret)){   
     $fabricInstallerSecret = $userEnteredFabricInstallerSecret
}

$userEnteredAuthorizationServiceURL = Read-Host  "Enter the URL for the Authorization Service or hit enter to accept the default [$authorizationServiceURL]"
Write-Host ""
if(![string]::IsNullOrEmpty($userEnteredAuthorizationServiceURL)){   
     $authorizationServiceURL = $userEnteredAuthorizationServiceURL
}

$userEnteredIdentityServiceURL = Read-Host  "Enter the URL for the Identity Service or hit enter to accept the default [$identityServiceUrl]"
Write-Host ""
if(![string]::IsNullOrEmpty($userEnteredIdentityServiceURL)){   
     $identityServiceUrl = $userEnteredIdentityServiceURL
}

$userEnteredSafetySurveillanceURL = Read-Host  "Enter the URL for the Safety Surveillance Service or hit enter to accept the default [$safetySurveillanceUrl]"
Write-Host ""
if(![string]::IsNullOrEmpty($userEnteredSafetySurveillanceURL)){   
     $safetySurveillanceUrl = $userEnteredSafetySurveillanceURL
}

$userEnteredGroupName = Read-Host  "Enter the AD Group name to associate to the documenter role or hit enter to accept the default [$groupName]"
Write-Host ""
if(![string]::IsNullOrEmpty($userEnteredGroupName)){   
     $groupName = $userEnteredGroupName
}

if([string]::IsNullOrWhiteSpace($fabricInstallerSecret))
{
    Write-Error "You must enter a value for the installer secret" -ErrorAction Stop
}
if([string]::IsNullOrWhiteSpace($authorizationServiceURL))
{
    Write-Error "You must enter a value for the Fabric.Authorization URL" -ErrorAction Stop
}
if([string]::IsNullOrWhiteSpace($identityServiceUrl))
{
    Write-Error "You must enter a value for the Fabric.Identity URL." -ErrorAction Stop
}
if([string]::IsNullOrWhiteSpace($safetySurveillanceUrl))
{
    Write-Error "You must enter a value for the Safety Surveillance URL" -ErrorAction Stop
}
if([string]::IsNullOrWhiteSpace($groupName))
{
    Write-Error "You must enter a value for the Group." -ErrorAction Stop
}

$accessToken = Get-AccessToken $identityServiceUrl "fabric-installer" "fabric/identity.manageresources fabric/authorization.write fabric/authorization.read fabric/authorization.manageclients" $fabricInstallerSecret

#Register safety surveillance api
$body = @'
{
	"name":"safety-surveillance-api",
	"userClaims":["name","email","role","groups"],
	"scopes":[{"name":"safety-surveillance-api"}]
}
'@

Write-Host "Registering Safety Surveillance API with Fabric.Identity."
try {
	$authorizationApiSecret = Add-ApiRegistration -authUrl $identityServiceUrl -body $body -accessToken $accessToken
	Write-Success "Safety Surveillance apiSecret: $authorizationApiSecret"
	Write-Host ""
} catch {
    $exception = $_.Exception
    if($exception -ne $null -and $exception.Response.StatusCode.value__ -eq 409)
    {
	    Write-Success "Safety Surveillance API is already registered."
        Write-Host ""
    }else{
        Write-Error "Could not register Safety Surveillance API with Fabric.Identity, halting installation."
        throw $exception
    }

}

#Register safety surveillance client
$body = @{
    clientId = "safety-surveillance-webapp"
    clientName = "Safey Surveillance Web App"
    requireConsent = "false" 
    allowedGrantTypes = @("implicit", "client_credentials")
    redirectUris = @("$safetySurveillanceUrl/oidc-callback.html","$safetySurveillanceUrl/silent.html")
    postLogoutRedirectUris = @("$safetySurveillanceUrl")
    allowOfflineAccess = "false"
    allowAccessTokensViaBrowser = "true"
    allowedCorsOrigins = @("$safetySurveillanceUrl")
    allowedScopes = @("openid", "profile", "fabric.profile", "safety-surveillance-api", "fabric/authorization.write", "fabric/authorization.read", "fabric/authorization.manageclients")
}

$body = (ConvertTo-Json $body)
Write-Host "Registering Safety Surveillance Client with Fabric.Identity."
try{
	$authorizationClientSecret = Add-ClientRegistration -authUrl $identityServiceUrl -body $body -accessToken $accessToken
	Write-Success "Safety Surveillance clientSecret: $authorizationClientSecret"
	Write-Host ""
} catch {
    $exception = $_.Exception
    if($exception -ne $null -and $exception.Response.StatusCode.value__ -eq 409)
    {
	    Write-Success "Safety Surveillance Client is already registered."
        Write-Host ""
    }else{
        Write-Error "Could not register Safety Surveillance Client with Fabric.Identity, halting installation."
        throw $exception
    }
}

$clientId = "safety-surveillance-webapp"
$grain = "app"

Write-Host "Registering Safety Surveillance Client with Fabric.Authorization."
$client = Add-AuthorizationRegistration -authUrl $authorizationServiceURL -clientId $clientId -clientName "Safety Surveillance Web App" -accessToken $accessToken

Write-Host "Creating 'candocument' permission."
$permission = Add-Permission -authUrl $authorizationServiceURL -name "candocument" -grain $grain -securableItem $clientId -accessToken $accessToken

Write-Host "Creating 'documenter' role."
$role = Add-Role -authUrl $authorizationServiceURL -name "documenter" -grain $grain -securableItem $clientId -accessToken $accessToken

Write-Host "Adding '$groupName' group."
$group = Add-Group -authUrl $authorizationServiceURL -name $groupName -source "Windows" -accessToken $accessToken

if($permission -ne $null -and $role -ne $null){
    Write-Host "Associating permission with role."
    $rolePermission = Add-PermissionToRole -authUrl $authorizationServiceURL -roleId $role.id -permission $permission -accessToken $accessToken
}

if($group -ne $null -and $role -ne $null){
    Write-Host "Associating role with group."
    $groupRole = Add-RoleToGroup -authUrl $authorizationServiceURL -groupName $groupName -role $role -accessToken $accessToken
}
