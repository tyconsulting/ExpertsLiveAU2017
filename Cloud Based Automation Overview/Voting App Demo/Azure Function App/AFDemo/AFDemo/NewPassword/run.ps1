$DefaultPasswordLength = $env:DefaultPasswordLength
$DefaultNumberOfSpecialCharacters = $env:DefaultNumberOfSpecialCharacters
Add-Type -AssemblyName System.Web | out-null

if ($req_query_length) 
{
    $length = $req_query_length
} else {
    $length = $DefaultPasswordLength
}

if ($req_query_specialchar)
{
    $NumberOfSpecialCharacters = $req_query_specialchar
} else {
    $NumberOfSpecialCharacters = $DefaultNumberOfSpecialCharacters
}
$NewPassword = [Web.Security.Membership]::GeneratePassword($Length,$NumberOfSpecialCharacters)
$output = @{
    'NewPassword'=$NewPassword
    'Length' = $length
    'SpecialChar' = $NumberOfSpecialCharacters
} | convertto-JSON
Out-File -Encoding Ascii -FilePath $res -inputObject $output