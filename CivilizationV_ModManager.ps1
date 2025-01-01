[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$gameRootPath,

    [Parameter(Mandatory = $true)]
    [string]$steamINI ,
    
    [Parameter(Mandatory = $true)]
    [string]$onlineJsonUrl
)

# Add version number after param block
$SCRIPT_VERSION = "1.0.5"

# Add schema version check function
function Test-SchemaVersion {
    param([PSObject]$onlineData)
    
    $requiredVersion = "1.0"
    if ($onlineData.schemaVersion -ne $requiredVersion) {
        throw "Incompatible online JSON schema version. Required: $requiredVersion, Found: $($onlineData.schemaVersion)"
    }
}

# Add self-update function
function Update-Script {
    param(
        [string]$updateUrl,
        [string]$currentPath,
        [string]$currentVersion
    )
    
    try {
        $newContent = (Invoke-WebRequest -Uri $updateUrl -UseBasicParsing).Content.Trim()
        
        # Extract version from new content
        if ($newContent -match '\$SCRIPT_VERSION\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"') {
            $newVersion = $matches[1]
            
            # Compare versions
            $current = [version]$currentVersion
            $new = [version]$newVersion
            
            if ($new -gt $current) {
                Write-ColorMessage "New script version available ($newVersion). Current version: $currentVersion" -Color "Yellow"
                Write-ColorMessage "Update? (Y/N)" -Color "Yellow"
                $timeoutTask = Start-Job { Start-Sleep -Seconds 5 }
                
                while ($timeoutTask.State -eq 'Running') {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Y') {
                            $newContent | Set-Content -Path $currentPath -NoNewline
                            Write-ColorMessage "Script updated successfully to version $newVersion" -Color "Green"
                            Stop-Job $timeoutTask
                            Remove-Job $timeoutTask
                            Start-Process powershell -ArgumentList "-File `"$currentPath`" -gameRootPath `"$gameRootPath`" -steamINI `"$steamINI`" -onlineJsonUrl `"$onlineJsonUrl`""
                            exit
                        } elseif ($key.Key -eq 'N') {
                            Write-ColorMessage "Update skipped" -Color "Yellow"
                            break
                        }
                    }
                }
                Stop-Job $timeoutTask
                Remove-Job $timeoutTask
            }
        } else {
            Write-ColorMessage "Could not determine version of update script" -Color "Red"
        }
    } catch {
        Write-ColorMessage "Error checking for updates: $_" -Color "Red"
    }
}

# Function to handle JSON caching and retrieval
function Get-CachedJsonData {
    param(
        [string]$onlineJsonUrl,
        [string]$gameRootPath
    )
    
    $cachedJsonPath = Join-Path $gameRootPath "modmanager_cache.json"
    $result = @{
        Data     = $null
        IsOnline = $false
    }
    
    try {
        # Try to get online data first
        Write-ColorMessage -Message "Getting online resources" -Color "Blue"
        $onlineData = Invoke-WebRequest -Uri $onlineJsonUrl -UseBasicParsing | ConvertFrom-Json
        
        # Cache the successful response
        $onlineData | ConvertTo-Json -Depth 10 | Set-Content -Path $cachedJsonPath -Force
        Write-ColorMessage "Successfully retrieved and cached online game mode data" -Color "Green"
        
        $result.Data = $onlineData
        $result.IsOnline = $true
        return $result
    } catch {
        # If online fetch fails, try to use cached data
        if (Test-Path $cachedJsonPath) {
            Write-ColorMessage "Cannot access online data, using cached configuration" -Color "Yellow"
            try {
                $cachedData = Get-Content $cachedJsonPath | ConvertFrom-Json
                $result.Data = $cachedData
                $result.IsOnline = $false
                return $result
            } catch {
                Write-ColorMessage "Error reading cached data: $_" -Color "Red"
                return $result
            }
        } else {
            Write-ColorMessage "No cached configuration available" -Color "Yellow"
            return $result
        }
    }
}


# Function to write colored console messages with section headers
function Write-ColorMessage {
    param(
        [string]$Message,
        [string]$Color = "White",
        [switch]$IsHeader = $false
    )
    if ($IsHeader) {
        Write-Host ("=" * 100) -ForegroundColor "Gray"
        Write-Host $Message -ForegroundColor $Color
        Write-Host ("=" * 100) -ForegroundColor "Gray"
        Write-Host " "
    } else {
        Write-Host $Message -ForegroundColor $Color
    }
}

# Function to check and create directory if it doesn't exist
function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-ColorMessage "Created directory: $Path" -Color "Yellow"
    }
}

# Function to backup save games
function Backup-SaveGames {
    $savePath = Join-Path $myDocumentsGamePath "Saves"
    if (Test-Path $savePath) {
        $backupPath = Join-Path $myDocumentsGamePath "Saves_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-ColorMessage "Backing up save games to: $backupPath" -Color "Cyan"
        try {
            Copy-Item -Path $savePath -Destination $backupPath -Recurse -Force
            Write-ColorMessage "Save games backed up successfully" -Color "Green"
        } catch {
            Write-ColorMessage "Failed to backup save games: $_" -Color "Red"
        }
    }
}

# Function to manage cached downloads
function Get-CachedDownload {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$ModeName,
        [Parameter(Mandatory = $true)]
        [ValidateSet("DLC", "MyDocuments")]
        [string]$LocationType
    )
    
    # Create cache directory structure
    $cacheBasePath = Join-Path $gameRootPath "ModCache"
    $modeCache = Join-Path $cacheBasePath ($ModeName -replace '[\\/:*?"<>|]', '_')
    $versionCache = Join-Path $modeCache $Version
    $locationCache = Join-Path $versionCache $LocationType
    
    # Create cache directory if it doesn't exist
    Ensure-Directory $locationCache
    
    # Generate cache file path
    $fileName = [System.IO.Path]::GetFileName($Url)
    $cachePath = Join-Path $locationCache $fileName
    
    # Check if file exists in cache with correct version
    if (Test-Path $cachePath) {
        Write-ColorMessage "Using cached version of $fileName" -Color "Cyan"
        return $cachePath
    }
    
    # If not in cache, download and store in cache
    try {
        Write-ColorMessage "Downloading $fileName to cache" -Color "Blue"
        Invoke-WebRequest -Uri $Url -OutFile $cachePath
        Write-ColorMessage "Successfully cached $fileName" -Color "Green"
        return $cachePath
    } catch {
        Write-ColorMessage "Error downloading to cache: $_" -Color "Red"
        if (Test-Path $cachePath) {
            Remove-Item $cachePath -Force
        }
        return $null
    }
}

# Function to clean old cache entries
function Clear-OldCache {
    param(
        [Parameter(Mandatory = $true)]
        [array]$CurrentModes
    )
    
    $cacheBasePath = Join-Path $gameRootPath "ModCache"
    if (-not (Test-Path $cacheBasePath)) {
        return
    }
    
    Write-ColorMessage "`nChecking for outdated cache entries..." -Color "Blue"
    
    # Get all cached mode directories
    $cachedModes = Get-ChildItem -Path $cacheBasePath -Directory
    
    foreach ($modeDir in $cachedModes) {
        # Find corresponding mode in current modes
        $currentMode = $CurrentModes | Where-Object { ($_.Name -replace '[\\/:*?"<>|]', '_') -eq $modeDir.Name }
        
        if ($null -eq $currentMode) {
            # Mode no longer exists, remove entire directory
            Write-ColorMessage "Removing cache for obsolete mode: $($modeDir.Name)" -Color "Yellow"
            Remove-Item $modeDir.FullName -Recurse -Force
            continue
        }
        
        # Check versions
        $versionDirs = Get-ChildItem -Path $modeDir.FullName -Directory
        foreach ($versionDir in $versionDirs) {
            $isCurrentVersion = $false
            if ($currentMode.OnlineVersion.DLC -eq $versionDir.Name -or 
                $currentMode.OnlineVersion.MyDocuments -eq $versionDir.Name) {
                $isCurrentVersion = $true
            }
            
            if (-not $isCurrentVersion) {
                Write-ColorMessage "Removing outdated version cache: $($modeDir.Name) v$($versionDir.Name)" -Color "Yellow"
                Remove-Item $versionDir.FullName -Recurse -Force
            }
        }
    }
}

# Download-AndExtract function to use cache
function Download-AndExtract {
    param(
        [string]$Url,
        [string]$TargetPath,
        [string]$Version,
        [string]$ModeName,
        [string]$LocationType
    )
    
    if ([string]::IsNullOrEmpty($Url)) {
        return $true
    }
    
    try {
        # Get file from cache or download
        $sourcePath = Get-CachedDownload -Url $Url -Version $Version -ModeName $ModeName -LocationType $LocationType
        
        if ($null -eq $sourcePath) {
            return $false
        }
        
        Write-ColorMessage "Extracting to: $TargetPath" -Color "Cyan"
        Expand-Archive -Path $sourcePath -DestinationPath $TargetPath -Force
        Write-ColorMessage "Extraction complete" -Color "Green"
        return $true
    } catch {
        Write-ColorMessage "Error during extraction: $_" -Color "Red"
        return $false
    }
}

# Function to clean up files and folders
function Clean-GameFiles {
    param(
        [array]$FilesToClean,
        [bool]$cleanupEnabled,
        [string]$location  # Add location parameter to specify DLC or MyDocuments
    )
    if (-not $cleanupEnabled) {
        Write-ColorMessage "Cleanup disabled in settings, skipping..." -Color "Yellow"
        return
    }

    Write-ColorMessage "`nCleaning up $location files..." -Color "Blue"

    foreach ($file in $FilesToClean) {
        # Only process files/folders for the specified location
        $isCorrectLocation = ($location -eq "DLC" -and $file.StartsWith("DLC/")) -or 
        ($location -eq "MyDocuments" -and $file.StartsWith("MyDocuments/")) 
        
        if ($isCorrectLocation) {
            $fullPath = $file -replace "^MyDocuments/", "$myDocumentsGamePath\" -replace "^DLC/", "$dlcFolderPath\"
            if (Test-Path $fullPath) {
                try {
                    Remove-Item -Path $fullPath -Recurse -Force
                    Write-ColorMessage "Cleaned up: $fullPath" -Color "Yellow"
                } catch {
                    Write-ColorMessage "Error cleaning up $fullPath : $_" -Color "Red"
                }
            }
        }
    }
    Write-ColorMessage "Cleaning up $location files successful" -Color "Green"
}

# Function to update local version file
function Update-LocalVersion {
    param(
        [string]$Mode,
        [PSObject]$Version,
        [string]$Location,
        [string]$BasePath
    )
    $versionFile = Join-Path $BasePath "version_$($Location.ToLower()).json"
    $versionInfo = @{
        Mode     = $Mode
        Version  = $Version
        LastRun  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Location = $Location
    }
    $versionInfo | ConvertTo-Json | Set-Content -Path $versionFile
}

# Function to clear cache directories
function Clear-CacheDirectories {
    param(
        [string]$myDocumentsPath
    )
    $cacheDirs = @(
        (Join-Path $myDocumentsPath "cache"),
        (Join-Path $myDocumentsPath "ModUserData")
    )

    foreach ($dir in $cacheDirs) {
        if (Test-Path $dir) {
            try {
                Remove-Item -Path $dir\* -Recurse -Force
                Write-ColorMessage "Cleared cache directory: $dir" -Color "Yellow"
            } catch {
                Write-ColorMessage "Error clearing cache directory $dir : $_" -Color "Red"
            }
        }
    }
    Write-ColorMessage "Cleared cache directory" -Color "Green"
}

# Function to check if cache clearing is needed
function Test-NeedsCacheClearing {
    param(
        [PSObject]$dlcVersion,
        [PSObject]$myDocsVersion,
        [PSObject]$selectedMode
    )
    
    # If either version file is missing, we need to clear cache
    if ($null -eq $dlcVersion -or $null -eq $myDocsVersion) {
        Write-ColorMessage "`nCache clearing needed: Missing version information" -Color "Blue"
        return $true
    }

    # Check if either DLC or MyDocuments has a different mode
    if ($dlcVersion.Mode -ne $selectedMode.Name -or $myDocsVersion.Mode -ne $selectedMode.Name) {
        Write-ColorMessage "`nCache clearing needed: Mode change detected" -Color "Blue"
        return $true
    }

    # Check if either location has a newer version available
    if ($dlcVersion.Version -ne $selectedMode.OnlineVersion.DLC -or 
        $myDocsVersion.Version -ne $selectedMode.OnlineVersion.MyDocuments) {
        Write-ColorMessage "`nCache clearing needed: New version available" -Color "Blue"
        return $true
    }

    Write-ColorMessage "`nNo cache clearing needed" -Color "Green"
    return $false
}

# Function to wrap text with proper indentation using console width
function Format-Description {
    param (
        [string]$text,
        [int]$indent = 4,
        # Default to console width, fallback to 100 if console width can't be determined
        [int]$maxWidth = $(try { 
                $host.UI.RawUI.WindowSize.Width 
            } catch { 
                try { 
                    $host.UI.RawUI.BufferSize.Width 
                } catch { 
                    100  # Fallback width
                }
            })
    )
    
    # Ensure we have some reasonable minimum width
    $maxWidth = [Math]::Max(40, $maxWidth)
    
    # Account for indent in available width
    $availableWidth = $maxWidth - $indent
    
    $indentStr = " " * $indent
    $words = $text -split '\s+'
    $lines = @()
    $currentLine = $indentStr
    
    foreach ($word in $words) {
        # Check if this word alone is longer than available width
        if ($word.Length -gt $availableWidth) {
            # If current line has content, add it to lines
            if ($currentLine -ne $indentStr) {
                $lines += $currentLine.TrimEnd()
                $currentLine = $indentStr
            }
            # Split long word across lines
            $remainingWord = $word
            while ($remainingWord.Length -gt $availableWidth) {
                $lines += $indentStr + $remainingWord.Substring(0, $availableWidth)
                $remainingWord = $remainingWord.Substring($availableWidth)
            }
            $currentLine = $indentStr + $remainingWord
        }
        # Normal word wrapping
        elseif (($currentLine.Length + $word.Length + 1) -gt $maxWidth) {
            $lines += $currentLine.TrimEnd()
            $currentLine = $indentStr + $word
        } else {
            if ($currentLine -eq $indentStr) {
                $currentLine += $word
            } else {
                $currentLine += " $word"
            }
        }
    }
    
    if ($currentLine -ne $indentStr) {
        $lines += $currentLine.TrimEnd()
    }
    
    return $lines -join "`n"
}

# Function to get the last used mode name
function Get-LastUsedMode {
    param (
        [string]$dlcVersionFile,
        [string]$myDocsVersionFile
    )
    
    try {
        if (Test-Path $myDocsVersionFile) {
            $myDocsVersion = Get-Content $myDocsVersionFile | ConvertFrom-Json
            return $myDocsVersion.Mode
        } elseif (Test-Path $dlcVersionFile) {
            $dlcVersion = Get-Content $dlcVersionFile | ConvertFrom-Json
            return $dlcVersion.Mode
        } 
    } catch {
        return $null
    }
    return $null
}

# Function to manage save games for different modes
function Manage-SaveGames {
    param(
        [string]$currentMode,
        [string]$previousMode,
        [string]$savePath,
        [string]$backupBasePath
    )
    
    # Create the backup root directory if it doesn't exist
    $backupRootPath = Join-Path $backupBasePath "ModeSaves"
    Ensure-Directory $backupRootPath

    # Ensure save directory exists
    Ensure-Directory $savePath

    Write-ColorMessage "`nManaging save games..." -Color "Blue"

    # If there was a previous mode, backup its saves
    if ($previousMode) {
        $previousModeBackupPath = Join-Path $backupRootPath ($previousMode -replace '[\\/:*?"<>|]', '_')
        
        # Check if there are any files to backup (recursively)
        $hasFiles = Get-ChildItem -Path $savePath -File -Recurse
        
        if ($hasFiles) {
            Write-ColorMessage "Backing up $previousMode save games..." -Color "Cyan"
            
            # Create mode backup directory
            Ensure-Directory $previousModeBackupPath
            
            try {
                # Get all files with their relative paths
                $files = Get-ChildItem -Path $savePath -File -Recurse
                
                foreach ($file in $files) {
                    # Calculate relative path from save directory
                    $relativePath = $file.FullName.Substring($savePath.Length + 1)
                    $targetFile = Join-Path $previousModeBackupPath $relativePath
                    $targetDir = Split-Path $targetFile -Parent
                    
                    # Ensure target directory exists
                    if (-not (Test-Path $targetDir)) {
                        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                    }
                    
                    # Copy file to backup location
                    Copy-Item -Path $file.FullName -Destination $targetFile -Force
                    # Remove original file
                    Remove-Item -Path $file.FullName -Force
                }
                
                Write-ColorMessage "Successfully backed up save games for $previousMode" -Color "Green"
            } catch {
                Write-ColorMessage "Error backing up saves: $_" -Color "Red"
            }
        }
    }

    # Restore saves for the selected mode if they exist
    $selectedModeBackupPath = Join-Path $backupRootPath ($currentMode -replace '[\\/:*?"<>|]', '_')
    if (Test-Path $selectedModeBackupPath) {
        Write-ColorMessage "Restoring $currentMode save games..." -Color "Cyan"
        
        try {
            # Get all files with their relative paths from backup
            $files = Get-ChildItem -Path $selectedModeBackupPath -File -Recurse
            
            foreach ($file in $files) {
                # Calculate relative path from backup directory
                $relativePath = $file.FullName.Substring($selectedModeBackupPath.Length + 1)
                $targetFile = Join-Path $savePath $relativePath
                $targetDir = Split-Path $targetFile -Parent
                
                # Ensure target directory exists
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }
                
                # Copy file to saves location
                Copy-Item -Path $file.FullName -Destination $targetFile -Force
            }
            Write-ColorMessage "Successfully restored save games for $currentMode" -Color "Green"
        } catch {
            Write-ColorMessage "Error restoring saves: $_" -Color "Red"
        }
    }
}

# Add new function to check if mode is available offline
function Test-ModeOfflineAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$mode,
        [Parameter(Mandatory = $true)]
        [string]$gameRootPath
    )
    
    $cacheBasePath = Join-Path $gameRootPath "ModCache"
    $modeCache = Join-Path $cacheBasePath ($mode.Name -replace '[\\/:*?"<>|]', '_')
    
    # Check DLC cache if DLCDownload is specified
    if ($mode.DLCDownload) {
        $dlcCache = Join-Path $modeCache $mode.OnlineVersion.DLC
        $dlcCache = Join-Path $dlcCache "DLC"
        $dlcFileName = [System.IO.Path]::GetFileName($mode.DLCDownload)
        $dlcFilePath = Join-Path $dlcCache $dlcFileName
        
        if (-not (Test-Path $dlcFilePath)) {
            return $false
        }
    }
    
    # Check MyDocuments cache if DocsDownload is specified
    if ($mode.DocsDownload) {
        $docsCache = Join-Path $modeCache $mode.OnlineVersion.MyDocuments
        $docsCache = Join-Path $docsCache "MyDocuments"
        $docsFileName = [System.IO.Path]::GetFileName($mode.DocsDownload)
        $docsFilePath = Join-Path $docsCache $docsFileName
        
        if (-not (Test-Path $docsFilePath)) {
            return $false
        }
    }
    
    # If we get here, either all required caches exist or no downloads are needed
    return $true
}

# Modified Show-ModeMenu function
function Show-ModeMenu {
    param(
        [array]$modes,
        [string]$lastUsedMode,
        [bool]$isOffline = $false,
        [string]$gameRootPath
    )

    Write-ColorMessage "`nAvailable Options:" -Color "DarkCyan"
    
    if ($isOffline) {
        Write-ColorMessage "OFFLINE MODE - Only showing cached options" -Color "Yellow"
    }

    # Display cache clearing option first
    Write-Host "[0] " -NoNewline -ForegroundColor White
    Write-Host "Clear Cache Only" -ForegroundColor Yellow
    $formattedDesc = Format-Description -text "Clears game cache without changing mods. Use this if you're experiencing issues with your current setup."
    Write-ColorMessage $formattedDesc -Color "Cyan"
    Write-Host ""

    # Filter modes if offline
    $availableModes = if ($isOffline) {
        $modes | Where-Object { Test-ModeOfflineAvailable -mode $_ -gameRootPath $gameRootPath }
    } else {
        $modes
    }

    if ($availableModes.Count -eq 0) {
        Write-ColorMessage "No modes available offline. Please connect to the internet to download mod files." -Color "Red"
        return -1
    }

    # Display regular mode options
    for ($i = 0; $i -lt $availableModes.Count; $i++) {
        # Create multiplayer status string with appropriate symbol
        $mpStatus = if ($availableModes[$i].MultiplayerCompatible) {
            "Multiplayer Compatible"
        } else {
            "Single Player Only"
        }
    
        # Check if this was the last used mode
        $isLastUsed = $availableModes[$i].Name -eq $lastUsedMode
    
        # Write the mode number, name, and multiplayer status
        Write-Host "[$($i + 1)] " -NoNewline -ForegroundColor White
        Write-Host "$($availableModes[$i].Name)" -NoNewline -ForegroundColor White

        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host $mpStatus -NoNewline -ForegroundColor $(if ($availableModes[$i].MultiplayerCompatible) {
                "Green" 
            } else {
                "Yellow" 
            })
        if ($isLastUsed) {
            Write-Host " | " -NoNewline -ForegroundColor Gray
            Write-Host "[Currently Installed]" -ForegroundColor Magenta
        } else {
            Write-Host ""  # Just for newline
        }
    
        # Format and display the description with proper wrapping
        $formattedDesc = Format-Description -text $availableModes[$i].Description
        Write-ColorMessage $formattedDesc -Color "Cyan"    
         
        # Add blank line between modes except after the last one
        if ($i -lt $availableModes.Count - 1) {
            Write-Host ""
        }
    }

    # Get user selection
    do {
        $selection = Read-Host "`nSelect option (0-$($availableModes.Count))"
    } while ($selection -notmatch '^\d+$' -or [int]$selection -lt 0 -or [int]$selection -gt $availableModes.Count)

    if ($selection -eq "0") {
        return 0
    } else {
        # Find the original index of the selected mode in the full modes array
        $selectedMode = $availableModes[$selection - 1]
        return ($modes.IndexOf($selectedMode) + 1)
    }
}

# Main script
try {
    $gameExecutablePath = Join-Path $gameRootPath "CivilizationV_DX11.exe"
    $iniFilePath = Join-Path $gameRootPath "$steamINI"
    $dlcFolderPath = Join-Path $gameRootPath "Assets\DLC"
    $myDocumentsGamePath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games\Sid Meier's Civilization 5"

    write-ColorMessage -Message "Civilization V Mod Manager Script" -Color "Blue" -IsHeader

    # Verify paths exist
    if (-not (Test-Path $gameRootPath)) {
        throw "Game root path does not exist: $gameRootPath"
    }
    
    # Get online or cached data with online status
    $jsonResult = Get-CachedJsonData -onlineJsonUrl $onlineJsonUrl -gameRootPath $gameRootPath
    $onlineData = $jsonResult.Data
    
    if ($null -eq $onlineData) {
        Write-ColorMessage "Starting game in default mode" -Color "Yellow"
        Start-Process $gameExecutablePath
        Start-Sleep -Seconds 5
        exit
    }

    # Add schema version check
    Test-SchemaVersion -onlineData $onlineData

    # Add self-update check only if we're online
    if (-not $jsonResult.IsOnline) {
        Write-ColorMessage "Offline mode - skipping update check" -Color "Yellow"
    } elseif ($onlineData.ScriptUpdateUrl) {
        Update-Script -updateUrl $onlineData.ScriptUpdateUrl -currentPath $MyInvocation.MyCommand.Path -currentVersion $SCRIPT_VERSION
    }

    # Update $steamINI with username
    if (Test-Path $iniFilePath) {
        write-ColorMessage -Message "`nUpdating Multiplayer user name" -Color "Blue"
        $currentUserName = (Get-Culture).TextInfo.ToTitleCase($env:USERNAME)
        $iniContent = Get-Content $iniFilePath
        $iniContent = $iniContent -replace "UserName=.*", "UserName=$currentUserName"
        $iniContent | Set-Content $iniFilePath
        Write-ColorMessage "Updated username to: $currentUserName in $steamINI" -Color "Green"
    } else {
        Write-ColorMessage "Warning: $steamINI not found" -Color "Yellow"
    }

    do {
        # Check versions separately for DLC and MyDocuments
        $dlcVersionFile = Join-Path $gameRootPath "version_dlc.json"
        $myDocsVersionFile = Join-Path $myDocumentsGamePath "version_mydocuments.json"
        
        $dlcVersion = if (Test-Path $dlcVersionFile) { 
            Get-Content $dlcVersionFile | ConvertFrom-Json 
        } else {
            $null 
        }
        
        $myDocsVersion = if (Test-Path $myDocsVersionFile) { 
            Get-Content $myDocsVersionFile | ConvertFrom-Json 
        } else {
            $null 
        }

        # Get last used mode
        $lastUsedMode = Get-LastUsedMode -dlcVersionFile $dlcVersionFile -myDocsVersionFile $myDocsVersionFile

        # Show menu and get selection
        $selection = Show-ModeMenu -modes $onlineData.PlayModes -lastUsedMode $lastUsedMode -isOffline (-not $jsonResult.IsOnline) -gameRootPath $gameRootPath

        if ($selection -eq -1) {
            Write-ColorMessage "No modes available. Press any key to exit..."
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            exit
        }

        # Handle cache clearing option
        if ($selection -eq "0") {
            Write-ColorMessage "`nClearing cache directories..." -Color "Blue"
            Clear-CacheDirectories -myDocumentsPath $myDocumentsGamePath
            Write-ColorMessage "Cache clearing complete." -Color "Green"
            continue
        }

        # Regular mode selection
        $selectedMode = $onlineData.PlayModes[$selection - 1]
        Write-ColorMessage "Selected mode: $($selectedMode.Name)" -Color "Green"

        # Add multiplayer compatibility warning if needed
        if (-not $selectedMode.MultiplayerCompatible) {
            Write-ColorMessage "Note: This mode is designed for single-player only" -Color "Yellow"
        } elseif ($selectedMode.Name -match "multiplayer|EUI|Vox Populi") {
            Write-ColorMessage "Note: For multiplayer, all players must use identical mod configuration" -Color "Cyan"
        }


        # Backup saves if enabled
        if ($lastUsedMode -ne $selectedMode.Name) {
            if ($onlineData.Settings.BackupSaves) {
                $savePath = Join-Path $myDocumentsGamePath "Saves"
                Manage-SaveGames `
                    -currentMode $selectedMode.Name `
                    -previousMode $lastUsedMode `
                    -savePath $savePath `
                    -backupBasePath $myDocumentsGamePath
            }

        } 

        $needsDLCUpdate = $dlcVersion -eq $null -or 
        $dlcVersion.Mode -ne $selectedMode.Name -or 
        $dlcVersion.Version -ne $selectedMode.OnlineVersion.DLC

        $needsMyDocsUpdate = $myDocsVersion -eq $null -or 
        $myDocsVersion.Mode -ne $selectedMode.Name -or 
        $myDocsVersion.Version -ne $selectedMode.OnlineVersion.MyDocuments

        if ($needsDLCUpdate -or $needsMyDocsUpdate) {
            Write-ColorMessage "`nGame files need updating" -Color "Blue"
            
            # Clean up old files if enabled, but only for locations that need updating
            if ($onlineData.Settings.CleanupOnModeSwitch) {
                $oldFiles = $modes | Where-Object { $_.Name -ne $selectedMode.Name } |
                    ForEach-Object { $_.Files + $_.Folders }
                if ($needsDLCUpdate) {
                    Clean-GameFiles -FilesToClean $oldFiles -cleanupEnabled $true -location "DLC"
                }
                if ($needsMyDocsUpdate) {
                    Clean-GameFiles -FilesToClean $oldFiles -cleanupEnabled $true -location "MyDocuments"
                }
            }

            # Clear old cache entries at startup
            Clear-OldCache -CurrentModes $onlineData.PlayModes
            
            # Download and extract required files
            Ensure-Directory $dlcFolderPath
            Ensure-Directory $myDocumentsGamePath
            
            if ($needsDLCUpdate -and $selectedMode.DLCDownload) {
                if (Download-AndExtract `
                        -Url $selectedMode.DLCDownload `
                        -TargetPath $dlcFolderPath `
                        -Version $selectedMode.OnlineVersion.DLC `
                        -ModeName $selectedMode.Name `
                        -LocationType "DLC") {
                    Update-LocalVersion -Mode $selectedMode.Name -Version $selectedMode.OnlineVersion.DLC -Location "DLC" -BasePath $gameRootPath
                    Write-ColorMessage "DLC files updated successfully" -Color "Green"
                }
            } else {
                Update-LocalVersion -Mode $selectedMode.Name -Version $selectedMode.OnlineVersion.DLC -Location "DLC" -BasePath $gameRootPath
            }
            
            if ($needsMyDocsUpdate -and $selectedMode.DocsDownload) {
                if (Download-AndExtract `
                        -Url $selectedMode.DocsDownload `
                        -TargetPath $myDocumentsGamePath `
                        -Version $selectedMode.OnlineVersion.MyDocuments `
                        -ModeName $selectedMode.Name `
                        -LocationType "MyDocuments") {
                    Update-LocalVersion -Mode $selectedMode.Name -Version $selectedMode.OnlineVersion.MyDocuments -Location "MyDocuments" -BasePath $myDocumentsGamePath
                    Write-ColorMessage "MyDocuments files updated successfully" -Color "Green"
                }
            } else {
                Update-LocalVersion -Mode $selectedMode.Name -Version $selectedMode.OnlineVersion.MyDocuments -Location "MyDocuments" -BasePath $myDocumentsGamePath
            }
        } else {
            Write-ColorMessage "Game files are up to date" -Color "Green"
        }

        # Check if we need to clear cache directories
        if (Test-NeedsCacheClearing -dlcVersion $dlcVersion -myDocsVersion $myDocsVersion -selectedMode $selectedMode) {
            Clear-CacheDirectories -myDocumentsPath $myDocumentsGamePath
        }

        # Start the game
        Write-ColorMessage "`nStarting Civilization V..." -Color "Green"
        Start-Process $gameExecutablePath
        # Pause for 5 seconds before ending the script
        Start-Sleep -Seconds 5
        break
    } while ($selection -eq "0")
} catch {
    Write-ColorMessage "An error occurred: $_" -Color "Red"
    Write-ColorMessage "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}