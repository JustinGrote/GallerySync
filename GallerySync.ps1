#!/usr/bin/env pwsh
#requires -module AzAuth,AzBlob
param(
	$checkpointName = 'checkpoint-gallerysync',
	#How many to download in a single batch from the gallery. The max for this is 100
	$downloadBatchSize = 100,
	#How many to batch before sending to Sleet. The max is recommended to be less than 4096 since Sleet will batch it anyways at that size. Ensure you have enough disk space to support this number of packages.
	$processBatchSize = $ENV:PROCESS_BATCH_SIZE ?? 500,
	#How many days to go back in history if no checkpoint has been detected yet.
	$defaultHistoryDays = $ENV:DEFAULT_HISTORY_DAYS ?? 7,
	$concurrentDownloads = 30
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (-not (Get-Command sleet)) {
	Write-Host 'Sleet not found in path. Please ensure Sleet is installed and available in the path.'
	exit 1
}

function Get-AzManagedIdentityToken {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Resource,
		[string]$ClientId
	)
	if (-not $env:IDENTITY_ENDPOINT) {
		throw 'Managed Identity has not been enabled in this environment (IDENTITY_ENDPOINT env varis not set).'
	}
	if (-not $env:IDENTITY_HEADER) {
		throw 'Managed Identity has not been enabled in this environment (IDENTITY_HEADER env varis not set).'
	}
	$irmParams = @{
		Uri         = $env:IDENTITY_ENDPOINT + "?api-version=2019-08-01&resource=$Resource"
		Headers     = @{
			'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER
			'Metadata'          = 'true'
		}
		Method      = 'GET'
		ContentType = 'application/json'
		# Body = @{
		# 	'api-version' = '2019-08-01'
		# 	resource = $Resource
		# }
	}
	# if ($ClientId) {
	# 	$irmParams.Body.client_id = $ClientId
	# }
	$response = Invoke-RestMethod @irmParams
	if (-not $response.access_token) {
		throw 'Managed Identity token could not be retrieved. (No access_token in response)'
	}
	return $response.access_token | ConvertTo-SecureString -AsPlainText
}

$token = Get-AzManagedIdentityToken -Resource 'https://storage.azure.com'
Set-AzBlobContext -Token $token

$checkpointPath = $($ENV:SLEET_FEED_PATH + "/$checkpointName")
[string]$checkpoint = try {
	Get-AzBlobContent -Uri $checkpointPath
} catch {
	Write-Host "Checkpoint not found, defaulting to $defaultHistoryDays ago"
	if ($PSItem -notmatch 'BlobNotFound') { throw }
	(Get-Date).AddDays(-$defaultHistoryDays).ToString('o')
}
"Checkpoint: $checkpoint"
$processed = 0
$i = 0
$processLastBatch = $false
$firstScan = $true
$SCRIPT:newCheckpoint = $null
while ($true) {
	Write-Host "Retrieving package info $i-$($i + $downloadBatchSize) from Gallery since $SCRIPT:newCheckpoint"
	$irmParams = @{
		Uri  = 'https://www.powershellgallery.com/api/v2/Packages'
		Body = @{
			'$filter'         = "Created gt datetime'$checkpoint'"
			'$orderby'        = 'Created'
			'$select'         = 'Created'
			'$skip'           = $i
			'$top'            = $downloadBatchSize
			includePrerelease = $true
		}
	}
	try {
		[Array[]]$packages = Invoke-RestMethod @irmParams
	} catch {
		# Wait 10 seconds for non permanent errors and retry
		if ($PSItem.Exception.Response.StatusCode -eq 429 -or $PSItem.Exception.Response.StatusCode -eq 503) {
			Write-Host "Gallery returned $($PSItem.Exception.Response.StatusCode) $($PSItem.Exception.Message). Waiting 10 seconds and retrying."
			Start-Sleep -Seconds 10
			continue
		}
	}

	$onDiskPackageCount = (Get-Item $PWD\*.nupkg).Count
	if ($packages.count -eq 0) {
		Write-Host 'No packages found'
		if ($onDiskPackageCount -eq 0) {
			Write-Host 'No packages left on disk'
			if ($firstScan) {
				Write-Host 'No packages found in gallery since checkpoint. Exiting.'
				exit 0
			} else {
				Write-Host 'No more packages to process! Exiting.'
			}
			break
		} else {
			Write-Host "$onDiskPackageCount packages left on disk. Processing them."
		}
		$processLastBatch = $true
	}
	$firstScan = $false

	Write-Host "Downloading $($packages.count) packages"
	$packages | ForEach-Object -Throttle $concurrentDownloads -Parallel {
		$maxDownloadRetries = 3
		for ($attempt = 1; $attempt -le $maxDownloadRetries; $attempt++) {
			try {
				Invoke-WebRequest $PSItem.content.src -OutFile "$(New-Guid).nupkg" -ErrorAction Stop
				break
			} catch {
				if ($attempt -ge $maxDownloadRetries) {
					throw "Failed to download package $($PSItem.id) $($PSItem.version) after $maxDownloadRetries attempts: $($PSItem.Exception.Message)"
				}
				Write-Host "Failed to download package $($PSItem.id) $($PSItem.version): $($PSItem.Exception.Message). Retrying in 5 seconds ($attempt/$maxDownloadRetries)."
				Start-Sleep -Seconds 5
			}
		}
	}

	$onDiskPackageCount = (Get-Item $PWD\*.nupkg).Count

	if ($packages.count -gt 0) {
		$SCRIPT:newCheckpoint = $packages[-1].Properties.Created.'#text'
		Write-Host "New checkpoint: $SCRIPT:newCheckpoint"
		if (-not $SCRIPT:newCheckpoint) {
			throw 'No Created property found on last package. This is a bug.'
		}
	}

	if (-not $processLastBatch -and $onDiskPackageCount -lt $processBatchSize) {
		Write-Host "Batch size of $onDiskPackageCount does not yet meet process size of $processBatchSize. Fetching more packages."
		$i += $downloadBatchSize
		continue
	}

	Write-Host "Processing batch of $onDiskPackageCount packages"
	& sleet push --skip-existing $PWD

	$processed += (Get-Item -Path $PWD\*.nupkg).Count
	Remove-Item -Path $PWD\*.nupkg -Force

	if (-not $SCRIPT:newCheckpoint) {
		throw 'No new checkpoint found after processing batch. This is a bug.'
	}
	Write-Host "Checkpoint roll forward to $SCRIPT:newCheckpoint"
	Set-AzBlobContent -Uri $checkpointPath -Content $SCRIPT:newCheckpoint

	if ($processLastBatch) { "$processed Packages Processed"; break }
}
