# Civilization V Mod Manager

This script, `CivilizationV_ModManager.ps1`, is designed to help manage and streamline mod configurations for Sid Meier's Civilization V. It handles tasks like backing up save files, cleaning up outdated files, downloading necessary resources, and ensuring compatibility for selected game modes.

## Features
- **Mode Selection**: Choose from various predefined game modes with detailed descriptions.
- **Backup Save Files**: Automatically backs up save files before making changes.
- **File and Folder Cleanup**: Cleans up outdated files and folders based on selected modes.
- **Version Management**: Ensures the local files match the online version for the selected mode.
- **Cache Management**: Clears cache directories when necessary.
- **Download and Extract Updates**: Downloads and extracts necessary files for the selected game mode.
- **Automatic INI Updates**: Updates your `steam.ini` file with the current username.

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
        }
    ],
    "Settings": {
        "BackupSaves": true,
        "CleanupOnModeSwitch": true
    }
}
```

### Fields
- **schemaVersion**: Indicates the version of the JSON schema.
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
  - **BackupSaves**: If true, save files will be backed up.
  - **CleanupOnModeSwitch**: If true, old files and folders will be cleaned up when switching modes.

## Notes
1. Replace the example URLs in the `DLCDownload` and `DocsDownload` fields with actual URLs.
2. Ensure the JSON file is accessible from the `onlineJsonUrl` parameter.
3. The script automatically detects and adapts to your console width for improved readability.

## License
This project is licensed under the MIT License.

