#Determine VPC ID this can be used to dynamically set values for script based on VPC.. using only one script rather than one for each VPC 
$mac = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/network/interfaces/macs
$vpcid = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/network/interfaces/macs/$mac/vpc-id
$ipv4 = Invoke-RestMethod -Uri http://169.254.169.254/latest/meta-data/local-ipv4

#get credentials from instance metadata
$iam = Invoke-RestMethod -uri http://169.254.169.254/latest/meta-data/iam/security-credentials/
$iamProfileInfo = ConvertFrom-Json (Invoke-WebRequest http://169.254.169.254/latest/meta-data/iam/security-credentials/$iam ).content
Set-AWSCredentials -AccessKey $iamProfileInfo.AccessKeyId -SecretKey $iamProfileInfo.SecretAccessKey -SessionToken $iamProfileInfo.Token

Add-WindowsFeature rsat-dns-server #needed to create DNS records

$logfile = "c:\bootstrap\scriptoutput.txt"
####### Get passwords from content

$certpassraw=get-content -Path C:\Bootstrap\bootstrap_assets.txt -Head 1
$FirstAccountPwdHash=(get-content -Path C:\Bootstrap\bootstrap_assets.txt -head 2)[-1]
$SecondAccountPwdHash=(get-content -Path C:\Bootstrap\bootstrap_assets.txt -head 3)[-1]
$certpassenc=$certpassraw | ConvertTo-SecureString -AsPlainText -force
####Install SSL Cert for decryption
$certstorelocation="Cert:\LocalMachine\My"
Import-PfxCertificate -FilePath c:\bootstrap\bootstrap_cert.pfx -CertStoreLocation $certstorelocation -Password $certpassenc

####Decrypt First domain account pw
$cert=Get-ChildItem $certstorelocation | Where-Object {$_.Subject -like "CN=bootstrap*"}
$FirstAccountEncryptedBytes = [System.Convert]::FromBase64String($FirstAccountPwdHash)
$FirstAccountDecryptedBytes = $Cert.PrivateKey.Decrypt($FirstAccountEncryptedBytes, $true)
$FirstAccountAccountPwd = [system.text.encoding]::UTF8.GetString($FirstAccountDecryptedBytes)
$FirstAccountPwdSecure = $FirstAccountAccountPwd | ConvertTo-SecureString -AsPlainText -Force

####Decrypt second domain account pw
$SecondAccountEncryptedBytes = [System.Convert]::FromBase64String($SecondAccountPwdHash)
$SecondAccountDecryptedBytes = $Cert.PrivateKey.Decrypt($SecondAccountEncryptedBytes, $true)
$SecondAccountPwd = [system.text.encoding]::UTF8.GetString($SecondAccountDecryptedBytes)

####Store domain account credentials
$username = "domain\svc_aws_bootstrap"  ##PUT YOUR FIRST SERVICE ACCOUNT NAME HERE
$cred = New-Object -typename System.Management.Automation.PSCredential($username, $DomAccountPWdSecure)
$SecondAccountUsername="domain\otherserviceaccount"



#set variables by VPC
$VPCID= "VPC-XXXXXXX" ####Put your VPC ID here.  
if ($vpcid -eq $VPCID)  
#The If logic isn't necessary but just in case you want to have a single script and have it dynamically assign variables according to which VPC ID.  Just add a different block for each VPC. 
{
$DNS_Settings = "10.0.0.1,10.0.0.2" ### put the IP addresses of your DNS servers here. if you have only one, just remove comma and second entry.
Write-Host "DNS string is $($DNS_Settings)" | out-file -FilePath $logfile -Append -NoClobber
$AD_OU = "OU=AWS,OU=Windows,OU=Servers,DC=domain,DC=com" #Put the Distinguished name of the OU you wan the computers to be stored in here. Must look like the format I provided!!
Write-Host "OU set to $($AD_OU)" | out-file -FilePath $logfile -Append -NoClobber
$Zone_Name = "domain.com"  ##put the DNS zone you want your server's A record to created in here!
Write-Host "DNS Zone set to $($Zone_Name)" | out-file -FilePath $logfile -Append -NoClobber
$endpointurl = "http://vpce-xxxxxxxx-xxxxx.ec2.us-east-1.vpce.amazonaws.com"  #put your EC2 interface endpoint url here.
Write-Host "VPC EndPoint URL set to $($endpointurl)"
$domainname="domain.com"  ###put your domain name here
$DNSServer="DNS1" ###put the name of your DNS server here.
}
function AWS_BootStrap {
    $instanceId = (Invoke-RestMethod -Method Get -Uri http://169.254.169.254/latest/meta-data/instance-id) 
    $instance = ((Get-EC2Instance -Instance $instanceId -SessionToken $iamProfileInfo -EndPointURL $endpointurl).RunningInstance)
    $myInstance = $instance | Where-Object {$_.InstanceId -eq $instanceId}
    $nametag = $myInstance.Tags | Where-Object {$_.Key -eq "Name"}
    $hostname = $nametag.value
    Rename-Computer -NewName $hostname
    Write-Host "Hostname set to $($hostname)" | out-file -FilePath $logfile -Append -NoClobber
    Add-Computer -Credential $cred -DomainName $domainname -OUPath $AD_OU -Options JoinWithNewName, AccountCreate
    Write-Host "Computer added to domain" | out-file -FilePath $logfile -Append -NoClobber
    Set-DnsClientServerAddress -ServerAddresses $DNS_Settings  -InterfaceAlias "Ethernet 2"
    Write-Host "DNS set to $($DNS_Settings)" | out-file -FilePath $logfile -Append -NoClobber

    ##new shell to DNS Server
    $Cim = New-CimSession -ComputerName $DNSServer -Credential $cred
    Add-DnsServerResourceRecordA -Name $hostname -IPV4Address $ipv4 -ZoneName $Zone_Name -cimsession $cim -CreatePtr
    Write-Host "A Record created for $($hostname) at $($ipv4)" | out-file -FilePath $logfile -Append -NoClobber
        
        
    ####Optional section####
    ### SECOND service account needed to call a setup.exe file that needs a user name and password to install. 
    ##Secure strings are not supported in this method, hence why the password is set in clear, 
    ##the first account is used by passing the credential parameter so that must have access to the setup file location but the second account had application level access
    ##your domain may not have a such a piquancy involved, but I included this in case you needed that..
    ... 
   #     $Installer = "\\UNCPATH To File\setup.exe"
   #     $Argument = "-user $secondaccountusername -pwd $SecondAccountpwd"
   #     Start-Process $Installer $Argument -credential $cred -Wait
   # Write-Host "Antivirus  installed" | out-file -FilePath $logfile -Append -NoClobber
}

try
{AWS_BootStrap}
catch 
{Write-Output $_.Exception | Out-File $logfile -Append -NoClobber}
Remove-WindowsFeature rsat-dns-server
Restart-Computer
