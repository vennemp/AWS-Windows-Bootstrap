ipmo *aws*

##This assumes you have default region and credentials stored in session. See Initialize-AWSDefaultConfiguration...

(Get-EC2Tag) | 
  Out-GridView -OutputMode Multiple | 
  ForEach-Object -Process { 
    New-EC2Tag -Tag (New-Object -TypeName Amazon.EC2.Model.Tag -ArgumentList @('Key', 'Value')) -Resource $PSItem.ResourceId
  }
