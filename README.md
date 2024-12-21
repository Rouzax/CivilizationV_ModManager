# Civilization V Mod Manager

## Overview
This script automates the management of Sid Meier's Civilization V game configurations, save backups, and mod updates. It is particularly useful for updating DLC and MyDocuments files, clearing caches, and ensuring the game is in the correct state for a selected game mode.

## Requirements
- Windows PowerShell (Version 5.1 or later)
- Internet access for downloading online resources and game files

## Parameters
The script requires three mandatory parameters:

- `-gameRootPath`: Specifies the root path where Civilization V is installed.
- `-steamINI`: Specifies the path to the Steam configuration INI file.
- `-onlineJsonUrl`: Specifies the URL for the online JSON resource containing game mode information.

## Features
1. **Dynamic Mode Selection:**
   - Allows users to choose from a list of available game modes.
   - Automatically updates DLC and MyDocuments files based on the selected mode.

2. **Save Game Backup:**
   - Backs up existing save files before updating game files.

3. **Online Resource Integration:**
   - Retrieves game mode information and version updates from an online JSON file.

4. **Cache Management:**
   - Clears cache directories if required, ensuring a clean game state.

5. **File Management:**
   - Cleans up old files during mode switches.
   - Downloads and extracts new DLC or MyDocuments files as needed.

6. **Error Handling:**
   - Provides detailed error messages for any issues encountered during execution.

## Usage
Run the script with the following syntax:

```powershell
./CivilizationV_ModManager.ps1 -gameRootPath "C:\Path\To\Game" -steamINI "steam_appid.ini" -onlineJsonUrl "https://example.com/game_modes.json"
```

### Example Workflow
1. The script checks the provided paths and verifies their existence.
2. Updates the Steam INI file with the current Windows username.
3. Retrieves online game mode data from the provided JSON URL.
4. Displays a menu of available game modes for the user to select.
5. Cleans up old files and downloads new DLC or MyDocuments files if needed.
6. Backs up save games before any updates.
7. Clears cache directories if required.
8. Starts the game in the selected mode.

## Notes
- Ensure that the game root path and Steam INI file path are correct.
- The script will not proceed without internet access if online resources are required.

## License
This script is open-source and provided "as is." Use it at your own risk.

