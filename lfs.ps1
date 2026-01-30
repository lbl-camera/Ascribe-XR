# PowerShell Script to Find Blob Objects Larger Than 1MB from Git Log

# Get all git object hashes from the master branch
$objects = git rev-list --objects master

# Filter for blob objects larger than 10MB (10000000 bytes)
$largeBlobs = $objects | Where-Object {
    $_.ObjectType -eq "blob" -and $_.Size -gt 10000000
}

# Sort unique object sizes.
$sortedBlobs = $largeBlobs | Sort-Object -Property Size -Unique

# Display the sorted list of sizes
$sortedBlobs | ForEach-Object {
    Write-Host $_.Size
}