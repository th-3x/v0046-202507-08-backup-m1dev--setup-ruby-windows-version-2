# Windows Development Environment

This is a unified setup for PHP, Redis, MariaDB, and Laravel on Windows without using WSL or virtualization.

## Components Installed

| Component | Status | Version | Notes |
|-----------|--------|---------|-------|
| PHP | ✅ Installed | 8.3 | Extensions: redis, mbstring, xml, curl, mysql |
| Redis | ⚪ Disabled | - | Not installed |
| MariaDB | ⚪ Disabled | - | Not installed |
| Laravel | ⚪ Disabled | - | Not installed |

## Getting Started

### Scripts

The following scripts are available in the \scripts\ directory:

| Script | Description |
|--------|-------------|
| use_php.bat | Switch to PHP for the current terminal session (cmd) |
| use_php.ps1 | Switch to PHP for the current PowerShell session |
| test_redis.ps1 | Test Redis connection |
| test_mariadb.ps1 | Test MariaDB connection |
| start_laravel.bat | Start Laravel development server |

### Laravel Project

The Laravel project is located at: \$(@{components=; paths=}.paths.project_root)\\

To start the Laravel development server:
\\\
cd c:\Users\Public\dev--path\v3--dev\poc--nix\
php artisan serve
\\\

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

The setup is configured using \config.json\. You can modify this file to change the setup options.

## Troubleshooting

Check the log files in the \logs\ directory for detailed information about the setup process.

## License

This project is open-source and available under the MIT License.
