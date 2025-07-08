# PHP Installation Script
# This script installs PHP using Chocolatey

param (
    [string]$Version = "8.3",
    [string[]]$Extensions = @("redis", "mbstring", "xml", "curl", "mysql"),
    [string]$MemoryLimit = "256M",
    [int]$MaxExecutionTime = 300,
    [string]$PostMaxSize = "50M",
    [string]$UploadMaxFilesize = "50M"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Log file
$logFile = Join-Path $PSScriptRoot "..\logs\php_install_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

# Function to write to log and console
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Output to console with color based on level
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    # Also append to log file
    $logMessage | Out-File -FilePath $logFile -Append
}

# Create logs directory if it doesn't exist
$logsDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

Write-Log "Starting PHP $Version installation..."

# Check if Chocolatey is installed
try {
    $chocoVersion = choco --version
    Write-Log "Chocolatey is installed: $chocoVersion" "SUCCESS"
} catch {
    Write-Log "Chocolatey is not installed. Installing..." "INFO"
    
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Write-Log "Chocolatey installed successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to install Chocolatey: $_" "ERROR"
        exit 1
    }
}

# Install PHP
try {
    Write-Log "Installing PHP $Version..." "INFO"
    choco install php --version=$Version -y
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to install PHP via Chocolatey" "ERROR"
        exit 1
    }
    
    Write-Log "PHP installed successfully" "SUCCESS"
    
    # Get PHP installation path
    $phpPath = "C:\tools\php$($Version -replace '\.')"
    
    if (-not (Test-Path $phpPath)) {
        Write-Log "PHP installation path not found at: $phpPath" "ERROR"
        exit 1
    }
    
    Write-Log "PHP installed at: $phpPath" "SUCCESS"
    
    # Configure PHP
    $phpIniPath = Join-Path $phpPath "php.ini"
    
    if (-not (Test-Path $phpIniPath)) {
        $phpIniDevPath = Join-Path $phpPath "php.ini-development"
        
        if (Test-Path $phpIniDevPath) {
            Copy-Item -Path $phpIniDevPath -Destination $phpIniPath
            Write-Log "Created php.ini from php.ini-development" "SUCCESS"
        } else {
            Write-Log "php.ini-development not found at: $phpIniDevPath" "ERROR"
            exit 1
        }
    }
    
    # Update PHP configuration
    $phpIniContent = Get-Content -Path $phpIniPath
    
    # Update memory limit
    $phpIniContent = $phpIniContent -replace "memory_limit = .*", "memory_limit = $MemoryLimit"
    
    # Update max execution time
    $phpIniContent = $phpIniContent -replace "max_execution_time = .*", "max_execution_time = $MaxExecutionTime"
    
    # Update post max size
    $phpIniContent = $phpIniContent -replace "post_max_size = .*", "post_max_size = $PostMaxSize"
    
    # Update upload max filesize
    $phpIniContent = $phpIniContent -replace "upload_max_filesize = .*", "upload_max_filesize = $UploadMaxFilesize"
    
    # Enable extensions
    foreach ($extension in $Extensions) {
        $extensionLine = "extension=$extension"
        
        # Check if extension line exists and is commented out
        $extensionLineIndex = $phpIniContent | ForEach-Object { $_ -match "^;extension=$extension" } | Where-Object { $_ } | Measure-Object
        
        if ($extensionLineIndex.Count -gt 0) {
            # Uncomment extension line
            $phpIniContent = $phpIniContent -replace "^;extension=$extension", "extension=$extension"
            Write-Log "Enabled extension: $extension" "SUCCESS"
        } else {
            # Add extension line if it doesn't exist
            $phpIniContent += "`nextension=$extension"
            Write-Log "Added extension: $extension" "SUCCESS"
        }
    }
    
    # Save updated php.ini
    $phpIniContent | Set-Content -Path $phpIniPath
    Write-Log "PHP configuration updated" "SUCCESS"
    
    # Create PHP version switcher script
    $phpSwitcherPath = Join-Path $PSScriptRoot "use_php.bat"
    
    @"
@echo off
REM PHP Switcher Script
echo Switching to PHP $Version at: $phpPath

REM Add PHP to the beginning of PATH for this session only
set PATH=$phpPath;%PATH%

REM Verify PHP version
php -v

echo.
echo PHP is now active in this terminal session.
echo This change only affects the current terminal window.
"@ | Out-File -FilePath $phpSwitcherPath -Encoding ASCII
    
    Write-Log "Created PHP switcher script at: $phpSwitcherPath" "SUCCESS"
    
    # Create PHP info script
    $phpInfoPath = Join-Path $PSScriptRoot "php_info.php"
    
    @"
<?php
// PHP Info Script
phpinfo();
"@ | Out-File -FilePath $phpInfoPath -Encoding utf8
    
    Write-Log "Created PHP info script at: $phpInfoPath" "SUCCESS"
    
    # Create PHP test script
    $phpTestPath = Join-Path $PSScriptRoot "test_php.bat"
    
    @"
@echo off
REM PHP Test Script
echo Testing PHP installation...

REM Add PHP to the beginning of PATH for this session only
set PATH=$phpPath;%PATH%

REM Verify PHP version
php -v

echo.
echo Testing PHP extensions...
php -m

echo.
echo Testing PHP configuration...
php -i | findstr "memory_limit\|max_execution_time\|post_max_size\|upload_max_filesize"

echo.
echo PHP test completed.
"@ | Out-File -FilePath $phpTestPath -Encoding ASCII
    
    Write-Log "Created PHP test script at: $phpTestPath" "SUCCESS"
} catch {
    Write-Log "Failed to install or configure PHP: $_" "ERROR"
    exit 1
}

Write-Log "PHP installation and configuration completed successfully" "SUCCESS"
