# Civilization V Mod Manager

This script, `CivilizationV_ModManager.ps1`, is designed to help manage and streamline mod configurations for Sid Meier's Civilization V. It handles tasks like backing up save files, cleaning up outdated files, downloading necessary resources, and ensuring compatibility for selected game modes.

## Features

- **Multiple Play Modes**: Easily switch between different game configurations:
  - Standard (Vanilla) Game
  - Enhanced UI (EUI)
  - Vox Populi (Community Balance Patch)
  - Vox Populi Multiplayer
  - Or any that you put online

- **Smart Cache Management**:
  - Downloads are cached to prevent unnecessary re-downloads
  - Automatic cleanup of outdated cache entries
  - Option to clear game cache manually when needed
  - Retry logic for failed downloads with exponential backoff

- **User Data Management**:
  - Automatic backup of save games when switching modes
  - Separate save games for each play mode
  - Preserves mod-specific user data between sessions

- **Offline Support**:
  - Works offline with previously cached content
  - Displays only available options when offline

- **Additional Features**:
  - Automatic username configuration for multiplayer
  - Self-updating capability
  - Clear visual feedback with color-coded console output
  - Compatible with both single-player and multiplayer setups
  - **WhatIf mode** for previewing changes without executing them
  - **Progress indicators** for long-running operations
  - **Quit option** in menu for clean exit

## Requirements

- Windows operating system
- PowerShell 5.1 or newer
- Civilization V with all DLCs installed
- Internet connection (for initial setup and updates)

## Installation

1. Download the script: `CivilizationV_ModManager.ps1`.
2. Place the script in a directory of your choice.
3. Ensure you have PowerShell 5.1 or newer installed.

## Usage

Run the script with the following parameters:

```powershell
.\CivilizationV_ModManager.ps1 -gameRootPath <path> -onlineJsonUrl <url> [-steamINI <filename>]
```

### Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-gameRootPath` | Yes | The root path where Civilization V is installed |
| `-onlineJsonUrl` | Yes | The URL to the online JSON configuration file |
| `-steamINI` | No | The name of the Steam INI file for multiplayer username configuration. If omitted, username updating is skipped. |
| `-WhatIf` | No | Preview what changes would be made without executing them |

### Examples

**Basic usage:**
```powershell
powershell -ExecutionPolicy Bypass -File CivilizationV_ModManager.ps1 `
    -gameRootPath "C:\Games\Civ5" `
    -onlineJsonUrl "https://example.com/civ5/modes.json"
```

**With multiplayer username updating:**
```powershell
powershell -ExecutionPolicy Bypass -File CivilizationV_ModManager.ps1 `
    -gameRootPath "C:\Games\Civ5" `
    -steamINI "steam.ini" `
    -onlineJsonUrl "https://example.com/civ5/modes.json"
```

**Preview mode (no changes made):**
```powershell
.\CivilizationV_ModManager.ps1 `
    -gameRootPath "C:\Games\Civ5" `
    -onlineJsonUrl "https://example.com/civ5/modes.json" `
    -WhatIf
```

**Get help:**
```powershell
Get-Help .\CivilizationV_ModManager.ps1 -Full
```

## JSON Structure

The script relies on a JSON file to define the available game modes, their descriptions, and related configurations. Here's an explanation of its structure:

### Example JSON

```json
{
    "schemaVersion": "1.1",
    "ScriptUpdateUrl": "https://raw.githubusercontent.com/Rouzax/CivilizationV_ModManager/main/CivilizationV_ModManager.ps1",
    "lastUpdated": "2024-12-20",
    "PlayModes": [
        {
            "Name": "Standard",
            "Description": "Classic Civilization V with all official expansions. Features vanilla gameplay and standard AI. Fully compatible with multiplayer and achievements. Perfect for new players.",
            "MultiplayerCompatible": true,
            "OnlineVersion": {
                "DLC": "1.0.0",
                "MyDocuments": "1.0.0"
            },
            "Files": [],
            "Folders": [],
            "DLCDownload": null,
            "DocsDownload": null
        },
        {
            "Name": "Standard with EUI",
            "Description": "Enhanced User Interface (EUI) adds quality-of-life improvements for gameplay. Compatible with multiplayer but may disable achievements.",
            "MultiplayerCompatible": true,
            "OnlineVersion": {
                "DLC": "2.0.0",
                "MyDocuments": "2.0.0"
            },
            "Files": [],
            "Folders": [],
            "DLCDownload": "https://example.com/civ5/eui_dlc.zip",
            "DocsDownload": "https://example.com/civ5/eui_docs.zip"
        },
        {
            "Name": "Vox Populi",
            "Description": "Complete game overhaul with enhanced AI, rebalanced civilizations, and new gameplay systems. Includes improved UI and In-Game Editor. For experienced players seeking challenges.",
            "MultiplayerCompatible": false,
            "OnlineVersion": {
                "DLC": "4.17.8",
                "MyDocuments": "4.17.8"
            },
            "Files": [
                "MyDocuments/Text/VPUI_tips_en_us.xml",
                "MyDocuments/MODS/InGame Editor+ (v 46).civ5mod"
            ],
            "Folders": [
                "DLC/UI_bc1",
                "DLC/VPUI",
                "MyDocuments/MODS/(1) Community Patch",
                "MyDocuments/MODS/(2) Vox Populi",
                "MyDocuments/MODS/(3a) VP - EUI Compatibility Files",
                "MyDocuments/MODS/(4a) Squads for VP",
                "MyDocuments/MODS/InGame Editor+ (v 46)"
            ],
            "DLCDownload": "https://example.com/civ5/civ5_VoxPopuli_4.17.8_dlc.zip",
            "DocsDownload": "https://example.com/civ5/civ5_VoxPopuli_4.17.8_docs.zip"
        }
    ],
    "Settings": {
        "BackupUserData": true,
        "CleanupOnModeSwitch": true
    }
}
```

### Fields

| Field | Description |
|-------|-------------|
| `schemaVersion` | Version of the JSON schema (must be "1.1") |
| `ScriptUpdateUrl` | URL to download the latest version of the script |
| `lastUpdated` | The last update date for this JSON file |
| `PlayModes` | Array of available game mode configurations |
| `Settings` | Global settings for the script |

#### PlayMode Fields

| Field | Description |
|-------|-------------|
| `Name` | The name of the game mode |
| `Description` | A detailed description of the mode |
| `MultiplayerCompatible` | Whether the mode supports multiplayer |
| `OnlineVersion.DLC` | Version of DLC files |
| `OnlineVersion.MyDocuments` | Version of MyDocuments files |
| `Files` | List of specific files associated with this mode |
| `Folders` | List of specific folders associated with this mode |
| `DLCDownload` | (Optional) URL to download DLC files |
| `DocsDownload` | (Optional) URL to download MyDocuments files |

#### Settings Fields

| Field | Description |
|-------|-------------|
| `BackupUserData` | If true, save files and user mod data will be backed up |
| `CleanupOnModeSwitch` | If true, old files and folders will be cleaned up when switching modes |

## Architecture

The script follows software engineering best practices:

- **SOLID Principles**: Single responsibility functions, dependency injection via configuration object
- **DRY**: Reusable helper functions for common operations
- **KISS**: Clear, straightforward logic flow

### Key Components

| Component | Description |
|-----------|-------------|
| `ScriptConfiguration` | Central configuration class containing all paths and settings |
| `ConvertTo-SafeFileName` | Sanitizes strings for safe use as filenames |
| `Copy-FilesWithStructure` | Copies files preserving directory structure |
| `Get-CachePath` | Builds consistent cache paths |
| `Invoke-DownloadWithRetry` | Downloads with retry logic and exponential backoff |
| `Switch-UserData` | Manages backup/restore of user data during mode switches |

### Directory Structure

```
Game Root/
├── ModCache/                    # Downloaded mod archives
│   └── ModeName/
│       └── Version/
│           ├── DLC/
│           └── MyDocuments/
├── version_dlc.json            # DLC version tracking
└── modmanager_cache.json       # Cached JSON configuration

My Documents/My Games/Sid Meier's Civilization 5/
├── ModeSaves/                   # Backed up saves per mode
│   └── ModeName/
├── ModeUserData/                # Backed up mod data per mode
│   └── ModeName/
├── version_mydocuments.json    # MyDocuments version tracking
└── cache/                       # Game cache (cleared on mode switch)
```

## Troubleshooting

### Common Issues

**"No modes available offline"**
- Connect to the internet and run the script to download mod files
- Once downloaded, modes will be available offline

**Download failures**
- The script automatically retries failed downloads up to 3 times
- Check your internet connection if downloads consistently fail
- Verify the URLs in your JSON configuration are correct

**Permission errors**
- Run PowerShell as Administrator if you encounter permission issues
- Ensure the game installation folder is writable

### Debug Mode

Use the `-Verbose` parameter to see detailed operation logs:

```powershell
.\CivilizationV_ModManager.ps1 -gameRootPath "C:\Games\Civ5" -steamINI "steam.ini" -onlineJsonUrl "https://example.com/modes.json" -Verbose
```

## Notes

1. Replace the example URLs in the `DLCDownload` and `DocsDownload` fields with actual URLs.
2. Ensure the JSON file is accessible from the `onlineJsonUrl` parameter.
3. The script automatically detects and adapts to your console width for improved readability.
4. Schema version must be "1.1" for compatibility with this version of the script.

## Version History

| Version | Changes |
|---------|---------|
| 2.0.0 | Major refactoring: SOLID/DRY principles, configuration class, retry logic, WhatIf support, improved error handling |
| 1.0.7 | Previous stable release |

## License

This project is licensed under the MIT License.