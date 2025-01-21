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

## Requirements

- Windows operating system
- PowerShell 5.1 or newer
- Civilization V with all DLCs installed
- Internet connection (for initial setup and updates)

## Installation
1. Download the script: `CivilizationV_ModManager.ps1`.
2. Place the script in a directory of your choice.
3. Ensure you have PowerShell 5.0 or newer installed.

## Usage
Run the script with the following parameters:
```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$gameRootPath,

    [Parameter(Mandatory = $true)]
    [string]$steamINI ,
    
    [Parameter(Mandatory = $true)]
    [string]$onlineJsonUrl
)
```
### Example
```powershell
powershell -ExecutionPolicy Bypass -File CivilizationV_ModManager.ps1 -gameRootPath "C:\Games\Civ5" -steamINI "steam.ini" -onlineJsonUrl "https://example.com/civ5/modes.json"
```

## JSON Structure
The script relies on a JSON file to define the available game modes, their descriptions, and related configurations. Here’s an explanation of its structure:

### Example JSON
```json
{
    "schemaVersion": "1.0",
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
            "DLCDownload": "https://example.com/civ5/civ5_VoxPopuli_4.17.8 _dlc.zip",
            "DocsDownload": "https://example.com/civ5/civ5_VoxPopuli_4.17.8 _dlc.zip"
        }
    ],
    "Settings": {
        "BackupUserData": true,
        "CleanupOnModeSwitch": true
    }
}
```

### Fields
- **schemaVersion**: Indicates the version of the JSON schema.
- **ScriptUpdateUrl**: URL to download latest version of the script
- **lastUpdated**: The last update date for this JSON file.
- **PlayModes**: An array of objects defining available game modes.
  - **Name**: The name of the game mode.
  - **Description**: A detailed description of the mode.
  - **MultiplayerCompatible**: Indicates if the mode supports multiplayer.
  - **OnlineVersion**: An object containing version information for:
    - **DLC**: The version of DLC files.
    - **MyDocuments**: The version of files in the MyDocuments folder.
  - **Files**: A list of specific files associated with this mode.
  - **Folders**: A list of specific folders associated with this mode.
  - **DLCDownload**: (Optional) The URL to download DLC files.
  - **DocsDownload**: (Optional) The URL to download files for the MyDocuments folder.
- **Settings**: Global settings for the script.
  - **BackupUserData**: If true, save files and user mod data will be backed up.
  - **CleanupOnModeSwitch**: If true, old files and folders will be cleaned up when switching modes.

## Notes
1. Replace the example URLs in the `DLCDownload` and `DocsDownload` fields with actual URLs.
2. Ensure the JSON file is accessible from the `onlineJsonUrl` parameter.
3. The script automatically detects and adapts to your console width for improved readability.

## License
This project is licensed under the MIT License.

