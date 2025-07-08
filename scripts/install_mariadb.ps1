# MariaDB Installation Script for Windows
# This script installs MariaDB and configures it for Laravel

param (
    [int]$Port = 3306,
    [string]$RootPassword = "",
    [string]$DatabaseName = "laravel_db",
    [string]$User = "laravel_user",
    [string]$Password = "laravel_password"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Log file
$logFile = Join-Path $PSScriptRoot "..\logs\mariadb_install_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

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

Write-Log "Starting MariaDB installation..."

# Check if MariaDB is already installed
$mariaDBService = Get-Service -Name "MySQL*" -ErrorAction SilentlyContinue

if ($mariaDBService) {
    Write-Log "MariaDB/MySQL service is already installed: $($mariaDBService.Name)" "SUCCESS"
} else {
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
    
    # Install MariaDB
    try {
        Write-Log "Installing MariaDB via Chocolatey..." "INFO"
        
        if ([string]::IsNullOrEmpty($RootPassword)) {
            # Install without root password
            choco install mariadb -y
        } else {
            # Install with root password
            choco install mariadb --params="/Password:$RootPassword" -y
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to install MariaDB via Chocolatey" "ERROR"
            exit 1
        }
        
        Write-Log "MariaDB installed successfully" "SUCCESS"
        
        # Start the MariaDB service
        Start-Service -Name "MySQL"
        Write-Log "MariaDB service started" "SUCCESS"
    } catch {
        Write-Log "Failed to install or start MariaDB: $_" "ERROR"
        exit 1
    }
}

# Create database and user for Laravel
try {
    Write-Log "Creating database and user for Laravel..." "INFO"
    
    # Create SQL script
    $sqlScriptPath = Join-Path $env:TEMP "create_db.sql"
    
    @"
CREATE DATABASE IF NOT EXISTS $DatabaseName;
CREATE USER IF NOT EXISTS '$User'@'localhost' IDENTIFIED BY '$Password';
GRANT ALL PRIVILEGES ON $DatabaseName.* TO '$User'@'localhost';
FLUSH PRIVILEGES;
"@ | Out-File -FilePath $sqlScriptPath -Encoding utf8
    
    # Execute SQL script
    if ([string]::IsNullOrEmpty($RootPassword)) {
        # Execute without password
        mysql -u root -e "source $sqlScriptPath"
    } else {
        # Execute with password
        mysql -u root -p$RootPassword -e "source $sqlScriptPath"
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to create database and user" "ERROR"
        Remove-Item $sqlScriptPath -Force
        exit 1
    }
    
    Write-Log "Database and user created successfully" "SUCCESS"
    Remove-Item $sqlScriptPath -Force
} catch {
    Write-Log "Failed to create database and user: $_" "ERROR"
    if (Test-Path $sqlScriptPath) {
        Remove-Item $sqlScriptPath -Force
    }
    exit 1
}

# Create MariaDB test script
$mariaDBTestPath = Join-Path $PSScriptRoot "test_mariadb.ps1"

@"
# MariaDB Test Script
Write-Host "Testing MariaDB connection..." -ForegroundColor Cyan

try {
    # Test connection to MariaDB
    `$connectionTest = mysql -u $User -p$Password -e "SELECT 'Connection successful!' AS Message;"
    
    if (`$LASTEXITCODE -eq 0) {
        Write-Host "MariaDB connection successful!" -ForegroundColor Green
        
        # Show databases
        Write-Host "`nAvailable databases:" -ForegroundColor Cyan
        mysql -u $User -p$Password -e "SHOW DATABASES;"
        
        # Show tables in Laravel database
        Write-Host "`nTables in $DatabaseName database:" -ForegroundColor Cyan
        mysql -u $User -p$Password -e "USE $DatabaseName; SHOW TABLES;"
        
        # Show MariaDB version
        Write-Host "`nMariaDB version:" -ForegroundColor Cyan
        mysql -u $User -p$Password -e "SELECT VERSION() AS Version;"
        
        # Show MariaDB status
        Write-Host "`nMariaDB status:" -ForegroundColor Cyan
        mysql -u $User -p$Password -e "SHOW STATUS LIKE 'Uptime';"
    } else {
        Write-Host "Failed to connect to MariaDB" -ForegroundColor Red
    }
} catch {
    Write-Host "Failed to connect to MariaDB: `$_" -ForegroundColor Red
}
"@ | Out-File -FilePath $mariaDBTestPath -Encoding utf8

Write-Log "Created MariaDB test script at: $mariaDBTestPath" "SUCCESS"

# Create MariaDB service control script
$mariaDBControlPath = Join-Path $PSScriptRoot "mariadb_service.bat"

@"
@echo off
REM MariaDB Service Control Script
setlocal

set MARIADB_SERVICE_NAME=MySQL

if "%1"=="" goto :help
if "%1"=="start" goto :start
if "%1"=="stop" goto :stop
if "%1"=="restart" goto :restart
if "%1"=="status" goto :status
goto :help

:start
echo Starting MariaDB service...
sc start %MARIADB_SERVICE_NAME%
if %ERRORLEVEL% EQU 0 (
    echo MariaDB service started successfully.
) else (
    echo Failed to start MariaDB service.
)
goto :eof

:stop
echo Stopping MariaDB service...
sc stop %MARIADB_SERVICE_NAME%
if %ERRORLEVEL% EQU 0 (
    echo MariaDB service stopped successfully.
) else (
    echo Failed to stop MariaDB service.
)
goto :eof

:restart
echo Restarting MariaDB service...
sc stop %MARIADB_SERVICE_NAME%
timeout /t 2 /nobreak > nul
sc start %MARIADB_SERVICE_NAME%
if %ERRORLEVEL% EQU 0 (
    echo MariaDB service restarted successfully.
) else (
    echo Failed to restart MariaDB service.
)
goto :eof

:status
echo Checking MariaDB service status...
sc query %MARIADB_SERVICE_NAME%
goto :eof

:help
echo MariaDB Service Control Script
echo Usage: mariadb_service.bat [command]
echo Commands:
echo   start   - Start the MariaDB service
echo   stop    - Stop the MariaDB service
echo   restart - Restart the MariaDB service
echo   status  - Check the MariaDB service status
goto :eof
"@ | Out-File -FilePath $mariaDBControlPath -Encoding ASCII

Write-Log "Created MariaDB service control script at: $mariaDBControlPath" "SUCCESS"

# Create MariaDB status page
$mariaDBStatusPath = Join-Path $PSScriptRoot "mariadb_status.php"

@"
<?php
// MariaDB Status Page
header('Content-Type: text/html');

// Database connection details
\$host = 'localhost';
\$port = $Port;
\$user = '$User';
\$password = '$Password';
\$database = '$DatabaseName';

// Function to check if MariaDB is running
function isMariaDBRunning() {
    \$output = [];
    \$returnVar = 0;
    exec('sc query MySQL', \$output, \$returnVar);
    
    foreach (\$output as \$line) {
        if (strpos(\$line, 'RUNNING') !== false) {
            return true;
        }
    }
    
    return false;
}

// Function to get MariaDB version
function getMariaDBVersion(\$conn) {
    \$version = 'Unknown';
    
    if (\$conn) {
        \$result = mysqli_query(\$conn, 'SELECT VERSION() AS version');
        if (\$result) {
            \$row = mysqli_fetch_assoc(\$result);
            \$version = \$row['version'];
            mysqli_free_result(\$result);
        }
    }
    
    return \$version;
}

// Function to get database size
function getDatabaseSize(\$conn, \$database) {
    \$size = 'Unknown';
    
    if (\$conn) {
        \$query = "SELECT 
                    table_schema AS 'Database',
                    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
                FROM information_schema.tables
                WHERE table_schema = '\$database'
                GROUP BY table_schema";
        
        \$result = mysqli_query(\$conn, \$query);
        if (\$result && mysqli_num_rows(\$result) > 0) {
            \$row = mysqli_fetch_assoc(\$result);
            \$size = \$row['Size (MB)'] . ' MB';
            mysqli_free_result(\$result);
        } else {
            \$size = '0 MB';
        }
    }
    
    return \$size;
}

// Function to get table count
function getTableCount(\$conn, \$database) {
    \$count = 0;
    
    if (\$conn) {
        \$query = "SELECT COUNT(*) AS table_count
                FROM information_schema.tables
                WHERE table_schema = '\$database'";
        
        \$result = mysqli_query(\$conn, \$query);
        if (\$result) {
            \$row = mysqli_fetch_assoc(\$result);
            \$count = \$row['table_count'];
            mysqli_free_result(\$result);
        }
    }
    
    return \$count;
}

// Check if MariaDB service is running
\$isRunning = isMariaDBRunning();

// Initialize connection variables
\$conn = null;
\$connectionError = '';
\$version = 'Unknown';
\$dbSize = 'Unknown';
\$tableCount = 0;

// Try to connect to MariaDB if it's running
if (\$isRunning) {
    try {
        \$conn = mysqli_connect(\$host, \$user, \$password, \$database, \$port);
        
        if (!\$conn) {
            \$connectionError = 'Failed to connect to MariaDB: ' . mysqli_connect_error();
        } else {
            \$version = getMariaDBVersion(\$conn);
            \$dbSize = getDatabaseSize(\$conn, \$database);
            \$tableCount = getTableCount(\$conn, \$database);
        }
    } catch (Exception \$e) {
        \$connectionError = 'Exception: ' . \$e->getMessage();
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MariaDB Status</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background-color: #fff;
            padding: 20px;
            border-radius: 5px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            border-bottom: 1px solid #eee;
            padding-bottom: 10px;
        }
        .status {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 3px;
            font-weight: bold;
        }
        .online {
            background-color: #d4edda;
            color: #155724;
        }
        .offline {
            background-color: #f8d7da;
            color: #721c24;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        table, th, td {
            border: 1px solid #ddd;
        }
        th, td {
            padding: 12px;
            text-align: left;
        }
        th {
            background-color: #f2f2f2;
        }
        .refresh {
            display: inline-block;
            margin-top: 20px;
            padding: 8px 16px;
            background-color: #007bff;
            color: white;
            text-decoration: none;
            border-radius: 4px;
        }
        .refresh:hover {
            background-color: #0069d9;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>MariaDB Server Status</h1>
        
        <p>
            Service Status: 
            <span class="status <?php echo \$isRunning ? 'online' : 'offline'; ?>">
                <?php echo \$isRunning ? 'Running' : 'Stopped'; ?>
            </span>
        </p>
        
        <?php if (\$isRunning): ?>
            <?php if (\$conn): ?>
                <p>
                    Connection Status: 
                    <span class="status online">Connected</span>
                </p>
                
                <h2>Server Information</h2>
                <table>
                    <tr>
                        <th>Property</th>
                        <th>Value</th>
                    </tr>
                    <tr>
                        <td>MariaDB Version</td>
                        <td><?php echo \$version; ?></td>
                    </tr>
                    <tr>
                        <td>Host</td>
                        <td><?php echo \$host; ?></td>
                    </tr>
                    <tr>
                        <td>Port</td>
                        <td><?php echo \$port; ?></td>
                    </tr>
                    <tr>
                        <td>Database</td>
                        <td><?php echo \$database; ?></td>
                    </tr>
                    <tr>
                        <td>Database Size</td>
                        <td><?php echo \$dbSize; ?></td>
                    </tr>
                    <tr>
                        <td>Table Count</td>
                        <td><?php echo \$tableCount; ?></td>
                    </tr>
                </table>
                
                <?php if (\$tableCount > 0): ?>
                    <h2>Tables in Database</h2>
                    <table>
                        <tr>
                            <th>Table Name</th>
                            <th>Rows</th>
                            <th>Size</th>
                        </tr>
                        <?php
                        \$tablesQuery = "SELECT 
                                            table_name,
                                            table_rows,
                                            ROUND((data_length + index_length) / 1024 / 1024, 2) AS size_mb
                                        FROM information_schema.tables
                                        WHERE table_schema = '\$database'
                                        ORDER BY table_name";
                        
                        \$tablesResult = mysqli_query(\$conn, \$tablesQuery);
                        
                        if (\$tablesResult) {
                            while (\$table = mysqli_fetch_assoc(\$tablesResult)) {
                                echo "<tr>";
                                echo "<td>" . \$table['table_name'] . "</td>";
                                echo "<td>" . \$table['table_rows'] . "</td>";
                                echo "<td>" . \$table['size_mb'] . " MB</td>";
                                echo "</tr>";
                            }
                            
                            mysqli_free_result(\$tablesResult);
                        }
                        ?>
                    </table>
                <?php endif; ?>
                
                <?php
                // Close the connection
                mysqli_close(\$conn);
                ?>
            <?php else: ?>
                <p>
                    Connection Status: 
                    <span class="status offline">Connection Failed</span>
                </p>
                <p><?php echo \$connectionError; ?></p>
            <?php endif; ?>
        <?php else: ?>
            <p>MariaDB service is not running. Please start the service to connect to the database.</p>
        <?php endif; ?>
        
        <a href="<?php echo \$_SERVER['PHP_SELF']; ?>" class="refresh">Refresh Status</a>
    </div>
</body>
</html>
"@ | Out-File -FilePath $mariaDBStatusPath -Encoding utf8

Write-Log "Created MariaDB status page at: $mariaDBStatusPath" "SUCCESS"

Write-Log "MariaDB installation and configuration completed successfully" "SUCCESS"
