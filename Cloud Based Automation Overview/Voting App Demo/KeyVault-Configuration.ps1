#Requires -Modules @{ModuleName='AzureRM.Resources'; ModuleVersion='3.2.0'; GUID='ab3ca893-26fe-44b0-bd3c-8933df144d7b'}, @{ModuleName='AzureRM.Automation'; ModuleVersion='2.2.0'; GUID='bcea1c70-a32b-48c3-a05c-323e1c02f4d3'}, @{ModuleName='AzureRM.KeyVault'; ModuleVersion='2.2.0'; GUID='fa236c1f-6464-4d6a-a48d-db47c0e7923d'}, @{ModuleName='AzureRM.Profile'; ModuleVersion='2.2.0'; GUID='342714fc-4009-4863-8afb-a9067e3db04b'}
#requires -version 3.0
#Requires -RunAsAdministrator
<#
==================================================================
AUTHOR:  Tao Yang 
DATE:    24/03/2017
Version: 1.0
Comment: Configure the Key Vault
==================================================================
#>

#region functions
function New-Password
{
  [CmdletBinding()]
  PARAM (
    [Parameter(Mandatory = $true,HelpMessage='Specify the password length')][int]$Length,
    [Parameter(Mandatory = $true,HelpMessage='Specify the number of special characters')][int]$NumberOfSpecialCharacters
  )
  Add-Type -AssemblyName System.Web
  [Web.Security.Membership]::GeneratePassword($Length,$NumberOfSpecialCharacters)
}

#endregion
Clear-Host
#region variables
$CertValidityMonth = 12
#endregion

Write-Output "Login to Azure."
$null = Add-AzureRmAccount
$Context = Get-AzureRmContext

$CurrentSubName = $Context.Subscription.SubscriptionName
$CurrentSubId = $Context.Subscription.SubscriptionId
$TenantDomain = $Context.Tenant.Domain

#Select Azure subscription
If ($CurrentSubName -ne $null)
{
  $SelectSubTitle = "Select Azure Subscription"
  $SelectSubMessage = "Currently the Azure subscription '$CurrentSubName (Id: $CurrentSubId)' is selected. Do you want to use this subscription?"
  $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Use the current subscription."
  $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Select another subscription."
  $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

  $UserSelected = $host.ui.PromptForChoice($SelectSubTitle, $SelectSubMessage, $options, 0) 

}
If($UserSelected -eq 1)
{
  Write-Output "Getting Azure subscriptions..."
  $subscriptions = Get-AzureRmSubscription -WarningAction SilentlyContinue
  if ($subscriptions.count -gt 0)
  {
    Write-Output -InputObject 'Select Azure Subscription of which the Azure Key Vault is located'

    $menu = @{}
    for ($i = 1;$i -le $subscriptions.count; $i++) 
    {
      Write-Host -Object "$i. $($subscriptions[$i-1].SubscriptionName)"
      $menu.Add($i,($subscriptions[$i-1].SubscriptionId))
    }
    Do 
    {
      [int]$ans = Read-Host -Prompt "Enter selection (1 - $($i -1))"
    }
    while ($ans -le 0 -or $ans -gt $($i -1))
    Write-Output ""
    $subscriptionID = $menu.Item($ans)
    $null = Set-AzureRmContext -SubscriptionId $subscriptionID
  }
  else 
  {
    Write-Error -Message 'No Azure Subscription found. Unable to continue!'
    Exit -1
  }
}
$Context = Get-AzureRmContext
$TenantId = $Context.Tenant.TenantId
$SubscriptionId = $Context.Subscription.SubscriptionId

#endregion


#Azure Key Vault
$Keyvaults = Get-AzureRmKeyVault
Write-OUtput "Select Azure Key Vault:"
for ($i = 1;$i -le $Keyvaults.count; $i++) 
{
  Write-Output "$i. $($Keyvaults[$i-1].VaultName)"
}

[int]$ans = Read-Host -Prompt 'Enter selection'
$KeyVault = $Keyvaults[$ans-1]
$KeyVaultName = $KeyVault.VaultName

#endregion

#Create Azure Service Principal connection to be used by Azure Functions
#Region Create AAD Service Principal Login
Write-Verbose "Creating Azure Active Directory application and the Service Principal."
$ApplicationDisplayName = "ExpertsLiveAUDemo_" + $([GUID]::NewGuid().Tostring()) -replace('-', '')

#create cert
Write-Verbose "Creating certificate"
$CurrentDate = Get-Date
$EndDate = $CurrentDate.AddMonths($CertValidityMonth)
$KeyId = (New-Guid).Guid
$CertPath = Join-Path -Path $PSScriptRoot -ChildPath ($ApplicationDisplayName + '.pfx')
Write-Verbose "Creating a self-signed certificate '$CertPath'"
$Cert = New-SelfSignedCertificate -DnsName $ApplicationDisplayName -CertStoreLocation cert:\LocalMachine\My -KeyExportPolicy Exportable -Provider 'Microsoft Enhanced RSA and AES Cryptographic Provider'
$CertThumbprint = $cert.Thumbprint
$CertPlainPassword = New-Password -Length 8 -NumberOfSpecialCharacters 2
$CertPassword = ConvertTo-SecureString -String $CertPlainPassword -AsPlainText -Force
Export-PfxCertificate -Cert ('Cert:\localmachine\my\' + $Cert.Thumbprint) -FilePath $CertPath -Password $CertPassword -Force | Write-Verbose
If (Test-Path $CertPath)
{
  Write-Verbose "Certificate has been successfully exported, deleting it from the computer cert store now."
  $CertPathInCertStore = Join-path "Cert:\LocalMachine\My\" $Cert.Thumbprint
  Remove-item $CertPathInCertStore -Force
}
$PFXCert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate -ArgumentList @($CertPath, $CertPlainPassword)
$KeyValue = [System.Convert]::ToBase64String($PFXCert.GetRawCertData())
$KeyCredential = New-Object  -TypeName Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADKeyCredential
$KeyCredential.StartDate = $CurrentDate
$KeyCredential.EndDate = $EndDate
$KeyCredential.KeyId = $KeyId
$KeyCredential.CertValue = $KeyValue
Write-Verbose "Creating Azure AD application '$ApplicationDisplayName'"
$Application = New-AzureRmADApplication -DisplayName $ApplicationDisplayName -HomePage ('http://' + $ApplicationDisplayName) -IdentifierUris ('http://' + $ApplicationDisplayName) -KeyCredentials $KeyCredential


$ApplicationServicePrincipal = New-AzureRmADServicePrincipal -ApplicationId $Application.ApplicationId
Write-Verbose "Assigning the Contributor role to the application Service Principal"
$NewRole = $null
$Retries = 0
While ($NewRole -eq $null -and $Retries -le 5)
{
  # Sleep here for a few seconds to allow the service principal application to become active (should only take a couple of seconds normally)
  Start-Sleep -Seconds 10
  New-AzureRmRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 10
  $NewRole = Get-AzureRmRoleAssignment -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
  $Retries++
}


#Setting Key Vault permission for the AAD Application
Write-Verbose "Assigning Azure Key Vault permission for the Azure AD application."
Set-AzureRmKeyVaultAccessPolicy -VaultName $KeyVaultName -ServicePrincipalName $Application.ApplicationId -PermissionsToKeys get,list,decrypt -PermissionsToSecrets get,list


#write outputs
Write-Output "Done!"
Write-Output ""
Write-Output "Please store the following information in a secure location:"
Write-Output ""
Write-Output "Azure AD Application Name: $ApplicationDisplayName"
Write-Output "TenantId: $TenantID"
Write-Output "SubscriptionId: $SubscriptionId"
Write-output "Key Vault Name: $KeyVaultName"
Write-Output "Application Id: $($Application.ApplicationId)"
Write-Output "CertificateThumbprint: $CertThumbprint"
Write-Output "Certificate Password: $CertPlainPassword"
Write-Output "Certificate file path: '$CertPath'"
Write-Output "Certificate Expiry Date: $EndDate"