[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$gameRootPath,

    [Parameter(Mandatory = $true)]
    [string]$steamINI ,
    
    [Parameter(Mandatory = $true)]
    [string]$onlineJsonUrl
)

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

# Function to download and extract ZIP files
function Download-AndExtract {
    param(
        [string]$Url,
        [string]$TargetPath
    )
    try {
        
        $tempFile = Join-Path $env:TEMP ([System.IO.Path]::GetFileName($Url))
        Write-ColorMessage "`nDownloading: $Url" -Color "Blue"
        Invoke-WebRequest -Uri $Url -OutFile $tempFile
        Write-ColorMessage "Extracting to: $TargetPath" -Color "Cyan"
        Expand-Archive -Path $tempFile -DestinationPath $TargetPath -Force
        Remove-Item $tempFile -Force
        return $true
    } catch {
        Write-ColorMessage "Error during download/extract: $_" -Color "Red"
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
        if (Test-Path $dlcVersionFile) {
            $dlcVersion = Get-Content $dlcVersionFile | ConvertFrom-Json
            return $dlcVersion.Mode
        } elseif (Test-Path $myDocsVersionFile) {
            $myDocsVersion = Get-Content $myDocsVersionFile | ConvertFrom-Json
            return $myDocsVersion.Mode
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

    # Update $steamINI with username
    if (Test-Path $iniFilePath) {
        write-ColorMessage -Message "Updating Multiplayer user name" -Color "Blue"
        $currentUserName = (Get-Culture).TextInfo.ToTitleCase($env:USERNAME)
        $iniContent = Get-Content $iniFilePath
        $iniContent = $iniContent -replace "UserName=.*", "UserName=$currentUserName"
        $iniContent | Set-Content $iniFilePath
        Write-ColorMessage "Updated username to: $currentUserName in $steamINI" -Color "Green"
    } else {
        Write-ColorMessage "Warning: $steamINI not found" -Color "Yellow"
    }

    # Check online connectivity
    try {
        write-ColorMessage -Message "`nGetting online resources" -Color "Blue"
        $onlineData = Invoke-WebRequest -Uri $onlineJsonUrl -UseBasicParsing | ConvertFrom-Json
        Write-ColorMessage "Successfully retrieved online game mode data" -Color "Green"
    } catch {
        Write-ColorMessage "Cannot access online data, starting game in default mode" -Color "Yellow"
        Start-Process $gameExecutablePath
        Start-Sleep -Seconds 5
        exit
    }

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
     

    # Display mode selection menu
    Write-ColorMessage "`nAvailable Game Modes:" -Color "DarkCyan"
    $modes = $onlineData.PlayModes

    # Get last used mode
    $lastUsedMode = Get-LastUsedMode -dlcVersionFile $dlcVersionFile -myDocsVersionFile $myDocsVersionFile

    for ($i = 0; $i -lt $modes.Count; $i++) {
        # Create multiplayer status string with appropriate symbol
        $mpStatus = if ($modes[$i].MultiplayerCompatible) {
            "Multiplayer Compatible"
        } else {
            "Single Player Only"
        }
    
        # Check if this was the last used mode
        $isLastUsed = $modes[$i].Name -eq $lastUsedMode
    
        # Write the mode number, name, and multiplayer status on the same line with different colors
        Write-Host "[$($i + 1)] " -NoNewline -ForegroundColor White
        Write-Host "$($modes[$i].Name)" -NoNewline -ForegroundColor White

        Write-Host " | " -NoNewline -ForegroundColor Gray
        Write-Host $mpStatus -NoNewline -ForegroundColor $(if ($modes[$i].MultiplayerCompatible) {
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
        $formattedDesc = Format-Description -text $modes[$i].Description
        Write-ColorMessage $formattedDesc -Color "Cyan"    
         
        # Add blank line between modes except after the last one
        if ($i -lt $modes.Count - 1) {
            Write-Host ""
        }
    }

    # Get user selection
    do {
        $selection = Read-Host "`nSelect game mode (1-$($modes.Count))"
    } while ([int]$selection -lt 1 -or [int]$selection -gt $modes.Count)
    
    $selectedMode = $modes[$selection - 1]
    Write-ColorMessage "Selected mode: $($selectedMode.Name)" -Color "Green"
    
    # Add multiplayer compatibility warning if needed
    if (-not $selectedMode.MultiplayerCompatible) {
        Write-ColorMessage "Note: This mode is designed for single-player only" -Color "Yellow"
    } elseif ($selectedMode.Name -match "multiplayer|EUI|Vox Populi") {
        Write-ColorMessage "Note: For multiplayer, all players must use identical mod configuration" -Color "Cyan"
    }

    # Backup saves if enabled
    if ($onlineData.Settings.BackupSaves) {
        $savePath = Join-Path $myDocumentsGamePath "Saves"
        Manage-SaveGames `
            -currentMode $selectedMode.Name `
            -previousMode $lastUsedMode `
            -savePath $savePath `
            -backupBasePath $myDocumentsGamePath
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
            
        # Download and extract required files
        Ensure-Directory $dlcFolderPath
        Ensure-Directory $myDocumentsGamePath
            
        if ($needsDLCUpdate -and $selectedMode.DLCDownload) {
            if (Download-AndExtract -Url $selectedMode.DLCDownload -TargetPath $dlcFolderPath) {
                Update-LocalVersion -Mode $selectedMode.Name -Version $selectedMode.OnlineVersion.DLC -Location "DLC" -BasePath $gameRootPath
                Write-ColorMessage "DLC files updated successfully" -Color "Green"
            }
        } else {
            Update-LocalVersion -Mode $selectedMode.Name -Version $selectedMode.OnlineVersion.DLC -Location "DLC" -BasePath $gameRootPath
        }
        
        if ($needsMyDocsUpdate -and $selectedMode.DocsDownload) {
            if (Download-AndExtract -Url $selectedMode.DocsDownload -TargetPath $myDocumentsGamePath) {
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

} catch {
    Write-ColorMessage "An error occurred: $_" -Color "Red"
    Write-ColorMessage "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}