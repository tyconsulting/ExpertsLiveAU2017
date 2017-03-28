function New-Password
{
  [CmdletBinding()]
  PARAM (
    [Parameter(Mandatory = $false)][int]$Length=10,
    [Parameter(Mandatory = $false)][int]$SpecialChar=2
  )
  Add-Type -AssemblyName System.Web
  [Web.Security.Membership]::GeneratePassword($Length,$SpecialChar)
}
#Generate password with default parameters
$NewPassword = New-Password
Write-Output "New password generated (with default parameters): '$NewPassword'."

#Generate password using custom parameters
$NewPassword = New-Password -Length 16 -SpecialChar 4
Write-Output "New password generated (with default parameters): '$NewPassword'."