ipmo *aws*

$accesskey = Read-Host -Prompt "Insert your API Access Key"
$secretkey = Read-Host -Prompt "Insert your API Secret Key"
Set-AWSCredentials -StoreAs usersession  -AccessKey $accesskey -SecretKey $secretkey
$wildcardfilter = Read-Host -Prompt "Enter filter string (include stars)"
$ObjectType = Read-Host -Prompt "Object type (instance/volume)"
$TagName = Read-Host -prompt "Enter tag name (NOT VALUE)"
$TagValue = Read-Host -Prompt "Enter tag value"
$tag = New-Object Amazon.EC2.Model.Tag
$tag.key = $TagName
$tag.value = $TagValue  

function TagEC2Object {

$objects =  Get-EC2Tag -Region us-east-1 -StoredCredentials usersession | where {$_.resourcetype -eq $ObjectType -and $_.value -like $wildcardfilter -or $_.Value -contains $wildcardfilter} #contains is if your tag value has spaces as the like operator may not work for filters with spaces

foreach ($object in $objects.ResourceId)
{
New-EC2Tag -Resources $object -Tags $tag -Region us-east-1 -storedcredentials usersession
}
}

TagEC2Object
Clear-AWSCredentials -StoredCredentials usersession
