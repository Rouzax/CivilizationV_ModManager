<#
.SYNOPSIS
    Civilization V Mod Manager - Manages mod configurations for Sid Meier's Civilization V.

.DESCRIPTION
    This script helps manage and streamline mod configurations for Civilization V.
    It handles backing up save files, cleaning up outdated files, downloading 
    necessary resources, and ensuring compatibility for selected game modes.

.PARAMETER gameRootPath
    The root path where Civilization V is installed.

.PARAMETER steamINI
    Optional. The name of the Steam INI file for multiplayer username configuration.
    If not specified, username updating is skipped.

.PARAMETER onlineJsonUrl
    The URL to the online JSON configuration file containing available play modes.

.PARAMETER WhatIf
    Preview what changes would be made without executing them.

.EXAMPLE
    .\CivilizationV_ModManager.ps1 -gameRootPath "C:\Games\Civ5" -steamINI "steam.ini" -onlineJsonUrl "https://example.com/modes.json"

.EXAMPLE
    .\CivilizationV_ModManager.ps1 -gameRootPath "C:\Games\Civ5" -onlineJsonUrl "https://example.com/modes.json"
    
    Runs without updating the multiplayer username.

.EXAMPLE
    .\CivilizationV_ModManager.ps1 -gameRootPath "C:\Games\Civ5" -onlineJsonUrl "https://example.com/modes.json" -WhatIf

.NOTES
    Author: Rouzax
    Version: 2.0.0
    License: MIT
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$gameRootPath,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$steamINI,
    
    [Parameter(Mandatory = $true)]
    [ValidateScript({ $_ -match '^https?://' })]
    [string]$onlineJsonUrl
)

#region Constants
$script:SCRIPT_VERSION = "2.0.0"
$script:REQUIRED_SCHEMA_VERSION = "1.1"

# File and folder names
$script:VERSION_FILE_DLC = "version_dlc.json"
$script:VERSION_FILE_MYDOCUMENTS = "version_mydocuments.json"
$script:MOD_CACHE_FOLDER = "ModCache"
$script:MODE_SAVES_FOLDER = "ModeSaves"
$script:MODE_USERDATA_FOLDER = "ModeUserData"
$script:CACHE_JSON_FILE = "modmanager_cache.json"
$script:GAME_EXECUTABLE = "CivilizationV_DX11.exe"

# Timeouts and retries
$script:UPDATE_TIMEOUT_SECONDS = 5
$script:DOWNLOAD_RETRY_COUNT = 3
$script:DOWNLOAD_RETRY_DELAY_SECONDS = 2

# Invalid filename characters pattern
$script:INVALID_FILENAME_CHARS = '[\\/:*?"<>|]'
#endregion Constants

#region Configuration Class
class ScriptConfiguration {
    [string]$GameRootPath
    [string]$GameExecutablePath
    [string]$IniFilePath
    [string]$DlcFolderPath
    [string]$MyDocumentsGamePath
    [string]$CacheBasePath
    [string]$DlcVersionFile
    [string]$MyDocsVersionFile
    [bool]$IsOnline
    [PSObject]$OnlineData

    ScriptConfiguration([string]$gameRoot, [string]$steamINI) {
        $this.GameRootPath = $gameRoot
        $this.GameExecutablePath = Join-Path $gameRoot $script:GAME_EXECUTABLE
        $this.IniFilePath = if ($steamINI) { Join-Path $gameRoot $steamINI } else { $null }
        $this.DlcFolderPath = Join-Path $gameRoot "Assets\DLC"
        $this.MyDocumentsGamePath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Games\Sid Meier's Civilization 5"
        $this.CacheBasePath = Join-Path $gameRoot $script:MOD_CACHE_FOLDER
        $this.DlcVersionFile = Join-Path $gameRoot $script:VERSION_FILE_DLC
        $this.MyDocsVersionFile = Join-Path $this.MyDocumentsGamePath $script:VERSION_FILE_MYDOCUMENTS
        $this.IsOnline = $false
        $this.OnlineData = $null
    }
}
#endregion Configuration Class

#region Helper Functions - File Operations

<#
.SYNOPSIS
    Converts a string to a safe filename by removing invalid characters.

.PARAMETER Name
    The string to convert.

.OUTPUTS
    String with invalid filename characters replaced with underscores.
#>
function ConvertTo-SafeFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    
    return $Name -replace $script:INVALID_FILENAME_CHARS, '_'
}

<#
.SYNOPSIS
    Ensures a directory exists, creating it if necessary.

.PARAMETER Path
    The directory path to ensure exists.
#>
function Assert-DirectoryExists {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, "Create directory")) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-ColorMessage "Created directory: $Path" -Color "Yellow"
        }
    }
}

<#
.SYNOPSIS
    Copies files from source to destination preserving directory structure.

.PARAMETER SourcePath
    The source directory path.

.PARAMETER DestinationPath
    The destination directory path.

.PARAMETER RemoveSource
    If true, removes source files after copying.

.PARAMETER OperationName
    Description of the operation for logging.
#>
function Copy-FilesWithStructure {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        
        [switch]$RemoveSource,
        
        [string]$OperationName = "files"
    )
    
    if (-not (Test-Path $SourcePath)) {
        return $false
    }
    
    $files = Get-ChildItem -Path $SourcePath -File -Recurse
    if (-not $files) {
        return $false
    }
    
    Assert-DirectoryExists -Path $DestinationPath
    
    foreach ($file in $files) {
        $relativePath = $file.FullName.Substring($SourcePath.Length + 1)
        $targetFile = Join-Path $DestinationPath $relativePath
        $targetDir = Split-Path $targetFile -Parent
        
        if (-not (Test-Path $targetDir)) {
            if ($PSCmdlet.ShouldProcess($targetDir, "Create directory")) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
        }
        
        if ($PSCmdlet.ShouldProcess($targetFile, "Copy file")) {
            Copy-Item -Path $file.FullName -Destination $targetFile -Force
        }
        
        if ($RemoveSource -and $PSCmdlet.ShouldProcess($file.FullName, "Remove source file")) {
            Remove-Item -Path $file.FullName -Force
        }
    }
    
    return $true
}

<#
.SYNOPSIS
    Gets the cache path for a specific mode and location type.

.PARAMETER Config
    The script configuration object.

.PARAMETER ModeName
    The name of the mode.

.PARAMETER Version
    The version string.

.PARAMETER LocationType
    Either "DLC" or "MyDocuments".

.OUTPUTS
    The full cache path.
#>
function Get-CachePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config,
        
        [Parameter(Mandatory = $true)]
        [string]$ModeName,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("DLC", "MyDocuments")]
        [string]$LocationType
    )
    
    $safeName = ConvertTo-SafeFileName -Name $ModeName
    $modeCache = Join-Path $Config.CacheBasePath $safeName
    $versionCache = Join-Path $modeCache $Version
    return Join-Path $versionCache $LocationType
}

#endregion Helper Functions - File Operations

#region Helper Functions - Console Output

<#
.SYNOPSIS
    Writes a colored message to the console.

.PARAMETER Message
    The message to write.

.PARAMETER Color
    The foreground color to use.

.PARAMETER IsHeader
    If true, displays the message as a header with separators.
#>
function Write-ColorMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet("Black", "DarkBlue", "DarkGreen", "DarkCyan", "DarkRed", "DarkMagenta", 
                     "DarkYellow", "Gray", "DarkGray", "Blue", "Green", "Cyan", "Red", 
                     "Magenta", "Yellow", "White")]
        [string]$Color = "White",
        
        [switch]$IsHeader
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

<#
.SYNOPSIS
    Gets the console width with a fallback value.

.OUTPUTS
    The console width or 100 as fallback.
#>
function Get-ConsoleWidth {
    [CmdletBinding()]
    [OutputType([int])]
    param()
    
    $width = $host.UI.RawUI.WindowSize.Width
    if (-not $width) {
        $width = $host.UI.RawUI.BufferSize.Width
    }
    if (-not $width -or $width -lt 40) {
        $width = 100
    }
    return $width
}

<#
.SYNOPSIS
    Formats text with proper word wrapping and indentation.

.PARAMETER Text
    The text to format.

.PARAMETER Indent
    Number of spaces for indentation.

.PARAMETER MaxWidth
    Maximum line width (defaults to console width).

.OUTPUTS
    Formatted text string.
#>
function Format-Description {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        
        [int]$Indent = 4,
        
        [int]$MaxWidth = (Get-ConsoleWidth)
    )
    
    $MaxWidth = [Math]::Max(40, $MaxWidth)
    $availableWidth = $MaxWidth - $Indent
    $indentStr = " " * $Indent
    $words = $Text -split '\s+'
    $lines = @()
    $currentLine = $indentStr
    
    foreach ($word in $words) {
        if ($word.Length -gt $availableWidth) {
            if ($currentLine -ne $indentStr) {
                $lines += $currentLine.TrimEnd()
                $currentLine = $indentStr
            }
            $remainingWord = $word
            while ($remainingWord.Length -gt $availableWidth) {
                $lines += $indentStr + $remainingWord.Substring(0, $availableWidth)
                $remainingWord = $remainingWord.Substring($availableWidth)
            }
            $currentLine = $indentStr + $remainingWord
        } elseif (($currentLine.Length + $word.Length + 1) -gt $MaxWidth) {
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

<#
.SYNOPSIS
    Shows a progress indicator for long-running operations.

.PARAMETER Activity
    The activity description.

.PARAMETER Status
    The current status.

.PARAMETER PercentComplete
    The percentage complete (0-100).

.PARAMETER Completed
    If true, completes and removes the progress bar.
#>
function Show-OperationProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Activity,
        
        [string]$Status = "Processing...",
        
        [int]$PercentComplete = -1,
        
        [switch]$Completed
    )
    
    if ($Completed) {
        Write-Progress -Activity $Activity -Completed
    } else {
        Write-Progress -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    }
}

#endregion Helper Functions - Console Output

#region Version Management

<#
.SYNOPSIS
    Gets version information from a version file.

.PARAMETER Location
    Either "DLC" or "MyDocuments".

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    PSObject with version info or $null if not found.
#>
function Get-VersionInfo {
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("DLC", "MyDocuments")]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $versionFile = if ($Location -eq "DLC") { 
        $Config.DlcVersionFile 
    } else { 
        $Config.MyDocsVersionFile 
    }
    
    if (Test-Path $versionFile) {
        try {
            return Get-Content $versionFile -Raw | ConvertFrom-Json
        } catch {
            Write-ColorMessage "Error reading version file for $Location`: $_" -Color "Yellow"
            return $null
        }
    }
    return $null
}

<#
.SYNOPSIS
    Updates the local version file.

.PARAMETER Mode
    The mode name.

.PARAMETER Version
    The version string.

.PARAMETER Location
    Either "DLC" or "MyDocuments".

.PARAMETER Config
    The script configuration object.
#>
function Update-LocalVersion {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        
        [Parameter(Mandatory = $true)]
        [PSObject]$Version,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("DLC", "MyDocuments")]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $versionFile = if ($Location -eq "DLC") { 
        $Config.DlcVersionFile 
    } else { 
        $Config.MyDocsVersionFile 
    }
    
    $versionInfo = @{
        Mode     = $Mode
        Version  = $Version
        LastRun  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Location = $Location
    }
    
    if ($PSCmdlet.ShouldProcess($versionFile, "Update version info")) {
        $versionInfo | ConvertTo-Json | Set-Content -Path $versionFile
    }
}

<#
.SYNOPSIS
    Tests if a location needs updating.

.PARAMETER Location
    Either "DLC" or "MyDocuments".

.PARAMETER SelectedMode
    The selected play mode object.

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    Boolean indicating if update is needed.
#>
function Test-NeedsUpdate {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("DLC", "MyDocuments")]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [PSObject]$SelectedMode,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $versionInfo = Get-VersionInfo -Location $Location -Config $Config
    $targetVersion = if ($Location -eq "DLC") {
        $SelectedMode.OnlineVersion.DLC
    } else {
        $SelectedMode.OnlineVersion.MyDocuments
    }
    
    return ($null -eq $versionInfo) -or 
           ($versionInfo.Mode -ne $SelectedMode.Name) -or 
           ($versionInfo.Version -ne $targetVersion)
}

<#
.SYNOPSIS
    Gets the last used mode name.

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    The mode name or $null.
#>
function Get-LastUsedMode {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $myDocsVersion = Get-VersionInfo -Location "MyDocuments" -Config $Config
    if ($myDocsVersion) {
        return $myDocsVersion.Mode
    }
    
    $dlcVersion = Get-VersionInfo -Location "DLC" -Config $Config
    if ($dlcVersion) {
        return $dlcVersion.Mode
    }
    
    return $null
}

#endregion Version Management

#region JSON and Schema Validation

<#
.SYNOPSIS
    Validates the online JSON schema version and required properties.

.PARAMETER OnlineData
    The parsed JSON data object.
#>
function Test-SchemaVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$OnlineData
    )
    
    if ($OnlineData.schemaVersion -ne $script:REQUIRED_SCHEMA_VERSION) {
        throw "Incompatible online JSON schema version. Required: $script:REQUIRED_SCHEMA_VERSION, Found: $($OnlineData.schemaVersion)"
    }
    
    # Validate required properties
    $requiredProperties = @('PlayModes', 'Settings')
    foreach ($prop in $requiredProperties) {
        if (-not $OnlineData.PSObject.Properties.Name.Contains($prop)) {
            throw "Missing required property in JSON schema: $prop"
        }
    }
    
    if ($OnlineData.PlayModes.Count -eq 0) {
        throw "PlayModes array is empty in JSON schema"
    }
}

<#
.SYNOPSIS
    Gets cached or online JSON data.

.PARAMETER OnlineJsonUrl
    The URL to fetch JSON from.

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    Hashtable with Data and IsOnline properties.
#>
function Get-CachedJsonData {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OnlineJsonUrl,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $cachedJsonPath = Join-Path $Config.GameRootPath $script:CACHE_JSON_FILE
    $result = @{
        Data     = $null
        IsOnline = $false
    }
    
    try {
        Write-ColorMessage -Message "Getting online resources" -Color "Blue"
        $onlineData = Invoke-WebRequest -Uri $OnlineJsonUrl -UseBasicParsing -ErrorAction Stop | 
                      ConvertFrom-Json
        
        $onlineData | ConvertTo-Json -Depth 10 | Set-Content -Path $cachedJsonPath -Force
        Write-ColorMessage "Successfully retrieved and cached online game mode data" -Color "Green"
        
        $result.Data = $onlineData
        $result.IsOnline = $true
        return $result
    } catch {
        if (Test-Path $cachedJsonPath) {
            Write-ColorMessage "Cannot access online data, using cached configuration" -Color "Yellow"
            try {
                $cachedData = Get-Content $cachedJsonPath -Raw | ConvertFrom-Json
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

#endregion JSON and Schema Validation

#region Self-Update Functions

<#
.SYNOPSIS
    Checks for and applies script updates.

.PARAMETER UpdateUrl
    The URL to download the update from.

.PARAMETER CurrentPath
    The path to the current script.

.PARAMETER CurrentVersion
    The current script version.

.PARAMETER Config
    The script configuration object.
#>
function Update-Script {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$UpdateUrl,
        
        [Parameter(Mandatory = $true)]
        [string]$CurrentPath,
        
        [Parameter(Mandatory = $true)]
        [string]$CurrentVersion,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $timeoutTask = $null
    
    try {
        $newContent = (Invoke-WebRequest -Uri $UpdateUrl -UseBasicParsing -ErrorAction Stop).Content.Trim()
        
        if ($newContent -match '\$(?:script:)?SCRIPT_VERSION\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"') {
            $newVersion = $matches[1]
            
            $current = [version]$CurrentVersion
            $new = [version]$newVersion
            
            if ($new -gt $current) {
                Write-ColorMessage "New script version available ($newVersion). Current version: $CurrentVersion" -Color "Yellow"
                Write-ColorMessage "Update? (Y/N) - Auto-skip in $script:UPDATE_TIMEOUT_SECONDS seconds" -Color "Yellow"
                
                $timeoutTask = Start-Job { 
                    param($seconds)
                    Start-Sleep -Seconds $seconds 
                } -ArgumentList $script:UPDATE_TIMEOUT_SECONDS
                
                while ($timeoutTask.State -eq 'Running') {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'Y') {
                            if ($PSCmdlet.ShouldProcess($CurrentPath, "Update script to version $newVersion")) {
                                $newContent | Set-Content -Path $CurrentPath -NoNewline
                                Write-ColorMessage "Script updated successfully to version $newVersion" -Color "Green"
                                
                                # Restart with same parameters
                                $restartArgs = "-File `"$CurrentPath`" -gameRootPath `"$($Config.GameRootPath)`" -onlineJsonUrl `"$onlineJsonUrl`""
                                if ($Config.IniFilePath) {
                                    $iniFileName = Split-Path $Config.IniFilePath -Leaf
                                    $restartArgs += " -steamINI `"$iniFileName`""
                                }
                                Start-Process powershell -ArgumentList $restartArgs
                                exit
                            }
                        } elseif ($key.Key -eq 'N') {
                            Write-ColorMessage "Update skipped" -Color "Yellow"
                            break
                        }
                    }
                    Start-Sleep -Milliseconds 100
                }
            }
        } else {
            Write-ColorMessage "Could not determine version of update script" -Color "Yellow"
        }
    } catch {
        Write-ColorMessage "Error checking for updates: $_" -Color "Yellow"
    } finally {
        if ($timeoutTask) {
            Stop-Job $timeoutTask -ErrorAction SilentlyContinue
            Remove-Job $timeoutTask -ErrorAction SilentlyContinue
        }
    }
}

#endregion Self-Update Functions

#region Download and Cache Management

<#
.SYNOPSIS
    Downloads a file with retry logic.

.PARAMETER Url
    The URL to download from.

.PARAMETER DestinationPath
    The local path to save the file.

.PARAMETER RetryCount
    Number of retries on failure.

.OUTPUTS
    Boolean indicating success.
#>
function Invoke-DownloadWithRetry {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        
        [int]$RetryCount = $script:DOWNLOAD_RETRY_COUNT
    )
    
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            if ($PSCmdlet.ShouldProcess($Url, "Download file (attempt $attempt of $RetryCount)")) {
                Show-OperationProgress -Activity "Downloading" -Status "Attempt $attempt of $RetryCount" -PercentComplete (($attempt - 1) * 100 / $RetryCount)
                Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -ErrorAction Stop
                Show-OperationProgress -Activity "Downloading" -Completed
                return $true
            }
            return $true  # WhatIf mode
        } catch {
            Write-ColorMessage "Download attempt $attempt failed: $_" -Color "Yellow"
            if ($attempt -lt $RetryCount) {
                $delay = $script:DOWNLOAD_RETRY_DELAY_SECONDS * $attempt
                Write-ColorMessage "Retrying in $delay seconds..." -Color "Yellow"
                Start-Sleep -Seconds $delay
            }
        }
    }
    
    Show-OperationProgress -Activity "Downloading" -Completed
    return $false
}

<#
.SYNOPSIS
    Gets a file from cache or downloads it.

.PARAMETER Url
    The URL to download from.

.PARAMETER Version
    The version string.

.PARAMETER ModeName
    The mode name.

.PARAMETER LocationType
    Either "DLC" or "MyDocuments".

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    The path to the cached file or $null on failure.
#>
function Get-CachedDownload {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [Parameter(Mandatory = $true)]
        [string]$ModeName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("DLC", "MyDocuments")]
        [string]$LocationType,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $locationCache = Get-CachePath -Config $Config -ModeName $ModeName -Version $Version -LocationType $LocationType
    Assert-DirectoryExists -Path $locationCache
    
    $fileName = [System.IO.Path]::GetFileName($Url)
    $cachePath = Join-Path $locationCache $fileName
    
    if (Test-Path $cachePath) {
        Write-ColorMessage "Using cached version of $fileName" -Color "Cyan"
        return $cachePath
    }
    
    Write-ColorMessage "Downloading $fileName to cache" -Color "Blue"
    
    if (Invoke-DownloadWithRetry -Url $Url -DestinationPath $cachePath) {
        Write-ColorMessage "Successfully cached $fileName" -Color "Green"
        return $cachePath
    } else {
        Write-ColorMessage "Failed to download $fileName after $script:DOWNLOAD_RETRY_COUNT attempts" -Color "Red"
        if (Test-Path $cachePath) {
            Remove-Item $cachePath -Force -ErrorAction SilentlyContinue
        }
        return $null
    }
}

<#
.SYNOPSIS
    Downloads and extracts mod files.

.PARAMETER Url
    The download URL.

.PARAMETER TargetPath
    The extraction target path.

.PARAMETER Version
    The version string.

.PARAMETER ModeName
    The mode name.

.PARAMETER LocationType
    Either "DLC" or "MyDocuments".

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    Boolean indicating success.
#>
function Invoke-DownloadAndExtract {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        
        [Parameter(Mandatory = $true)]
        [string]$Version,
        
        [Parameter(Mandatory = $true)]
        [string]$ModeName,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("DLC", "MyDocuments")]
        [string]$LocationType,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    if ([string]::IsNullOrEmpty($Url)) {
        return $true
    }
    
    try {
        $sourcePath = Get-CachedDownload -Url $Url -Version $Version -ModeName $ModeName `
                                         -LocationType $LocationType -Config $Config
        
        if ($null -eq $sourcePath) {
            return $false
        }
        
        # Extract to temp folder first for safety
        $tempExtractPath = Join-Path $env:TEMP "CivModExtract_$(Get-Date -Format 'yyyyMMddHHmmss')"
        
        Write-ColorMessage "Extracting to: $TargetPath" -Color "Cyan"
        Show-OperationProgress -Activity "Extracting files" -Status "Please wait..." -PercentComplete 50
        
        if ($PSCmdlet.ShouldProcess($TargetPath, "Extract archive")) {
            Expand-Archive -Path $sourcePath -DestinationPath $tempExtractPath -Force
            
            # Move contents to target
            Get-ChildItem -Path $tempExtractPath | ForEach-Object {
                $destPath = Join-Path $TargetPath $_.Name
                if (Test-Path $destPath) {
                    Remove-Item $destPath -Recurse -Force
                }
                Move-Item $_.FullName -Destination $TargetPath -Force
            }
            
            # Cleanup temp folder
            Remove-Item $tempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Show-OperationProgress -Activity "Extracting files" -Completed
        Write-ColorMessage "Extraction complete" -Color "Green"
        return $true
    } catch {
        Show-OperationProgress -Activity "Extracting files" -Completed
        Write-ColorMessage "Error during extraction: $_" -Color "Red"
        return $false
    }
}

<#
.SYNOPSIS
    Clears old cache entries for outdated versions.

.PARAMETER CurrentModes
    Array of current play modes.

.PARAMETER Config
    The script configuration object.
#>
function Clear-OldCache {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [array]$CurrentModes,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    if (-not (Test-Path $Config.CacheBasePath)) {
        return
    }
    
    Write-ColorMessage "`nChecking for outdated cache entries..." -Color "Blue"
    
    $cachedModes = Get-ChildItem -Path $Config.CacheBasePath -Directory
    
    foreach ($modeDir in $cachedModes) {
        $currentMode = $CurrentModes | Where-Object { 
            (ConvertTo-SafeFileName -Name $_.Name) -eq $modeDir.Name 
        }
        
        if ($null -eq $currentMode) {
            Write-ColorMessage "Removing cache for obsolete mode: $($modeDir.Name)" -Color "Yellow"
            if ($PSCmdlet.ShouldProcess($modeDir.FullName, "Remove obsolete mode cache")) {
                Remove-Item $modeDir.FullName -Recurse -Force
            }
            continue
        }
        
        $versionDirs = Get-ChildItem -Path $modeDir.FullName -Directory
        foreach ($versionDir in $versionDirs) {
            $isCurrentVersion = ($currentMode.OnlineVersion.DLC -eq $versionDir.Name) -or 
                               ($currentMode.OnlineVersion.MyDocuments -eq $versionDir.Name)
            
            if (-not $isCurrentVersion) {
                Write-ColorMessage "Removing outdated version cache: $($modeDir.Name) v$($versionDir.Name)" -Color "Yellow"
                if ($PSCmdlet.ShouldProcess($versionDir.FullName, "Remove outdated version cache")) {
                    Remove-Item $versionDir.FullName -Recurse -Force
                }
            }
        }
    }
}

#endregion Download and Cache Management

#region Game File Management

<#
.SYNOPSIS
    Removes game files from other modes.

.PARAMETER FilesToClean
    Array of file/folder paths to clean.

.PARAMETER CleanupEnabled
    Whether cleanup is enabled in settings.

.PARAMETER Location
    Either "DLC" or "MyDocuments".

.PARAMETER Config
    The script configuration object.
#>
function Remove-GameFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [array]$FilesToClean,
        
        [bool]$CleanupEnabled,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("DLC", "MyDocuments")]
        [string]$Location,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    if (-not $CleanupEnabled) {
        Write-ColorMessage "Cleanup disabled in settings, skipping..." -Color "Yellow"
        return
    }

    Write-ColorMessage "`nCleaning up $Location files..." -Color "Blue"
    
    $basePath = if ($Location -eq "DLC") { $Config.DlcFolderPath } else { $Config.MyDocumentsGamePath }
    $prefix = if ($Location -eq "DLC") { "DLC/" } else { "MyDocuments/" }

    foreach ($file in $FilesToClean) {
        if ($file.StartsWith($prefix)) {
            $relativePath = $file.Substring($prefix.Length)
            $fullPath = Join-Path $basePath $relativePath
            
            if (Test-Path $fullPath) {
                try {
                    if ($PSCmdlet.ShouldProcess($fullPath, "Remove")) {
                        Remove-Item -Path $fullPath -Recurse -Force
                        Write-ColorMessage "Cleaned up: $fullPath" -Color "Yellow"
                    }
                } catch {
                    Write-ColorMessage "Error cleaning up $fullPath`: $_" -Color "Red"
                }
            }
        }
    }
    Write-ColorMessage "Cleaning up $Location files successful" -Color "Green"
}

<#
.SYNOPSIS
    Clears the game cache directory.

.PARAMETER Config
    The script configuration object.
#>
function Clear-GameCacheDirectory {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $cacheDir = Join-Path $Config.MyDocumentsGamePath "cache"

    if (Test-Path $cacheDir) {
        try {
            if ($PSCmdlet.ShouldProcess($cacheDir, "Clear cache directory")) {
                Remove-Item -Path "$cacheDir\*" -Recurse -Force
                Write-ColorMessage "Cleared cache directory: $cacheDir" -Color "Yellow"
            }
        } catch {
            Write-ColorMessage "Error clearing cache directory $cacheDir`: $_" -Color "Red"
        }
    }
    Write-ColorMessage "Cache directory cleared" -Color "Green"
}

<#
.SYNOPSIS
    Tests if cache clearing is needed.

.PARAMETER SelectedMode
    The selected play mode.

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    Boolean indicating if cache clearing is needed.
#>
function Test-NeedsCacheClearing {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$SelectedMode,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $dlcVersion = Get-VersionInfo -Location "DLC" -Config $Config
    $myDocsVersion = Get-VersionInfo -Location "MyDocuments" -Config $Config
    
    if ($null -eq $dlcVersion -or $null -eq $myDocsVersion) {
        Write-ColorMessage "`nCache clearing needed: Missing version information" -Color "Blue"
        return $true
    }

    if ($dlcVersion.Mode -ne $SelectedMode.Name -or $myDocsVersion.Mode -ne $SelectedMode.Name) {
        Write-ColorMessage "`nCache clearing needed: Mode change detected" -Color "Blue"
        return $true
    }

    if ($dlcVersion.Version -ne $SelectedMode.OnlineVersion.DLC -or 
        $myDocsVersion.Version -ne $SelectedMode.OnlineVersion.MyDocuments) {
        Write-ColorMessage "`nCache clearing needed: New version available" -Color "Blue"
        return $true
    }

    Write-ColorMessage "`nNo cache clearing needed" -Color "Green"
    return $false
}

#endregion Game File Management

#region User Data Management

<#
.SYNOPSIS
    Backs up user files for a mode.

.PARAMETER ModeName
    The mode name.

.PARAMETER SourcePath
    The source directory path.

.PARAMETER BackupRootPath
    The backup root directory.

.PARAMETER DataType
    Description of the data type for logging.
#>
function Backup-UserFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModeName,
        
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory = $true)]
        [string]$BackupRootPath,
        
        [string]$DataType = "files"
    )
    
    if (-not (Test-Path $SourcePath)) {
        return
    }
    
    $files = Get-ChildItem -Path $SourcePath -File -Recurse
    if (-not $files) {
        return
    }
    
    $safeName = ConvertTo-SafeFileName -Name $ModeName
    $backupPath = Join-Path $BackupRootPath $safeName
    
    Write-ColorMessage "Backing up $ModeName $DataType..." -Color "Cyan"
    
    try {
        if (Copy-FilesWithStructure -SourcePath $SourcePath -DestinationPath $backupPath -RemoveSource) {
            Write-ColorMessage "Successfully backed up $DataType for $ModeName" -Color "Green"
        }
    } catch {
        Write-ColorMessage "Error backing up $DataType`: $_" -Color "Red"
    }
}

<#
.SYNOPSIS
    Restores user files for a mode.

.PARAMETER ModeName
    The mode name.

.PARAMETER TargetPath
    The target directory path.

.PARAMETER BackupRootPath
    The backup root directory.

.PARAMETER DataType
    Description of the data type for logging.
#>
function Restore-UserFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModeName,
        
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,
        
        [Parameter(Mandatory = $true)]
        [string]$BackupRootPath,
        
        [string]$DataType = "files"
    )
    
    $safeName = ConvertTo-SafeFileName -Name $ModeName
    $backupPath = Join-Path $BackupRootPath $safeName
    
    if (-not (Test-Path $backupPath)) {
        return
    }
    
    Write-ColorMessage "Restoring $ModeName $DataType..." -Color "Cyan"
    
    try {
        if (Copy-FilesWithStructure -SourcePath $backupPath -DestinationPath $TargetPath) {
            Write-ColorMessage "Successfully restored $DataType for $ModeName" -Color "Green"
        }
    } catch {
        Write-ColorMessage "Error restoring $DataType`: $_" -Color "Red"
    }
}

<#
.SYNOPSIS
    Manages user data when switching modes.

.PARAMETER CurrentMode
    The mode being switched to.

.PARAMETER PreviousMode
    The mode being switched from.

.PARAMETER Config
    The script configuration object.
#>
function Switch-UserData {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CurrentMode,
        
        [string]$PreviousMode,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    $savePath = Join-Path $Config.MyDocumentsGamePath "Saves"
    $modUserDataPath = Join-Path $Config.MyDocumentsGamePath "ModUserData"
    $backupRootPath = Join-Path $Config.MyDocumentsGamePath $script:MODE_SAVES_FOLDER
    $modUserDataBackupRoot = Join-Path $Config.MyDocumentsGamePath $script:MODE_USERDATA_FOLDER
    
    # Ensure directories exist
    Assert-DirectoryExists -Path $backupRootPath
    Assert-DirectoryExists -Path $modUserDataBackupRoot
    Assert-DirectoryExists -Path $savePath
    Assert-DirectoryExists -Path $modUserDataPath

    Write-ColorMessage "`nManaging user data..." -Color "Blue"

    # Backup previous mode data
    if ($PreviousMode) {
        Backup-UserFiles -ModeName $PreviousMode -SourcePath $savePath `
                        -BackupRootPath $backupRootPath -DataType "save games"
        
        Backup-UserFiles -ModeName $PreviousMode -SourcePath $modUserDataPath `
                        -BackupRootPath $modUserDataBackupRoot -DataType "mod user data"
    }

    # Restore current mode data
    Restore-UserFiles -ModeName $CurrentMode -TargetPath $savePath `
                     -BackupRootPath $backupRootPath -DataType "save games"
    
    Restore-UserFiles -ModeName $CurrentMode -TargetPath $modUserDataPath `
                     -BackupRootPath $modUserDataBackupRoot -DataType "mod user data"
}

#endregion User Data Management

#region Mode Availability

<#
.SYNOPSIS
    Tests if a mode is available offline (cached).

.PARAMETER Mode
    The play mode object.

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    Boolean indicating if mode is available offline.
#>
function Test-ModeOfflineAvailable {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Mode,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    # Check DLC cache if DLCDownload is specified
    if ($Mode.DLCDownload) {
        $dlcCachePath = Get-CachePath -Config $Config -ModeName $Mode.Name `
                                      -Version $Mode.OnlineVersion.DLC -LocationType "DLC"
        $dlcFileName = [System.IO.Path]::GetFileName($Mode.DLCDownload)
        $dlcFilePath = Join-Path $dlcCachePath $dlcFileName
        
        if (-not (Test-Path $dlcFilePath)) {
            return $false
        }
    }
    
    # Check MyDocuments cache if DocsDownload is specified
    if ($Mode.DocsDownload) {
        $docsCachePath = Get-CachePath -Config $Config -ModeName $Mode.Name `
                                       -Version $Mode.OnlineVersion.MyDocuments -LocationType "MyDocuments"
        $docsFileName = [System.IO.Path]::GetFileName($Mode.DocsDownload)
        $docsFilePath = Join-Path $docsCachePath $docsFileName
        
        if (-not (Test-Path $docsFilePath)) {
            return $false
        }
    }
    
    return $true
}

<#
.SYNOPSIS
    Gets available modes based on online status.

.PARAMETER Modes
    Array of all play modes.

.PARAMETER IsOffline
    Whether the script is running offline.

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    Array of available modes.
#>
function Get-AvailableModes {
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Modes,
        
        [bool]$IsOffline = $false,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    if ($IsOffline) {
        return $Modes | Where-Object { Test-ModeOfflineAvailable -Mode $_ -Config $Config }
    }
    
    return $Modes
}

#endregion Mode Availability

#region Menu Display

<#
.SYNOPSIS
    Displays the mode selection menu.

.PARAMETER Modes
    Array of all play modes.

.PARAMETER LastUsedMode
    The name of the last used mode.

.PARAMETER IsOffline
    Whether the script is running offline.

.PARAMETER Config
    The script configuration object.

.OUTPUTS
    The selected index (0 for cache clear, -1 for no modes, or 1+ for mode selection).
#>
function Show-ModeMenu {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [array]$Modes,
        
        [string]$LastUsedMode,
        
        [bool]$IsOffline = $false,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )

    Write-ColorMessage "`nAvailable Options:" -Color "DarkCyan"
    
    if ($IsOffline) {
        Write-ColorMessage "OFFLINE MODE - Only showing cached options" -Color "Yellow"
    }

    # Display cache clearing option first
    Write-Host "[0] " -NoNewline -ForegroundColor White
    Write-Host "Clear Cache Only" -ForegroundColor Yellow
    $formattedDesc = Format-Description -Text "Clears game cache without changing mods. Use this if you're experiencing issues with your current setup."
    Write-ColorMessage $formattedDesc -Color "Cyan"
    Write-Host ""

    # Get available modes
    $availableModes = Get-AvailableModes -Modes $Modes -IsOffline $IsOffline -Config $Config

    if ($availableModes.Count -eq 0) {
        Write-ColorMessage "No modes available offline. Please connect to the internet to download mod files." -Color "Red"
        return -1
    }

    # Display regular mode options
    for ($i = 0; $i -lt $availableModes.Count; $i++) {
        $mode = $availableModes[$i]
        $mpStatus = if ($mode.MultiplayerCompatible) { "Multiplayer Compatible" } else { "Single Player Only" }
        $isLastUsed = $mode.Name -eq $LastUsedMode
    
        Write-Host "[$($i + 1)] " -NoNewline -ForegroundColor White
        Write-Host "$($mode.Name)" -NoNewline -ForegroundColor White
        Write-Host " | " -NoNewline -ForegroundColor Gray
        
        $mpColor = if ($mode.MultiplayerCompatible) { "Green" } else { "Yellow" }
        Write-Host $mpStatus -NoNewline -ForegroundColor $mpColor
        
        if ($isLastUsed) {
            Write-Host " | " -NoNewline -ForegroundColor Gray
            Write-Host "[Currently Installed]" -ForegroundColor Magenta
        } else {
            Write-Host ""
        }
    
        $formattedDesc = Format-Description -Text $mode.Description
        Write-ColorMessage $formattedDesc -Color "Cyan"    
         
        if ($i -lt $availableModes.Count - 1) {
            Write-Host ""
        }
    }

    # Display exit option at the end
    Write-Host ""
    Write-Host "[Q] " -NoNewline -ForegroundColor White
    Write-Host "Quit" -ForegroundColor Gray

    # Get user selection
    do {
        $selection = Read-Host "`nSelect option (0-$($availableModes.Count) or Q to quit)"
        
        if ($selection -eq 'Q' -or $selection -eq 'q') {
            return -2  # Exit code
        }
    } while ($selection -notmatch '^\d+$' -or [int]$selection -lt 0 -or [int]$selection -gt $availableModes.Count)

    if ($selection -eq "0") {
        return 0
    } else {
        # Find the original index of the selected mode in the full modes array
        $selectedMode = $availableModes[$selection - 1]
        return ($Modes.IndexOf($selectedMode) + 1)
    }
}

#endregion Menu Display

#region Steam INI Management

<#
.SYNOPSIS
    Updates the Steam INI file with the current username.

.PARAMETER Config
    The script configuration object.
#>
function Update-SteamUsername {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config
    )
    
    # Skip if no INI file configured
    if (-not $Config.IniFilePath) {
        return
    }
    
    # Skip if INI file doesn't exist
    if (-not (Test-Path $Config.IniFilePath)) {
        return
    }
    
    Write-ColorMessage -Message "`nUpdating Multiplayer user name" -Color "Blue"
    $currentUserName = (Get-Culture).TextInfo.ToTitleCase($env:USERNAME)
    
    if ($PSCmdlet.ShouldProcess($Config.IniFilePath, "Update username to $currentUserName")) {
        $iniContent = Get-Content $Config.IniFilePath
        $iniContent = $iniContent -replace "UserName=.*", "UserName=$currentUserName"
        $iniContent | Set-Content $Config.IniFilePath
        Write-ColorMessage "Updated username to: $currentUserName in $(Split-Path $Config.IniFilePath -Leaf)" -Color "Green"
    }
}

#endregion Steam INI Management

#region Main Script Logic

<#
.SYNOPSIS
    Processes the selected mode and updates game files.

.PARAMETER SelectedMode
    The selected play mode object.

.PARAMETER Config
    The script configuration object.

.PARAMETER OnlineData
    The online configuration data.

.PARAMETER LastUsedMode
    The name of the last used mode.
#>
function Invoke-ModeUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$SelectedMode,
        
        [Parameter(Mandatory = $true)]
        [ScriptConfiguration]$Config,
        
        [Parameter(Mandatory = $true)]
        [PSObject]$OnlineData,
        
        [string]$LastUsedMode
    )
    
    Write-ColorMessage "Selected mode: $($SelectedMode.Name)" -Color "Green"

    # Display multiplayer compatibility info
    if (-not $SelectedMode.MultiplayerCompatible) {
        Write-ColorMessage "Note: This mode is designed for single-player only" -Color "Yellow"
    } elseif ($SelectedMode.Name -match "multiplayer|EUI|Vox Populi") {
        Write-ColorMessage "Note: For multiplayer, all players must use identical mod configuration" -Color "Cyan"
    }

    # Backup saves and mod user data if mode changed
    if ($LastUsedMode -ne $SelectedMode.Name) {
        if ($OnlineData.Settings.BackupUserData) {
            Switch-UserData -CurrentMode $SelectedMode.Name -PreviousMode $LastUsedMode -Config $Config
        }
    }

    $needsDLCUpdate = Test-NeedsUpdate -Location "DLC" -SelectedMode $SelectedMode -Config $Config
    $needsMyDocsUpdate = Test-NeedsUpdate -Location "MyDocuments" -SelectedMode $SelectedMode -Config $Config

    if ($needsDLCUpdate -or $needsMyDocsUpdate) {
        Write-ColorMessage "`nGame files need updating" -Color "Blue"
        
        # Clean up old files if enabled
        if ($OnlineData.Settings.CleanupOnModeSwitch) {
            $oldFiles = $OnlineData.PlayModes | 
                Where-Object { $_.Name -ne $SelectedMode.Name } |
                ForEach-Object { $_.Files + $_.Folders }
            
            if ($needsDLCUpdate) {
                Remove-GameFiles -FilesToClean $oldFiles -CleanupEnabled $true -Location "DLC" -Config $Config
            }
            if ($needsMyDocsUpdate) {
                Remove-GameFiles -FilesToClean $oldFiles -CleanupEnabled $true -Location "MyDocuments" -Config $Config
            }
        }

        # Clear old cache entries
        Clear-OldCache -CurrentModes $OnlineData.PlayModes -Config $Config
        
        # Ensure target directories exist
        Assert-DirectoryExists -Path $Config.DlcFolderPath
        Assert-DirectoryExists -Path $Config.MyDocumentsGamePath
        
        # Update DLC files
        if ($needsDLCUpdate) {
            if ($SelectedMode.DLCDownload) {
                if (Invoke-DownloadAndExtract -Url $SelectedMode.DLCDownload `
                                              -TargetPath $Config.DlcFolderPath `
                                              -Version $SelectedMode.OnlineVersion.DLC `
                                              -ModeName $SelectedMode.Name `
                                              -LocationType "DLC" `
                                              -Config $Config) {
                    Update-LocalVersion -Mode $SelectedMode.Name -Version $SelectedMode.OnlineVersion.DLC `
                                       -Location "DLC" -Config $Config
                    Write-ColorMessage "DLC files updated successfully" -Color "Green"
                }
            } else {
                Update-LocalVersion -Mode $SelectedMode.Name -Version $SelectedMode.OnlineVersion.DLC `
                                   -Location "DLC" -Config $Config
            }
        }
        
        # Update MyDocuments files
        if ($needsMyDocsUpdate) {
            if ($SelectedMode.DocsDownload) {
                if (Invoke-DownloadAndExtract -Url $SelectedMode.DocsDownload `
                                              -TargetPath $Config.MyDocumentsGamePath `
                                              -Version $SelectedMode.OnlineVersion.MyDocuments `
                                              -ModeName $SelectedMode.Name `
                                              -LocationType "MyDocuments" `
                                              -Config $Config) {
                    Update-LocalVersion -Mode $SelectedMode.Name -Version $SelectedMode.OnlineVersion.MyDocuments `
                                       -Location "MyDocuments" -Config $Config
                    Write-ColorMessage "MyDocuments files updated successfully" -Color "Green"
                }
            } else {
                Update-LocalVersion -Mode $SelectedMode.Name -Version $SelectedMode.OnlineVersion.MyDocuments `
                                   -Location "MyDocuments" -Config $Config
            }
        }
    } else {
        Write-ColorMessage "Game files are up to date" -Color "Green"
    }

    # Check if we need to clear cache directories
    if (Test-NeedsCacheClearing -SelectedMode $SelectedMode -Config $Config) {
        Clear-GameCacheDirectory -Config $Config
    }
}

<#
.SYNOPSIS
    Main entry point for the script.
#>
function Start-ModManager {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    
    try {
        # Initialize configuration
        $config = [ScriptConfiguration]::new($gameRootPath, $steamINI)
        
        Write-ColorMessage -Message "Civilization V Mod Manager Script v$script:SCRIPT_VERSION" -Color "Blue" -IsHeader
        
        if ($WhatIfPreference) {
            Write-ColorMessage "Running in WhatIf mode - no changes will be made" -Color "Yellow"
        }
        
        # Get online or cached data
        $jsonResult = Get-CachedJsonData -OnlineJsonUrl $onlineJsonUrl -Config $config
        $config.OnlineData = $jsonResult.Data
        $config.IsOnline = $jsonResult.IsOnline
        
        if ($null -eq $config.OnlineData) {
            Write-ColorMessage "Starting game in default mode" -Color "Yellow"
            if ($PSCmdlet.ShouldProcess($config.GameExecutablePath, "Start game")) {
                Start-Process $config.GameExecutablePath
                Start-Sleep -Seconds 5
            }
            return
        }

        # Validate schema
        Test-SchemaVersion -OnlineData $config.OnlineData

        # Check for script updates (only if online)
        if (-not $config.IsOnline) {
            Write-ColorMessage "Offline mode - skipping update check" -Color "Yellow"
        } elseif ($config.OnlineData.ScriptUpdateUrl) {
            Update-Script -UpdateUrl $config.OnlineData.ScriptUpdateUrl `
                         -CurrentPath $MyInvocation.PSCommandPath `
                         -CurrentVersion $script:SCRIPT_VERSION `
                         -Config $config
        }

        # Update Steam username
        Update-SteamUsername -Config $config

        # Main menu loop
        do {
            $lastUsedMode = Get-LastUsedMode -Config $config

            # Show menu and get selection
            $selection = Show-ModeMenu -Modes $config.OnlineData.PlayModes `
                                       -LastUsedMode $lastUsedMode `
                                       -IsOffline (-not $config.IsOnline) `
                                       -Config $config

            switch ($selection) {
                -2 {
                    # Exit requested
                    Write-ColorMessage "`nExiting..." -Color "Cyan"
                    return
                }
                -1 {
                    # No modes available
                    Write-ColorMessage "No modes available. Press any key to exit..."
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                    return
                }
                0 {
                    # Clear cache
                    Write-ColorMessage "`nClearing cache directories..." -Color "Blue"
                    Clear-GameCacheDirectory -Config $config
                    Write-ColorMessage "Cache clearing complete." -Color "Green"
                    continue
                }
                default {
                    # Mode selection
                    $selectedMode = $config.OnlineData.PlayModes[$selection - 1]
                    
                    Invoke-ModeUpdate -SelectedMode $selectedMode `
                                     -Config $config `
                                     -OnlineData $config.OnlineData `
                                     -LastUsedMode $lastUsedMode

                    # Start the game
                    Write-ColorMessage "`nStarting Civilization V..." -Color "Green"
                    if ($PSCmdlet.ShouldProcess($config.GameExecutablePath, "Start game")) {
                        Start-Process $config.GameExecutablePath
                        Start-Sleep -Seconds 5
                    }
                    return
                }
            }
        } while ($true)
        
    } catch {
        Write-ColorMessage "An error occurred: $_" -Color "Red"
        Write-ColorMessage "Stack trace: $($_.ScriptStackTrace)" -Color "DarkGray"
        Write-ColorMessage "Press any key to exit..."
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
}

#endregion Main Script Logic

# Execute main function
Start-ModManager