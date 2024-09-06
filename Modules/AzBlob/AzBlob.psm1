function Set-AzBlobContext {
	param (
		[Parameter(Mandatory = $true)]
		[securestring]$Token
	)

	$SCRIPT:AzBlobToken = $Token
}

function Get-AzBlobContent {
	param (
		[Parameter(ParameterSetName = 'Name', Mandatory = $true)]
		[string]$StorageAccountName,
		[Parameter(ParameterSetName = 'Name', Mandatory = $true)]
		[string]$ContainerName,
		[Parameter(ParameterSetName = 'Name', Mandatory = $true)]
		[string]$BlobName,
		[Parameter(ParameterSetName = 'URI')]
		$Uri,
		[securestring]$Token = $SCRIPT:AzBlobToken
	)

	[string]$Uri = $Uri ?? "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName"

	$irmParams = @{
		Authentication = 'Bearer'
		Token          = $Token
		Uri            = $Uri
		Headers        = @{
			'x-ms-version' = '2024-11-04'
		}
	}

	try {
		Write-Verbose "Fetching $Uri"
		$response = Invoke-RestMethod @irmParams
		return $response
	} catch {
		Write-Error "Failed to retrieve blob content: $_"
	}
}

function Set-AzBlobContent {
	param (
		[Parameter(ParameterSetName = 'Name', Mandatory = $true)]
		[string]$StorageAccountName,
		[Parameter(ParameterSetName = 'Name', Mandatory = $true)]
		[string]$ContainerName,
		[Parameter(ParameterSetName = 'Name', Mandatory = $true)]
		[string]$BlobName,
		[Parameter(ParameterSetName = 'URI')]
		$Uri,
		[object]$Content,
		[securestring]$Token = $SCRIPT:AzBlobToken
	)

	[string]$Uri = $Uri ?? "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$BlobName"

	$irmParams = @{
		Authentication = 'Bearer'
		Token          = $Token
		Uri            = $Uri
		Headers        = @{
			'x-ms-version'   = '2024-11-04'
			'x-ms-blob-type' = 'BlockBlob'
		}
		ContentType    = 'application/octet-stream'
		Body           = $Content
		Method         = 'PUT'
	}

	try {
		Write-Host "Fetching $Uri"
		$response = Invoke-RestMethod @irmParams
		return $response
	} catch {
		Write-Error "Failed to retrieve blob content: $_"
	}
}