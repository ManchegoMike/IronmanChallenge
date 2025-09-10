#-------------------------------------------------------------------------------
# Development folder
#-------------------------------------------------------------------------------

$sourceFolder = "."

#-------------------------------------------------------------------------------
# Destination folders
#-------------------------------------------------------------------------------

$destFolders = @(
    "D:\Games\World of Warcraft\_classic_era_\Interface\AddOns\IronmanChallenge",
    "D:\Games\Ascension Launcher\resources\epoch_live\Interface\Addons\IronmanChallenge"
)

#-------------------------------------------------------------------------------
# Create the FileSystemWatcher
#-------------------------------------------------------------------------------

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $sourceFolder
$watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite'

$lastCopied = @{}  # store last copy time per file

#-------------------------------------------------------------------------------
# Action to perform on file change
#-------------------------------------------------------------------------------

$action = {

    $path = $Event.SourceEventArgs.FullPath
    $name = $Event.SourceEventArgs.Name
    $ext = [System.IO.Path]::GetExtension($name).ToLower()

    if ($ext -eq ".lua" -or $ext -eq ".md") {

        $now = Get-Date
        $last = $lastCopied[$path]

        # Skip if copied within last 200ms
        if ($last -and ($now - $last).TotalMilliseconds -lt 200) { return }

        # Delay a fraction of a second to allow save to complete
        Start-Sleep -Milliseconds 100

        foreach ($dest in $destFolders) {

            # Ensure destination folder exists
            if (-not (Test-Path $dest)) {
                New-Item -ItemType Directory -Force -Path $dest | Out-Null
            }

            # Copy file
            Copy-Item $path -Destination (Join-Path $dest $name) -Force
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Copied $name -> $dest"

            # Update last copied timestamp
            $lastCopied[$path] = Get-Date

        }
    }
}

#-------------------------------------------------------------------------------
# Register event
#-------------------------------------------------------------------------------

Register-ObjectEvent $watcher "Changed" -Action $action

#-------------------------------------------------------------------------------
# Keep script running
#-------------------------------------------------------------------------------

Write-Host "Watching $sourceFolder for file changes. Press Ctrl+C to stop."
while ($true) { Start-Sleep 1 }
