# Civilization V Configuration Updater Script

This PowerShell script automates the process of updating the `steam_api.ini` file for *Sid Meier's Civilization V*. It specifically updates the `UserName` field in the configuration file to match the current logged-in Windows user. The script also verifies the existence of both the game executable and the configuration file before attempting to launch the game.

## Features

- Updates the `UserName` field in the `steam_api.ini` file to the current logged-in Windows username.
- Checks if the `steam_api.ini` file and the Civilization V executable are present at specified locations.
- Attempts to launch *Sid Meier's Civilization V* if all checks pass.
- Provides console feedback with color-coded messages indicating success, error, and informational updates.
- Includes basic error handling for missing files and failures during execution.
- Pauses for 5 seconds before the script ends to give the user time to review the final output.

## Prerequisites

- PowerShell (the script has been tested with PowerShell 5.1).
- Sid Meier's Civilization V installed on your system.

## Usage

### 1. Download or Clone the Repository

To use this script, download or clone this repository to your local machine.

### 2. Modify the Script Paths (if necessary)

Open the script (`Update_CivV_UserName.ps1`) in a text editor and ensure the following paths are correctly set for your system:

- **`steam_api.ini`**: The location of your *Sid Meier's Civilization V* configuration file.
- **`Civilization V Executable`**: The path to the Civilization V executable (typically `CivilizationV_DX11.exe`).

For example:
```powershell
$iniFilePath = "D:\Games\Sid Meier's Civilization V\steam_api.ini"
$gameExecutablePath = "D:\Games\Sid Meier's Civilization V\CivilizationV_DX11.exe"
```

### 3. Running the Script

#### Option 1: Run Directly in PowerShell
1. Open **PowerShell** as an administrator (if needed).
2. Navigate to the folder where the script is located using the `cd` command.
3. Run the script:
   ```powershell
   .\Update_CivV_UserName.ps1
   ```

#### Option 2: Create a Shortcut to Run the Script
1. Create a shortcut to **PowerShell** and use the following command as the shortcut target:
   ```plaintext
   powershell.exe -NoExit -ExecutionPolicy Bypass -File "C:\Path\To\Update_CivV_UserName.ps1"
   ```
   Replace `"C:\Path\To\Update_CivV_UserName.ps1"` with the actual path to the script on your system.
2. Double-click the shortcut to run the script directly.

### 4. Optional: Launch Civilization V
The script will attempt to launch Civilization V once the necessary conditions are met. This feature is enabled by default. If you want to prevent the game from launching automatically, simply comment out or remove the following line in the script:
```powershell
Start-Process -FilePath $gameExecutablePath -ErrorAction Stop
```

### 5. Customize the Console Output
The script provides color-coded feedback to the user:
- **Green**: For success messages.
- **Red**: For error messages.
- **Cyan**: For informational messages.
- **Yellow**: For headers and separators.

### 6. Modify the `UserName` Field Capitalization
The script automatically capitalizes the first letter of each word in the Windows username using `.ToTitleCase()`. If you wish to modify this behavior, you can adjust the `$currentUserName` logic.

## Example Output

When the script runs, you will see output similar to the following:

```plaintext
==========================================
Civilization V Configuration Updater
==========================================
Initializing script...
------------------------------------------
INI file found at:
  D:\Games\Sid Meier's Civilization V\steam_api.ini
------------------------------------------
Reading INI file...
UserName updated to:
  JohnDoe
Saving updates to INI file...
INI file updated successfully.
------------------------------------------
Game executable found at:
  D:\Games\Sid Meier's Civilization V\CivilizationV_DX11.exe
------------------------------------------
Launching Civilization V...
Civilization V launched successfully.
------------------------------------------
Pausing for 5 seconds before exiting...
Script execution completed.
```

## License

This script is open-source and available under the [MIT License](LICENSE).
