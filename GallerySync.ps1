#!/usr/bin/env pwsh
#requires -module AzAuth,AzBlob
param(
	$checkpointName = 'checkpoint-gallerysync',
	#How many to download in a single batch from the gallery. The max for this is 100
	$downloadBatchSize = 100,
	#How many to batch before sending to Sleet. The max is recommended to be less than 4096 since Sleet will batch it anyways at that size. Ensure you have enough disk space to support this number of packages.
	$processBatchSize = 500,
	#How many days to go back in history if no checkpoint has been detected yet.
	$defaultHistoryDays = 7,
	$concurrentDownloads = 30
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$token = Get-AzToken -ClientId $env:AZURE_CLIENT_ID -TenantId $ENV:AZURE_TENANT_ID -ClientSecret $env:AZURE_CLIENT_SECRET -Resource 'https://storage.azure.com'
Set-AzBlobContext -Token ($token.Token | ConvertTo-SecureString -AsPlainText)
$checkpointPath = $($ENV:SLEET_FEED_PATH + "/$checkpointName")
[string]$checkpoint = try {
	Get-AzBlobContent -Uri $checkpointPath
} catch {
	Write-Host "Checkpoint not found, defaulting to $defaultHistoryDays ago"
	if ($PSItem -notmatch 'BlobNotFound') { throw }
	(Get-Date).AddDays(-$defaultHistoryDays).ToString('o')
}
"Checkpoint: $checkpoint"

$i = 0

while ($true) {
	Write-Host "Processing batch $i"
	$irmParams = @{
		Uri  = 'https://www.powershellgallery.com/api/v2/Search()'
		Body = @{
			'$filter'         = "Published gt datetime'$checkpoint'"
			'$orderby'        = 'Published'
			'$inlinecount'    = 'allpages'
			'$skip'           = $i
			'$top'            = $downloadBatchSize
			includePrerelease = $true
		}
	}
	$packages = Invoke-RestMethod @irmParams
	if (-not $packages) { 'All packages processed'; break }

	$i += $downloadBatchSize
	$packages | ForEach-Object -Throttle $concurrentDownloads -Parallel {
		Write-Host "Downloading $($_.content.src)"
		Invoke-WebRequest $PSItem.content.src -OutFile "$(New-Guid).nupkg"
	}
	if ((Get-Item $PWD\*.nupkg).Count -lt $processBatchSize) {
		Write-Host "Batch size of $($packages.Count) does not yet meet process size of $processBatchSize. Fetching more packages."
		continue
	}
	Write-Host "Processing batch of $($packages.Count) packages"

	& sleet push --skip-existing $PWD
	$newCheckpoint = $packages[-1].properties.Created.'#text'
	if (-not $newCheckpoint) { throw 'No Created date found on last package in batch. This is a bug' }
	Set-AzBlobContent -Uri $checkpointPath -Content $newCheckpoint
	Write-Host "Checkpoint Rolled Forward to: $newCheckpoint"
	Remove-Item -Path $PWD\*.nupkg -Force
}