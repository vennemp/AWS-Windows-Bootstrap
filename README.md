# AWS-Windows-Bootstrap
This script can be used to automatically add Windows computers to an AD domain upon launching the EC2 instance

This is my first time contributing to GitHub and the Open Source world.  With that said, my powershell may be a little hard to read.  I apologize in advance.

I wrote this script for a client so that they can automatically add a Windows EC2 instance to an already created domain in AWS.  This is somewhat of a free version to AWS Directory Services where you can import your domain into AWS to be joined at launch.  

The script will do the following:
1. Rename the computer according to the "Name" tag given at launch.
1. Update the local DNS settings.
1. Join the domain and add computer object to appropriate OU in AD.
1. Create the A record on your DNS server.
1. (OPTIONAL)We have a requirement to install anti-virus on all domain computers.  I will include some logic for how I went about this.
1. Reboot


In order for this to work, you will need to consider the following:
1. IAM roles.  Since I designed this script to be stored in S3, you will obviously need an IAM role that has Read access to the bucket.  Also, you will need make sure your IAM role includes the ability to Read EC2 data so it can query the tags.
1. VPC Endpoints / PrivateLink.  In order to follow best security practices, you will need to create VPC endpoints for both EC2 (interface type) and S3 (gateway type).  The S3 gateway will need to be added to your route tables for each VPC you wish this to work. These are especially necessary if you are using this in a private subnet and will not have a NAT Gateway.
The EC2 endpoint is accessed via URL. REMEMBER THIS URL because you will need to be add to the script. https://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/vpce-interface.html
1. Credential management.  In order to add computers to a domain and perform the actions necessary you will need to create a designated domain account.  Follow least privilege (only give ability to create DNS records, add to the needed OUs, etc).
1. Password encryption.  Since you do not want to store the password for the aforementioned service accounts in the clear, in the script.  You will have to consider how to protect those credentials from malicious threats.  This was written using an SSL cert from our Domain CA to encrypt and decrypt the credentials. We explored other avenues of encryption, namely AWS KMS and a standard symmetric encryption with powershell.  We went against KMS because we wanted to manage our own encryption keys. Here is a great article on how to encrypt strings using KMS. https://stevenaskwith.com/2016/07/07/encrypting-secrets-using-powershell-and-aws-kms/  Here is an article if you wish to generate your own encryption key.  https://gallery.technet.microsoft.com/scriptcenter/PowerShell-Script-410ef9df
1. S3 security.  We chose to additionally lock down the S3 bucket to have no public access and use SS3-C encryption of the actual files in the bucket on top of the encrypted passwords.
1. Knowledge of your environment.  This goes without saying but make sure to know your environment well enough to implement this. DC names, DNS settings, GPOs, firewall rules etc.  

The script will do the following:
1. Via user data, create a folder called Bootstrap in C:\. Copy all script assets from the s3 bucket and call script.
1. From locally copied files, the script will grab the strings from a text file.  Each line in the string is an encrypted password.  It will decrypt the string, and then store it as a secure string to used in credentials.  
1. Rename the computer according to the "Name" tag given at launch.
1. Update the local DNS settings.
1. Join the domain and add computer object to appropriate OU in AD.
1. Create the A record on your DNS server.
1. (OPTIONAL)We have a requirement to install anti-virus on all domain computers.  I will include some logic for how I went about this.
1. Reboot

I included an example of the architecture of the text file I queried for the passwords.  Each password must be in a single line, no matter how long the encrypted string is.  The logic in the get-content portion of the script is how you can target a single line in a text file.

If you wish to encrypt the files in S3 using SSE-C upload the following.. MAKE SURE TO STORE THE VALUE OF $BASE64 in clear.. YOU WILL NEED IT FOR DECRYPTION!  To make it easy, use a prefix for each of the file names..  I used "bootstrap"
```Powershell
$Aes = New-Object System.Security.Cryptography.AesManaged
$Aes.KeySize = 256
$Aes::GenerateKey
$Base64key = [System.Convert]::ToBase64String($Aes.Key)

Write-S3Object -Region us-east-1 -File $file -BucketName $bucket -Key $objectkey `-
ServerSideEncryptionCustomerProvidedKey $Base64key `
-ServerSideEncryptionCustomerMethod AES256
```

When creating your instance, assign the IAM role named above
Just paste this in user data and VOILA!
```
<powershell>
New-Item -value bootstrap -Path c:\ -ItemType directory
Get-S3Object -BucketName BUCKETNAME -KeyPrefix bootstrap | Copy-S3Object -BucketName BUCKETNAME -localfolder c:\bootstrap -ServerSideEncryptionCustomerProvidedKey valueofbase64variable -ServerSideEncryptionCustomerMethod aes256
set-location c:\bootstrap
.\bootstrap_aws_windows.ps1
</powershell>
```
