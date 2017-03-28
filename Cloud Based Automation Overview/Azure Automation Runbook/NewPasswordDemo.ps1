#Get the Azure Function URL (stored in Azure Automation account as an automation variable)
$NewPasswordAzureFunctionURL = Get-AutomationVariable 'NewPasswordAzureFunctionURL'

#Invoke Azure Function with default parameters
$NewPasswordRequest = Invoke-WebRequest -UseBasicParsing -Uri $NewPasswordAzureFunctionURL -Method Get
$NewPasswordObject = ConvertFrom-Json $NewPasswordRequest.Content
Write-Output "New password generated (with default parameters): '$($NewPasswordObject.NewPassword)'. Password length: $($NewPasswordObject.Length). Special Characters count: $($NewPasswordObject.SpecialChar)"

#Invoke Azure Function with custom parameters
$PasswordLength = 16
$SpecialCharacterCount = 4
$NewPasswordAzureFunctionURL = "$NewPasswordAzureFunctionURL`?length=$PasswordLength`&specialchar=$SpecialCharacterCount"
$NewPasswordRequest = Invoke-WebRequest -UseBasicParsing -Uri $NewPasswordAzureFunctionURL -Method Get
$NewPasswordObject = ConvertFrom-Json $NewPasswordRequest.Content
Write-Output "New password generated (with custom parameters): '$($NewPasswordObject.NewPassword)'. Password length: $($NewPasswordObject.Length). Special Characters count: $($NewPasswordObject.SpecialChar)"