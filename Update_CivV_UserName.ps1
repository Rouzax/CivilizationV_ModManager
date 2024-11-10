# Define file paths
$iniFilePath = "D:\Games\Sid Meier's Civilization V\steam_api.ini"
$gameExecutablePath = "D:\Games\Sid Meier's Civilization V\CivilizationV_DX11.exe"

$header = "Civilization V Configuration Updater"

# Function to display a header
function Show-Header {
    param (
        [string]$Text
    )
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host $Text -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
}

# Function to display a separator
function Show-Seperator {
    Write-Host "------------------------------------------" -ForegroundColor DarkYellow
}

# Get the current logged-on username and capitalize the first letter of each word
$TextInfo = (Get-Culture).TextInfo
$currentUserName = $TextInfo.ToTitleCase($env:USERNAME)

# Start of the script
Clear-Host
Show-Header $header

# Check if the INI file exists
if (-Not (Test-Path -Path $iniFilePath)) {
    Write-Host "Error: INI file not found at $iniFilePath" -ForegroundColor Red
    exit 1
} else {
    Write-Host "INI file found at:" -ForegroundColor Green
    Write-Host "  $iniFilePath" -ForegroundColor White
}

Show-Seperator

try {
    # Read the content of the INI file
    Write-Host "Reading INI file..." -ForegroundColor Cyan
    $fileContent = Get-Content -Path $iniFilePath -ErrorAction Stop

    # Update the UserName line
    if ($fileContent -match 'UserName=') {
        $fileContent = $fileContent -replace '(?m)^UserName=.*$', "UserName=$currentUserName"
        Write-Host "UserName updated to:" -ForegroundColor Green
        Write-Host "  $currentUserName" -ForegroundColor White
    } else {
        Write-Host "Error: UserName field not found in INI file." -ForegroundColor Red
        exit 1
    }

    # Save the updated content back to the file without BOM
    Write-Host "Saving updates to INI file..." -ForegroundColor Cyan
	Set-Content -Path $iniFilePath -Value $fileContent -ErrorAction Stop
    Write-Host "INI file updated successfully." -ForegroundColor Green

} catch {
    Write-Host "Error: Failed to update INI file." -ForegroundColor Red
    Write-Host "Details: $_" -ForegroundColor White
    exit 1
}

Show-Seperator

# Check if the game executable exists
if (-Not (Test-Path -Path $gameExecutablePath)) {
    Write-Host "Error: Game executable not found at $gameExecutablePath" -ForegroundColor Red
    exit 1
} else {
    Write-Host "Game executable found at:" -ForegroundColor Green
    Write-Host "  $gameExecutablePath" -ForegroundColor White
}

Show-Seperator

try {
    # Start the game
    Write-Host "Launching Civilization V..." -ForegroundColor Cyan
    Start-Process -FilePath $gameExecutablePath -ErrorAction Stop
    Write-Host "Civilization V launched successfully." -ForegroundColor Green
} catch {
    Write-Host "Error: Failed to launch Civilization V." -ForegroundColor Red
    Write-Host "Details: $_" -ForegroundColor White
    exit 1
}

Show-Seperator

# Pause for 5 seconds before ending the script
Start-Sleep -Seconds 5
