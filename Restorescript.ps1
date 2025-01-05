# Install necessary modules (if not already installed)
Install-Module -Name AWSPowerShell -Force -Scope CurrentUser
Install-Module -Name Az -Force -Scope CurrentUser

# AWS S3 Credentials and Bucket Information
$AWSAccessKey = "YourAWSAccessKey"
$AWSSecretKey = "YourAWSSecretKey"
$S3BucketName = "YourS3BucketName"
$S3Region = "YourAWSRegion" # Example: us-west-2

# Azure Storage Account Information
$AzureStorageAccountName = "YourAzureStorageAccountName"
$AzureStorageAccountKey = "YourAzureStorageAccountKey"
$AzureBlobContainer = "YourAzureBlobContainerName"

# Set AWS Credentials
Set-AWSCredential -AccessKey $AWSAccessKey -SecretKey $AWSSecretKey -StoreAs "AWSProfile"

# Authenticate to Azure
$AzureContext = New-AzStorageContext -StorageAccountName $AzureStorageAccountName -StorageAccountKey $AzureStorageAccountKey

# List objects in the S3 bucket
Write-Output "Listing objects in the S3 bucket: $S3BucketName"
$S3Objects = Get-S3Object -BucketName $S3BucketName -Region $S3Region

foreach ($S3Object in $S3Objects) {
    # Download the S3 object to a local temporary file
    $TempFile = Join-Path -Path $env:TEMP -ChildPath $S3Object.Key
    Write-Output "Downloading $($S3Object.Key) from S3 to $TempFile"
    Read-S3Object -BucketName $S3BucketName -Key $S3Object.Key -File $TempFile -Region $S3Region

    # Upload the file to Azure Blob Storage
    Write-Output "Uploading $($S3Object.Key) to Azure Blob Storage container: $AzureBlobContainer"
    Set-AzStorageBlobContent -File $TempFile -Container $AzureBlobContainer -Blob $S3Object.Key -Context $AzureContext

    # Remove the temporary file after upload
    Remove-Item -Path $TempFile -Force
}

Write-Output "Data transfer from S3 to Azure Blob Storage completed successfully."
