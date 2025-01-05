# ====================
# CONFIGURATIESECTIE
# ====================
# Vraag de gebruiker om invoer voor de volgende configuratieparameters:

$logBasePath = Read-Host "Voer het pad in voor logbestanden"                  # Locatie van logbestanden
$clixmlFilePath = Read-Host "Voer het pad in voor het CLIXML-configuratiebestand" # Pad naar het CLIXML-bestand met opslagaccountgegevens
$localBackupBasePath = Read-Host "Voer het pad in voor de lokale back-upbestanden" # Lokale map voor backupbestanden
$retentionDays = Read-Host "Voer het aantal dagen in voor de retentieperiode"      # Retentieperiode in dagen

# ====================
# SCRIPT START
# ====================

# Functie om logregels te schrijven
function Write-Log {
    param (
        [string]$message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $message" | Out-File -Append -FilePath $logFile -ErrorAction Stop
}

# Functie om dynamisch het pad van het logbestand te genereren
function Get-LogFilePath {
    $year = (Get-Date).Year
    $month = (Get-Date).ToString("MM")
    $day = (Get-Date).ToString("dd")
    $time = (Get-Date).ToString("HH-mm-ss")
    $logFolder = Join-Path -Path $logBasePath -ChildPath "$year\$month\$day"

    if (-Not (Test-Path -Path $logFolder)) {
        New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    }

    return Join-Path -Path $logFolder -ChildPath "BackupLog_$time.txt"
}

# Functie om oude bestanden te verwijderen volgens de retentiebeleid
function Enforce-Retention {
    param (
        [string]$basePath,
        [int]$days
    )
    $cutoffDate = (Get-Date).AddDays(-$days)
    Get-ChildItem -Path $basePath -Recurse | Where-Object { $_.LastWriteTime -lt $cutoffDate } | Remove-Item -Recurse -Force -ErrorAction Stop
    Write-Log "Verwijderde bestanden ouder dan $days dagen in $basePath."
}

# Initialiseer logbestand
$logFile = Get-LogFilePath
Write-Log "Logbestand geïnitialiseerd: $logFile."

# Laad Azure-configuratie uit CLIXML-bestand
try {
    $azureConfig = Import-Clixml -Path $clixmlFilePath
    Write-Log "Succesvol geladen configuratie uit: $clixmlFilePath."
} catch {
    Write-Log "Fout bij laden van configuratiebestand: $($_.Exception.Message)"
    exit 1
}

# Haal configuratiegegevens op
$storageAccountName = $azureConfig.StorageAccountName
$storageAccountKey = $azureConfig.StorageAccountKey
$containerName = $azureConfig.ContainerId

# Valideer containernaam
if (-not $containerName) {
    Write-Log "Fout: Containernaam ontbreekt. Controleer configuratie."
    exit 1
}

# Maak StorageContext
try {
    Write-Log "Maak verbinding met Azure Storage account: $storageAccountName."
    $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
    Write-Log "Verbonden met Azure Storage account: $storageAccountName."
} catch {
    Write-Log "Fout bij het verbinden met Azure Storage: $($_.Exception.Message)"
    exit 1
}

# Pas retentiebeleid toe
Write-Log "Pas retentiebeleid toe op: $localBackupBasePath."
Enforce-Retention -basePath $localBackupBasePath -days $retentionDays

# Download blobs
try {
    Write-Log "Haal blobs op uit container: $containerName."
    $blobs = Get-AzStorageBlob -Container $containerName -Context $storageContext

    if ($blobs.Count -eq 0) {
        Write-Log "Geen blobs gevonden in container: $containerName. Script beëindigd."
        exit 0
    }

    Write-Log "Start met downloaden van blobs."
    foreach ($blob in $blobs) {
        $destinationFolder = Join-Path -Path $localBackupBasePath -ChildPath (Get-Date).ToString("yyyy/MM/dd")
        if (-Not (Test-Path -Path $destinationFolder)) {
            New-Item -Path $destinationFolder -ItemType Directory -Force | Out-Null
        }
        $localFilePath = Join-Path -Path $destinationFolder -ChildPath $blob.Name

        try {
            Get-AzStorageBlobContent -Blob $blob.Name -Container $containerName -Destination $localFilePath -Context $storageContext -Force
            Write-Log "Blob gedownload: $($blob.Name) naar $localFilePath."
        } catch {
            Write-Log "Fout bij downloaden van blob: $($blob.Name). Fout: $($_.Exception.Message)"
        }
    }
    Write-Log "Blobs succesvol gedownload."
} catch {
    Write-Log "Fout bij blobverwerking: $($_.Exception.Message)"
} finally {
    Write-Log "Azure Backup Script beëindigd."
}
