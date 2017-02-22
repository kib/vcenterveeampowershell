<#script created to make the following visible:
  - when Veeam backup jobs start
  - how big the fulls are
  - when the monthly active full runs (it is currently assumed the active fulls run each month)
 #>

[CmdletBinding()]
param()


#region 1 module: functions



<#
.Synopsis
   Converts the Veeam ApproxSizeString to an actual integer in Bytes
.DESCRIPTION
   Converts a string in format '123.3 GB' to an integer with value 123.
   Only values in MB, GB and TB are accepted.
.EXAMPLE
   Convert-SizeStringtoSizeInteger '123.3 GB'
.EXAMPLE
   $string = '1.8 TB'
   convert-SizeStringtoSizeInteger $string
#>
function Convert-SizeStringtoSizeInteger
{
    [CmdletBinding()]
    [OutputType([int64])]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [String]
        $sizeString
    )
    #find if the size is in MB, GB or TB
    $sizeNotation = $sizeString.Substring($sizeString.Length-2)
    
    $size = [double]($sizeString.Substring(0,$sizeString.Length-3))
    write-verbose "Received $sizeString.`nSeperated this into value: $size with notation $sizeNotation"
    switch ($sizeNotation)
    {
        'GB' {$power = 3; break}
        'TB' {$power = 4; break}
        'MB' {$power = 2 ;break}
        Default {Write-Verbose "$sizeNotation is invalid format exiting script.`nReturning 0 as value";$power='ERROR'}
    }
    write-verbose "Will multiply $size with 1024^$power"
    if($power -eq 'ERROR'){$sizeBytes =[int64] 0}
    else{$sizeBytes = [int64] ($size * [math]::Pow(1024,$power))}
    Return $sizeBytes
}


<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Convert-toBackupWindow
{
    [CmdletBinding()]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true)]
        $day,
        [Parameter(Mandatory=$true)]
        [int]$hour
    )
    
    
    if($hour -lt 7){
        switch ($day)
        {
            'Monday' {$backupwindow = 'Sunday to Monday'}
            'Tuesday'{$backupwindow = 'Monday to Tuesday'}
            'Wednesday'{$backupwindow = 'Tuesday to Wednesday'}
            'Thursday' {$backupwindow = 'Wednesday to Thursday'}
            'Friday' {$backupwindow = 'Thursday to Friday'}
            'Saturday'{$backupwindow = 'Friday to Saturday'}
            'Sunday' {$backupwindow = 'Saturday to Sunday'}
            Default {$backupwindow = 'Not Found'}
        }
    }
    else{
        switch ($day)
        {
            'Monday' {$backupwindow = 'Monday to Tuesday'}
            'Tuesday'{$backupwindow = 'Tuesday to Wednesday'}
            'Wednesday'{$backupwindow = 'Wednesday to Thursday'}
            'Thursday' {$backupwindow = 'Thursday to Friday'}
            'Friday' {$backupwindow =  'Friday to Saturday'}
            'Saturday'{$backupwindow = 'Saturday to Sunday'}
            'Sunday' {$backupwindow ='Sunday to Monday' }
            Default {$backupwindow = 'Not Found'}
        }
    }
    return $backupwindow
}

<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>
function Get-JobData
{
    [CmdletBinding()]
    Param
    (
        # Veeam job parameter
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $Job
    )
    
    write-verbose "Getting job data for $($job.name)"    
    Write-Verbose "`nCollecting when the job is running"
    $monthlySchedule = $job.BackupTargetOptions.FullBackupMonthlyScheduleOptions
    $numberinMonth = $monthlySchedule.DayNumberInMonth
    $fullDayofWeek = $monthlySchedule.DayOfWeek

    #in which hour the job will run
    $jobTimeHour = $job.ScheduleOptions.StartDateTimeLocal.Hour
    #in which minute (of the hour) the job will run
    [string]$jobTimeMinutes = $job.ScheduleOptions.StartDateTimeLocal.Minute

    #if minute only returned one integer add an 0 to the string
    if($jobTimeMinutes.Length -eq 1){$jobTimeMinutes = '0'+$jobTimeMinutes}
    $jobHour = "$jobTimeHour`:"+$jobTimeMinutes
    $backupwindow = Convert-toBackupWindow -day $fullDayofWeek -hour $jobTimeHour


    write-verbose "Done collecting when the job is running. Start collecting how big the job is"
    $vmsinJob = $job.GetObjectsInJob() | sort name
    #create 64 bit integer, because 2 GB in bytes is too big for 32 bit integer
    [int64]$jobsize = 0
    $vmNamesinInjob =""
    foreach($vm in $vmsinJob){
        $jobsize+= (Convert-SizeStringtoSizeInteger $vm.ApproxSizeString)
        $vmNamesinInjob+=$vm.name+';'
    }
    #now round to nearest GB
    [int]$jobsize = $jobsize/1GB

    write-verbose "Done collecting how big the job is. Start collecting on which storage device it is targetting"

    $storagedevice = Get-StorageDevice $job.info.TargetRepositoryId

    
    

    $jobData =[PSCustomObject]@{
                Job = $Job.Name
                'Hour when job is running'=$jobHour
                'Expected Full Job Size (GB)' = $jobsize
                'Backup Storage' = $storagedevice
                'Full: Backup Window' = $backupwindow
                'Full: Week number'=$numberinMonth
                'Full: WeekDay' = $fullDayofWeek
                'VMs in job' = $vmNamesinInjob
                }

    write-verbose "Found this data for $($job.name) : `n`n $jobData"
    return $jobData
}


<#
.Synopsis
   tries to resolve the storagedevice to a friendly name
.DESCRIPTION
   Tries to resolve the storagedevice to a friendly name. This might be nice in case veeam repo's are stored
   on SMB shares and you are only interested in the server name and not the path.
#>
function Get-StorageDevice
{
    [CmdletBinding()]
    [OutputType([string])]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        $RepoID
    )

    $repo = Get-VBRBackupRepository | where{$_.id -eq $RepoID}
    # todo add your own logic here that fits your purpose
    $storagedevice = ($Repo.name)
    return $storagedevice

}

#endregion


#region 2 module:"initialize variables and add needed modules
Add-PSSnapin VeeamPSSnapIn
#endregion


#region 3 module: retrieve data
$backupjobs = Get-VBRJob | Where-Object {$_.IsBackup}
$rapportData =@()
foreach($job in $backupjobs){$rapportData+= Get-JobData $job}

$rapportData | select job,'Hour when job is running','Expected Full Job Size (GB)','Backup Storage','Full: Backup Window'`
                ,'Full: Week number','Full: WeekDay','VMs in job' |
                Export-Csv '.\Veeambackupschedule.csv' -NoTypeInformation


#endregion
