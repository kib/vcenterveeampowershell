## Variables
$vcenter = "your.vcenter.fqdn"
$cluster = "clustername"

## Gather RPools
cls

Write-Host "Connecting to the vCenter server $vcenter"
Connect-VIServer $vcenter
Write-Host "------------------------------------------------------------------"
Write-Host "Resource pools found in the '$cluster' cluster:"
[array]$rpools = Get-ResourcePool -Location (Get-Cluster $cluster) | Sort-Object
Write-Host $rpools
Write-Host "------------------------------------------------------------------"
Write-Host "We normally use these weights for the three resource pools:"
Write-Host "VM's in Production have 1000 relative weight."
Write-Host "VM's in Acceptance have 500 relative weight."
Write-Host "VM's in Test have 250 relative weight."
Write-Host "------------------------------------------------------------------"
Write-Host "Please enter the values you want to use this time:"
## Enumerate Members of RPools
Foreach ($rpool in $rpools)
	{
	If ($rpool.name -ne "Resources")
		{
		Write-Host -ForegroundColor Green -BackgroundColor Black $rpool.name
		[int]$pervmshares = Read-Host "How many shares per VM in the $($rpool.Name) resource pool?"
		$rpoolenabledvms = $rpool |Get-VM | where {$_.PowerState -eq "PoweredOn"}
		$totalvms = $rpoolenabledvms.count
		[int]$rpshares = $pervmshares * $totalvms
		Write-Host "Found $totalvms enabled VM's, using $pervmshares as relative weight per virtual machine."
	    Write-Host "Setting the pool to $totalvms x $pervmshares = " -nonewline
		Write-Host -ForegroundColor Yellow -BackgroundColor Black "$rpshares " -nonewline
		Write-Host "shares. `n"
		Set-ResourcePool -ResourcePool $rpool.Name -CpuSharesLevel:Custom -NumCpuShares $rpshares -MemSharesLevel:Custom -NumMemShares $rpshares | Out-Null
		}
	}