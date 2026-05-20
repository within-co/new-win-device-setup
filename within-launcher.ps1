# WITHIN Launcher v1.1
# Downloaded to C:\Windows\Setup\Scripts\ during specialize pass
# Fires on first login via registry Run key
# Downloads and runs within-setup.ps1 from GitHub

$ProgressPreference = 'SilentlyContinue'
$LogFile = "C:\Windows\Setup\Scripts\within-launcher.log"
$dest    = "C:\Windows\Setup\Scripts\within-setup.ps1"
$url     = "https://raw.githubusercontent.com/within-co/new-win-device-setup/refs/heads/main/within-setup.ps1"

function Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg" | Tee-Object -FilePath $LogFile -Append | Out-Null
}

Log "WITHIN Launcher starting"

# Wait for network - simple sleep-based approach, no Test-NetConnection needed
$maxWait = 120  # wait up to 2 minutes
$waited  = 0
while ($waited -lt $maxWait) {
    try {
        $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Log "Network available after ${waited}s"
        break
    } catch {
        Log "Network not ready, waiting... (${waited}s)"
        Start-Sleep -Seconds 10
        $waited += 10
    }
}

# Download within-setup.ps1
Log "Downloading within-setup.ps1..."
try {
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
    Log "Download successful"
} catch {
    Log "Download failed: $_"
    exit 1
}

# Run the setup script
if (Test-Path $dest) {
    Log "Launching within-setup.ps1"
    & $dest
} else {
    Log "Script not found after download - exiting"
}
