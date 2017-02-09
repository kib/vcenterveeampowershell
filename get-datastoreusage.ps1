# Script created by Mohammed Raffic on December 21, 2013
# and published on http://www.vmwarearena.com/powershell-script-to-collect-datastore/
# modified by Rikkert Kooy for a customer by adding provisioned space numbers and disconnect

add-pssnapin VMware.VimAutomation.Core
$vcenterserver = "your.server.fqdn"

#this will prompt you for your credentials to connect to vcenter
Connect-VIServer $vcenterserver

Function Percentcal {
    param(
    [parameter(Mandatory = $true)]
    [int]$InputNum1,
    [parameter(Mandatory = $true)]
    [int]$InputNum2)
    [math]::round(($InputNum1 / $InputNum2*100),2)
}

$datastores = Get-Datastore | Sort Name
ForEach ($ds in $datastores)
{
    if (($ds.Name -match “Shared”) -or ($ds.Name -match “”))
    {
        $PercentFree = Percentcal $ds.FreeSpaceMB $ds.CapacityMB
        $ds | Add-Member -type NoteProperty -name PercentFree -value $PercentFree

        $ProvisionedSpaceGB = [Math]::Round(($ds.extensiondata.summary.capacity - $ds.extensiondata.summary.freespace + $ds.ExtensionData.Summary.uncommitted)/1GB,0)
        $PercentProvisioned = Percentcal ($ProvisionedSpaceGB*1024) $ds.CapacityMB
        $ds | Add-Member -Type NoteProperty -name ProvisionedSpaceGB -Value $ProvisionedSpaceGB
        $ds | Add-Member -Type NoteProperty -name PercentProvisioned -Value $PercentProvisioned
    }
}

#outputs the data in a csv file in the same location as the script
$datastores | Select Name,@{N=”UsedSpaceGB”;E={[Math]::Round(($_.ExtensionData.Summary.Capacity – $_.ExtensionData.Summary.FreeSpace)/1GB,0)}},@{N=”TotalSpaceGB”;E={[Math]::Round(($_.ExtensionData.Summary.Capacity)/1GB,0)}},ProvisionedSpaceGB,PercentFree,PercentProvisioned | Export-Csv ".\datastorereport-$(Get-Date -Format yyyyMMdd).csv" -NoTypeInformation
Disconnect-VIServer $vcenterserver