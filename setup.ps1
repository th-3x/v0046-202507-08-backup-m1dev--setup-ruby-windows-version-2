# Unified Setup Script for Windows Development Environment
# This script handles PHP, Redis, MariaDB, and Laravel setup based on config.json

# Set error action preference
$ErrorActionPreference = "Stop"

# Script initialization
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path -Parent $scriptPath
$configPath = Join-Path $scriptDir "config.json"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $scriptDir "logs\setup_$timestamp.log"

# Create logs directory if it doesn't exist
if (-not (Test-Path (Join-Path $scriptDir "logs"))) {
    New-Item -ItemType Directory -Path (Join-Path $scriptDir "logs") -Force | Out-Null
}

# Initialize log file
"[$timestamp] Setup started" | Out-File -FilePath $logFile -Encoding utf8

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

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Log "This script requires administrator privileges for some operations." "WARNING"
    Write-Log "Some features may not work correctly without admin rights." "WARNING"
}

# Load configuration
try {
    Write-Log "Loading configuration from $configPath"
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    Write-Log "Configuration loaded successfully" "SUCCESS"
} catch {
    Write-Log "Failed to load configuration: $_" "ERROR"
    exit 1
}

# Create scripts directory if it doesn't exist
if (-not (Test-Path $config.paths.scripts_dir)) {
    New-Item -ItemType Directory -Path $config.paths.scripts_dir -Force | Out-Null
    Write-Log "Created scripts directory: $($config.paths.scripts_dir)" "SUCCESS"
}

# Display setup information
Write-Host "`n========== Windows Development Environment Setup ==========" -ForegroundColor Magenta
Write-Host "This script will set up the following components based on config.json:" -ForegroundColor Magenta

if ($config.components.php.enabled) {
    Write-Host "✓ PHP $($config.components.php.version)" -ForegroundColor Green
} else {
    Write-Host "✗ PHP (disabled)" -ForegroundColor Gray
}

if ($config.components.redis.enabled) {
    Write-Host "✓ Redis (Windows)" -ForegroundColor Green
} else {
    Write-Host "✗ Redis (disabled)" -ForegroundColor Gray
}

if ($config.components.mariadb.enabled) {
    Write-Host "✓ MariaDB" -ForegroundColor Green
} else {
    Write-Host "✗ MariaDB (disabled)" -ForegroundColor Gray
}

if ($config.components.laravel.enabled) {
    Write-Host "✓ Laravel $($config.components.laravel.version)" -ForegroundColor Green
} else {
    Write-Host "✗ Laravel (disabled)" -ForegroundColor Gray
}

Write-Host "========================================================`n" -ForegroundColor Magenta

# Confirm setup
$confirmation = Read-Host "Do you want to proceed with the setup? (y/n)"
if ($confirmation -ne "y") {
    Write-Log "Setup cancelled by user" "WARNING"
    exit 0
}

# Function to set up PHP
function Setup-PHP {
    Write-Log "Starting PHP setup..." "INFO"
    
    # Check if PHP is already installed
    $phpPath = $null
    if (Test-Path $config.components.php.xampp_path) {
        $phpPath = $config.components.php.xampp_path
        Write-Log "Found PHP in XAMPP: $phpPath" "INFO"
    } elseif (Test-Path $config.components.php.chocolatey_path) {
        $phpPath = $config.components.php.chocolatey_path
        Write-Log "Found PHP from Chocolatey: $phpPath" "INFO"
    }
    
    if ($phpPath) {
        Write-Log "PHP is already installed at: $phpPath" "SUCCESS"
        
        # Create PHP switcher batch script
        $phpBatchSwitcherPath = Join-Path $config.paths.scripts_dir "use_php.bat"
        
        @"
@echo off
REM PHP Switcher Script
echo Switching to PHP at: $phpPath

REM Add PHP to the beginning of PATH for this session only
set PATH=$phpPath;%PATH%

REM Verify PHP version
php -v

echo.
echo PHP is now active in this terminal session.
echo This change only affects the current terminal window.
"@ | Out-File -FilePath $phpBatchSwitcherPath -Encoding ASCII
        
        Write-Log "Created PHP batch switcher script at: $phpBatchSwitcherPath" "SUCCESS"
        
        # Create PowerShell version of the PHP switcher script
        $phpPSSwitcherPath = Join-Path $config.paths.scripts_dir "use_php.ps1"
        
        $phpScript = @'
# PowerShell script to add PHP to the current session's PATH
$phpPath = "{0}"
$env:PATH = "$phpPath;$env:PATH"

Write-Host "Switching to PHP at: $phpPath"
# Verify PHP version
try {{
    php -v
    Write-Host "`nPHP is now active in this terminal session."
    Write-Host "This change only affects the current terminal window."
}} catch {{
    Write-Host "`nError: Failed to execute PHP. Please verify the path: $phpPath" -ForegroundColor Red
}}
'@ -f $phpPath
        
        $phpScript | Out-File -FilePath $phpPSSwitcherPath -Encoding UTF8
        
        Write-Log "Created PHP PowerShell switcher script at: $phpPSSwitcherPath" "SUCCESS"
    } else {
        # PHP not found, install via Chocolatey
        Write-Log "PHP not found, attempting to install via Chocolatey..." "INFO"
        
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
                return $false
            }
        }
        
        # Install PHP
        try {
            Write-Log "Installing PHP $($config.components.php.version)..." "INFO"
            choco install php --version=$($config.components.php.version) -y
            
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Failed to install PHP via Chocolatey" "ERROR"
                return $false
            }
            
            Write-Log "PHP installed successfully" "SUCCESS"
            
            # Create PHP switcher batch script
            $phpBatchSwitcherPath = Join-Path $config.paths.scripts_dir "use_php.bat"
            
            @"
@echo off
REM PHP Switcher Script
echo Switching to PHP at: C:\tools\php$($config.components.php.version -replace '\.')

REM Add PHP to the beginning of PATH for this session only
set PATH=C:\tools\php$($config.components.php.version -replace '\.');%PATH%

REM Verify PHP version
php -v

echo.
echo PHP is now active in this terminal session.
echo This change only affects the current terminal window.
"@ | Out-File -FilePath $phpBatchSwitcherPath -Encoding ASCII
            
            Write-Log "Created PHP batch switcher script at: $phpBatchSwitcherPath" "SUCCESS"
            
            # Create PowerShell version of the PHP switcher script
            $phpPath = "C:\tools\php$($config.components.php.version -replace '\.')"
            $phpPSSwitcherPath = Join-Path $config.paths.scripts_dir "use_php.ps1"
            
            $phpScript = @'
# PowerShell script to add PHP to the current session's PATH
$phpPath = "{0}"
$env:PATH = "$phpPath;$env:PATH"

Write-Host "Switching to PHP at: $phpPath"
# Verify PHP version
try {{
    php -v
    Write-Host "`nPHP is now active in this terminal session."
    Write-Host "This change only affects the current terminal window."
}} catch {{
    Write-Host "`nError: Failed to execute PHP. Please verify the path: $phpPath" -ForegroundColor Red
}}
'@ -f $phpPath
            
            $phpScript | Out-File -FilePath $phpPSSwitcherPath -Encoding UTF8
            
            Write-Log "Created PHP PowerShell switcher script at: $phpPSSwitcherPath" "SUCCESS"
        } catch {
            Write-Log "Failed to install PHP: $_" "ERROR"
            return $false
        }
    }
    
    return $true
}

# Function to set up Redis
function Setup-Redis {
    Write-Log "Starting Redis setup..." "INFO"
    
    $redisDir = $config.components.redis.install_dir
    $redisPort = $config.components.redis.port
    $redisMaxMemory = $config.components.redis.max_memory
    $redisMaxMemoryPolicy = $config.components.redis.max_memory_policy
    $redisPersistence = $config.components.redis.persistence
    
    # Check if Redis is already installed
    $redisService = Get-Service -Name "Redis" -ErrorAction SilentlyContinue
    
    if ($redisService) {
        Write-Log "Redis is already installed as a Windows service" "SUCCESS"
    } else {
        # Create Redis directories
        if (-not (Test-Path $redisDir)) {
            New-Item -ItemType Directory -Path $redisDir -Force | Out-Null
            Write-Log "Created Redis directory: $redisDir" "SUCCESS"
        }
        
        # Create logs and data directories
        $logsDir = Join-Path $redisDir "logs"
        $dataDir = Join-Path $redisDir "data"
        
        if (-not (Test-Path $logsDir)) {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
            Write-Log "Created logs directory: $logsDir" "SUCCESS"
        }
        
        if (-not (Test-Path $dataDir)) {
            New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
            Write-Log "Created data directory: $dataDir" "SUCCESS"
        }
        
        # Download Redis
        $downloadUrl = "https://github.com/microsoftarchive/redis/releases/download/win-3.0.504/Redis-x64-3.0.504.zip"
        $downloadPath = Join-Path $env:TEMP "redis.zip"
        
        try {
            Write-Log "Downloading Redis for Windows..." "INFO"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $downloadPath
            Write-Log "Redis downloaded successfully" "SUCCESS"
            
            # Extract Redis
            Write-Log "Extracting Redis..." "INFO"
            Expand-Archive -Path $downloadPath -DestinationPath $redisDir -Force
            Write-Log "Redis extracted to $redisDir" "SUCCESS"
            
            # Clean up the zip file
            Remove-Item $downloadPath -Force
        } catch {
            Write-Log "Failed to download or extract Redis: $_" "ERROR"
            return $false
        }
        
        # Generate Redis configuration
        $configPath = Join-Path $redisDir "redis.conf"
        
        # Create Redis configuration
        $redisConfig = @"
# Redis configuration file generated by setup script

# Network
port $redisPort
bind 127.0.0.1

# General
daemonize no
pidfile "$redisDir\redis.pid"
loglevel notice
logfile "$logsDir\redis.log"

# Memory Management
maxmemory $redisMaxMemory
maxmemory-policy $redisMaxMemoryPolicy

# Persistence
dir "$dataDir"
"@
        
        # Add persistence configuration if enabled
        if ($redisPersistence) {
            $redisConfig += @"

# Persistence Configuration
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
"@
        }
        
        # Write configuration to file
        $redisConfig | Out-File -FilePath $configPath -Encoding utf8
        Write-Log "Redis configuration generated at $configPath" "SUCCESS"
        
        # Install Redis as a Windows service
        $redisSvcPath = Join-Path $redisDir "redis-server.exe"
        
        if (-not (Test-Path $redisSvcPath)) {
            Write-Log "Redis server executable not found at $redisSvcPath" "ERROR"
            return $false
        }
        
        # Install Redis service
        try {
            Write-Log "Installing Redis as a Windows service..." "INFO"
            $installArgs = "--service-install --service-name Redis"
            $installService = Start-Process -FilePath $redisSvcPath -ArgumentList $installArgs -NoNewWindow -Wait -PassThru
            
            if ($installService.ExitCode -ne 0) {
                Write-Log "Failed to install Redis service. Exit code: $($installService.ExitCode)" "ERROR"
                return $false
            }
            
            Write-Log "Redis service installed successfully" "SUCCESS"
            
            # Start the Redis service
            Start-Service -Name "Redis"
            Write-Log "Redis service started" "SUCCESS"
        } catch {
            Write-Log "Failed to install or start Redis service: $_" "ERROR"
            return $false
        }
        
        # Create Redis CLI shortcut
        $redisCliPath = Join-Path $redisDir "redis-cli.exe"
        $shortcutPath = Join-Path $config.paths.scripts_dir "redis-cli.lnk"
        
        try {
            $WshShell = New-Object -ComObject WScript.Shell
            $Shortcut = $WshShell.CreateShortcut($shortcutPath)
            $Shortcut.TargetPath = $redisCliPath
            $Shortcut.WorkingDirectory = $redisDir
            $Shortcut.Description = "Redis Command Line Interface"
            $Shortcut.Save()
            
            Write-Log "Redis CLI shortcut created at: $shortcutPath" "SUCCESS"
        } catch {
            Write-Log "Failed to create Redis CLI shortcut: $_" "WARNING"
        }
    }
    
    # Create Redis test script
    $redisTestPath = Join-Path $config.paths.scripts_dir "test_redis.ps1"
    
    @"
# Redis Test Script
Write-Host "Testing Redis connection..." -ForegroundColor Cyan

try {
    `$redisCliPath = "$redisDir\redis-cli.exe"
    `$pingResult = & `$redisCliPath ping
    
    if (`$pingResult -eq "PONG") {
        Write-Host "Redis connection successful! Response: `$pingResult" -ForegroundColor Green
    } else {
        Write-Host "Redis connection test returned unexpected result: `$pingResult" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to test Redis connection: `$_" -ForegroundColor Red
}
"@ | Out-File -FilePath $redisTestPath -Encoding utf8
    
    Write-Log "Created Redis test script at: $redisTestPath" "SUCCESS"
    
    return $true
}

# Function to set up MariaDB
function Setup-MariaDB {
    Write-Log "Starting MariaDB setup..." "INFO"
    
    # Check if MariaDB is already installed
    $mariaDBService = Get-Service -Name "MySQL*" -ErrorAction SilentlyContinue
    
    if ($mariaDBService) {
        Write-Log "MariaDB/MySQL service is already installed" "SUCCESS"
    } else {
        # Install MariaDB via Chocolatey
        try {
            Write-Log "Installing MariaDB via Chocolatey..." "INFO"
            choco install mariadb -y
            
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Failed to install MariaDB via Chocolatey" "ERROR"
                return $false
            }
            
            Write-Log "MariaDB installed successfully" "SUCCESS"
            
            # Start the MariaDB service
            Start-Service -Name "MySQL"
            Write-Log "MariaDB service started" "SUCCESS"
        } catch {
            Write-Log "Failed to install or start MariaDB: $_" "ERROR"
            return $false
        }
    }
    
    # Create database and user for Laravel
    $dbName = $config.components.mariadb.database_name
    $dbUser = $config.components.mariadb.user
    $dbPassword = $config.components.mariadb.password
    
    # Create SQL script
    $sqlScriptPath = Join-Path $env:TEMP "create_db.sql"
    
    @"
CREATE DATABASE IF NOT EXISTS $dbName;
CREATE USER IF NOT EXISTS '$dbUser'@'localhost' IDENTIFIED BY '$dbPassword';
GRANT ALL PRIVILEGES ON $dbName.* TO '$dbUser'@'localhost';
FLUSH PRIVILEGES;
"@ | Out-File -FilePath $sqlScriptPath -Encoding utf8
    
    # Execute SQL script
    try {
        Write-Log "Creating database and user for Laravel..." "INFO"
        mysql -u root -e "source $sqlScriptPath"
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to create database and user" "ERROR"
            Remove-Item $sqlScriptPath -Force
            return $false
        }
        
        Write-Log "Database and user created successfully" "SUCCESS"
        Remove-Item $sqlScriptPath -Force
    } catch {
        Write-Log "Failed to create database and user: $_" "ERROR"
        Remove-Item $sqlScriptPath -Force
        return $false
    }
    
    # Create MariaDB test script
    $mariaDBTestPath = Join-Path $config.paths.scripts_dir "test_mariadb.ps1"
    
    @"
# MariaDB Test Script
Write-Host "Testing MariaDB connection..." -ForegroundColor Cyan

try {
    `$result = mysql -u $dbUser -p$dbPassword -e "SELECT 'Connection successful!' AS Message;"
    Write-Host "MariaDB connection successful!" -ForegroundColor Green
} catch {
    Write-Host "Failed to connect to MariaDB: `$_" -ForegroundColor Red
}
"@ | Out-File -FilePath $mariaDBTestPath -Encoding utf8
    
    Write-Log "Created MariaDB test script at: $mariaDBTestPath" "SUCCESS"
    
    return $true
}

# Function to set up Laravel
function Setup-Laravel {
    Write-Log "Starting Laravel setup..." "INFO"
    
    $projectName = $config.components.laravel.project_name
    $projectPath = Join-Path $config.paths.project_root $projectName
    
    # Check if Laravel project already exists
    if (Test-Path $projectPath) {
        Write-Log "Laravel project already exists at: $projectPath" "SUCCESS"
    } else {
        # Create Laravel project
        try {
            Write-Log "Creating Laravel project: $projectName" "INFO"
            
            # Create project directory
            New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
            Set-Location $projectPath
            
            # Create Laravel project
            composer create-project laravel/laravel:$($config.components.laravel.version) .
            
            if ($LASTEXITCODE -ne 0) {
                Write-Log "Failed to create Laravel project" "ERROR"
                return $false
            }
            
            Write-Log "Laravel project created successfully" "SUCCESS"
            
            # Install Redis and MariaDB dependencies
            Write-Log "Installing Redis and MariaDB dependencies..." "INFO"
            composer require predis/predis
            composer require doctrine/dbal
            
            # Configure .env file
            Write-Log "Configuring .env file..." "INFO"
            
            # Read current .env file
            $envPath = Join-Path $projectPath ".env"
            $envContent = Get-Content $envPath
            
            # Update .env file with our configuration
            $envContent = $envContent -replace "CACHE_DRIVER=.*", "CACHE_DRIVER=$($config.components.laravel.cache_driver)"
            $envContent = $envContent -replace "DB_CONNECTION=.*", "DB_CONNECTION=$($config.components.laravel.database_driver)"
            $envContent = $envContent -replace "DB_HOST=.*", "DB_HOST=127.0.0.1"
            $envContent = $envContent -replace "DB_PORT=.*", "DB_PORT=$($config.components.mariadb.port)"
            $envContent = $envContent -replace "DB_DATABASE=.*", "DB_DATABASE=$($config.components.mariadb.database_name)"
            $envContent = $envContent -replace "DB_USERNAME=.*", "DB_USERNAME=$($config.components.mariadb.user)"
            $envContent = $envContent -replace "DB_PASSWORD=.*", "DB_PASSWORD=$($config.components.mariadb.password)"
            
            # Add Redis configuration
            $envContent += @"

REDIS_CLIENT=$($config.components.laravel.redis_client)
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=$($config.components.redis.port)
"@
            
            # Write updated .env file
            $envContent | Set-Content $envPath
            
            Write-Log ".env file configured successfully" "SUCCESS"
            
            # Create API if enabled
            if ($config.components.laravel.create_api) {
                Write-Log "Setting up API..." "INFO"
                
                # Create Product model and migration
                php artisan make:model Product -m
                
                # Create API controller
                php artisan make:controller Api/ProductController --api
                
                # Create routes file for API
                $apiRoutesPath = Join-Path $projectPath "routes\api.php"
                
                @"
<?php

use App\Http\Controllers\Api\ProductController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| API Routes
|--------------------------------------------------------------------------
*/

Route::middleware('auth:sanctum')->get('/user', function (Request \$request) {
    return \$request->user();
});

// Product API Routes
Route::apiResource('products', ProductController::class);

// Redis Status Route
Route::get('/redis-status', function () {
    try {
        \$redis = app()->make('redis');
        \$redis->ping();
        
        return response()->json([
            'success' => true,
            'message' => 'Redis connection successful',
            'status' => 'online'
        ]);
    } catch (\Exception \$e) {
        return response()->json([
            'success' => false,
            'message' => 'Redis connection failed: ' . \$e->getMessage(),
            'status' => 'offline'
        ], 500);
    }
});
"@ | Set-Content $apiRoutesPath
                
                Write-Log "API setup completed successfully" "SUCCESS"
            }
            
            # Create Laravel start script
            $laravelStartPath = Join-Path $config.paths.scripts_dir "start_laravel.bat"
            
            @"
@echo off
REM Laravel Start Script
echo Starting Laravel development server...

cd $projectPath
php artisan serve

echo Laravel server stopped.
"@ | Out-File -FilePath $laravelStartPath -Encoding ASCII
            
            Write-Log "Created Laravel start script at: $laravelStartPath" "SUCCESS"
        } catch {
            Write-Log "Failed to set up Laravel: $_" "ERROR"
            return $false
        }
    }
    
    return $true
}

# Main setup process
$setupResults = @{}

# Set up components based on configuration
if ($config.components.php.enabled) {
    $setupResults["PHP"] = Setup-PHP
}

if ($config.components.redis.enabled) {
    $setupResults["Redis"] = Setup-Redis
}

if ($config.components.mariadb.enabled) {
    $setupResults["MariaDB"] = Setup-MariaDB
}

if ($config.components.laravel.enabled) {
    $setupResults["Laravel"] = Setup-Laravel
}

# Display setup summary
Write-Host "`n========== Setup Summary ==========" -ForegroundColor Magenta

foreach ($component in $setupResults.Keys) {
    if ($setupResults[$component]) {
        Write-Host "✓ $component setup completed successfully" -ForegroundColor Green
    } else {
        Write-Host "✗ $component setup failed" -ForegroundColor Red
    }
}

Write-Host "================================`n" -ForegroundColor Magenta

# Create README.md with setup information
$readmePath = Join-Path $scriptDir "README.md"

@"
# Windows Development Environment

This is a unified setup for PHP, Redis, MariaDB, and Laravel on Windows without using WSL or virtualization.

## Components Installed

| Component | Status | Version | Notes |
|-----------|--------|---------|-------|
"@ | Out-File -FilePath $readmePath -Encoding utf8

if ($config.components.php.enabled) {
    if ($setupResults["PHP"]) {
        "| PHP | ✅ Installed | $($config.components.php.version) | Extensions: $($config.components.php.extensions -join ', ') |" | Out-File -FilePath $readmePath -Append -Encoding utf8
    } else {
        "| PHP | ❌ Failed | $($config.components.php.version) | Installation failed |" | Out-File -FilePath $readmePath -Append -Encoding utf8
    }
} else {
    "| PHP | ⚪ Disabled | - | Not installed |" | Out-File -FilePath $readmePath -Append -Encoding utf8
}

if ($config.components.redis.enabled) {
    if ($setupResults["Redis"]) {
        "| Redis | ✅ Installed | 3.0.504 | Running on port $($config.components.redis.port) |" | Out-File -FilePath $readmePath -Append -Encoding utf8
    } else {
        "| Redis | ❌ Failed | 3.0.504 | Installation failed |" | Out-File -FilePath $readmePath -Append -Encoding utf8
    }
} else {
    "| Redis | ⚪ Disabled | - | Not installed |" | Out-File -FilePath $readmePath -Append -Encoding utf8
}

if ($config.components.mariadb.enabled) {
    if ($setupResults["MariaDB"]) {
        "| MariaDB | ✅ Installed | Latest | Running on port $($config.components.mariadb.port) |" | Out-File -FilePath $readmePath -Append -Encoding utf8
    } else {
        "| MariaDB | ❌ Failed | Latest | Installation failed |" | Out-File -FilePath $readmePath -Append -Encoding utf8
    }
} else {
    "| MariaDB | ⚪ Disabled | - | Not installed |" | Out-File -FilePath $readmePath -Append -Encoding utf8
}

if ($config.components.laravel.enabled) {
    if ($setupResults["Laravel"]) {
        "| Laravel | ✅ Installed | $($config.components.laravel.version) | Project: $($config.components.laravel.project_name) |" | Out-File -FilePath $readmePath -Append -Encoding utf8
    } else {
        "| Laravel | ❌ Failed | $($config.components.laravel.version) | Installation failed |" | Out-File -FilePath $readmePath -Append -Encoding utf8
    }
} else {
    "| Laravel | ⚪ Disabled | - | Not installed |" | Out-File -FilePath $readmePath -Append -Encoding utf8
}

@"

## Getting Started

### Scripts

The following scripts are available in the \`scripts\` directory:

| Script | Description |
|--------|-------------|
| use_php.bat | Switch to PHP for the current terminal session (cmd) |
| use_php.ps1 | Switch to PHP for the current PowerShell session |
| test_redis.ps1 | Test Redis connection |
| test_mariadb.ps1 | Test MariaDB connection |
| start_laravel.bat | Start Laravel development server |

### Laravel Project

The Laravel project is located at: \`$($config.paths.project_root)\$($config.components.laravel.project_name)\`

To start the Laravel development server:
\`\`\`
cd $($config.paths.project_root)\$($config.components.laravel.project_name)
php artisan serve
\`\`\`

### API Endpoints

The following API endpoints are available:

| Endpoint | Method | Description |
|----------|--------|-------------|
| /api/products | GET | Get all products |
| /api/products/{id} | GET | Get a specific product |
| /api/products | POST | Create a new product |
| /api/products/{id} | PUT/PATCH | Update a product |
| /api/products/{id} | DELETE | Delete a product |
| /api/redis-status | GET | Check Redis connection status |

## Configuration

The setup is configured using \`config.json\`. You can modify this file to change the setup options.

## Troubleshooting

Check the log files in the \`logs\` directory for detailed information about the setup process.

## License

This project is open-source and available under the MIT License.
"@ | Out-File -FilePath $readmePath -Append -Encoding utf8

Write-Log "Setup documentation created at: $readmePath" "SUCCESS"

# Final message
Write-Host "`nSetup completed. See $readmePath for detailed information." -ForegroundColor Green
Write-Host "Log file: $logFile" -ForegroundColor Cyan

# Display important usage instructions
if ($config.components.php.enabled -and $setupResults["PHP"]) {
    Write-Host "`nIMPORTANT: To use PHP in your current PowerShell session, run:" -ForegroundColor Yellow
    Write-Host "    $($config.paths.scripts_dir)\use_php.ps1" -ForegroundColor Yellow
    Write-Host "This will add PHP to your PATH for the current session only." -ForegroundColor Yellow
}
