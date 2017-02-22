<#
Script to run against veeam to check if VM's are included in backup jobs

2015-12-17 Rikkert Kooy: Changed method to get VMs in any job. So VM's were returned even if job hadn't run yet
#>

[CmdletBinding()]
Param()


#region Module 1 : Customization
    Write-Verbose "starting script and loading custom settings from .\custom_Settings.xml"
    [xml]$ConfigFile = Get-Content ".\custom_Settings.xml"

    #vcenter settings from settings.xml
    $vcenter = $ConfigFile.settings.OtherSettings.Vcenter

    # Email settings from Settings.xml
    $MailTo = $ConfigFile.Settings.EmailSettings.MailTo
    $MailFrom = $ConfigFile.Settings.EmailSettings.MailFrom
    $MailServer = $ConfigFile.Settings.EmailSettings.SMTPServer
    $excludedvms= $ConfigFile.Settings.Exclusions.VM

    if($MailTo){$SendMail=$True}
#endregion Module 1: Customization

#region Module 2 : Function
    
    <#
    .Synopsis
       Creates the email body
    .DESCRIPTION
       Long description
    #>
    function Create-MailBody
    {
        [CmdletBinding()]
        [OutputType([string])]
        Param
        (
            # Param1 help description
            [Parameter(Mandatory=$true,
                       ValueFromPipelineByPropertyName=$true,
                       Position=0)]
            $excludedVMs,
    
            # Param2 help description
            [Parameter(Mandatory=$true,
                       ValueFromPipelineByPropertyName=$true,
                       Position=1)]
            $notBackedupVMs,
            
            [Parameter(Mandatory=$true,
                       ValueFromPipelineByPropertyName=$true,
                       Position=2)]
            $backupedVMs
        )
        Write-Verbose "Staring the creation of the html mail body"
        $body = '<body style="font-family: Arial; font-size: 10pt;">'
        $body += '<b>Here is the bi-weekly report of the backup</b>'
        $body +='<br><br>'

        $body +='<b>Below VMs are not included in a backup job</b>'
        
        foreach($vm in $excludedVMs)
        {
            $body +="<br>"+$vm.Name +":   "+$vm.Value
        }


        $body +="<br><br>"
        $body +="<b>Below VMs have not been backuped in the past 7 days</b>"
        foreach($vm in $notBackedupVMs)
        {
            $body +="<br>" + $vm.Name +":   "+$vm.Value
        }

        $body +="<br><br>"
        $body +="<b>Below VMs have been backuped in past 7 days</b>"
        foreach($vm in $backedupVMs)
        {
            $body +="<br>" +$vm.Name +":   "+$vm.Value
        }
        
        Write-Verbose "Email body is:"
        Write-Verbose "$body"    
        return $body
    }

#endregion Module 2: Function


#region Module 3: load powershell modules
    Write-Verbose "loading VMware and Veeam powershell snapin"

    Add-PSSnapin "VMware.VimAutomation.Core" -ErrorAction SilentlyContinue

    Add-PSSnapin VeeamPSSnapIn -ErrorAction SilentlyContinue
#endregion Module 3: load powershell modules

Write-Verbose "Connection to vcenter server: $vcenter" 
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | out-null
Connect-ViServer $vcenter | Out-Null

#Get a list of all VMs from vCenter
Write-Verbose "Getting list of all VMs in vCenter"
$vms = Get-VM | ForEach-Object {$_ | Select-object @{Name="VMname";Expression={$_.Name}}}| sort vmname|  select vmname -Unique


# Find all backup jobs that have ended in the last 7 days
Write-Verbose "Finding backup jobs in Veeam"
$backupSessionsPast7Days = Get-VBRBackupSession | Where-Object {$_.jobtype -eq 'backup' -and $_.creationtime -ge (Get-Date).adddays(-7)}
$backupJobs = Get-VBRJob | Where-Object {$_.IsBackup}


# Find objects in a backup jobs
$backupSessions = @()
Write-Verbose "Finding VMs that are included in a backup job"
foreach ($backupjob in $backupjobs) {
    $backupSessions += $backupjob.GetObjectsInJob()
}

Write-Verbose "Processing collected data to create hashtable with values whether the vm is unprotected, included in a job or succesfully backued up"
# Reduce to list of VM names in succesful backup sessions


Write-Verbose "Finding VMs that have backup status success or warning in the past 7 days"

#in backupjobs of past 7 days find all the backups of specifics VMs that didn't fail and make the list unique.
$backedupVMs = $backupSessionsPast7Days | ForEach-Object{($_.gettasksessions() | 
                        where{$_.status -ne 'failed'}).name} | select -Unique @{Name="VMname";Expression={$_}}


# Reduce to list of VM names in backup sessions
$includedVMs = $backupSessions | ForEach-Object {$_ | Select-object @{Name="VMname";Expression={$_.Name}}}

# Build hash table with excluded VMs
$excludedvmhash= @{}
foreach ($vm in $excludedvms) {
    $excludedvmhash.Add($vm, "Excluded")
}

# Build hash table of VMs from vCenter, skipping excluded VMs
# assume VM is not protected
$vmhash= @{}
foreach ($vm in $vms) {
    if (!$excludedvmhash.ContainsKey($vm.VMname)) {
        $vmhash.Add($vm.VMname, "Unprotected")
    }
}

# Loop through VMs included in backup job, if VM name exist in hash
# update value to included in job
foreach($includedVM in $includedVMs) {
    if($vmhash.ContainsKey($includedVM.VMname)) {
        $vmhash[$includedVM.VMname]="Included in job"
    }
}

# Loop through backed up VMs, if VM name exist in hash
# update value to protected
foreach($backedupVM in $backedupVMs) {
    if($vmhash.ContainsKey($backedupvm.VMname)) {
        $vmhash[$backedupvm.VMname]="Protected"
    }
}
Write-Verbose "processing is done"

Write-Verbose "Starting sorting data to generate report to mail"

#VMs not included in any job
$notIncludedVM = $vmhash.GetEnumerator() | where {$_.value -eq "unprotected"} | sort name
if($notIncludedVM -eq $null){$notIncludedVM= @()}

$notBackedupVM = $vmhash.GetEnumerator() | where {$_.Value -eq "Included in job"} | sort name
if($notBackedupVM -eq $null){$notBackedupVM = @()}

$backedupVMs = $vmhash.GetEnumerator() | where {$_.Value -eq "Protected"} | sort name

$subject = "Bi-Weekly report of Veeam backup"

$htmlBody = Create-MailBody -excludedVMs $notIncludedVM -notBackedupVMs $notBackedupVM -backupedVMs $backedupVMs

if($SendMail) {
    Send-MailMessage -subject $subject -SmtpServer $MailServer -BodyAsHtml $htmlBody -to $MailTo -From $MailFrom
}

