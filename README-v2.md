# Windows Development Environment Setup

A comprehensive, unified development environment setup for PHP-based web development on Windows, including PHP, Redis, MariaDB, and Laravel - all without requiring WSL or virtualization.

## 🚀 Features

- **PHP 8.3** with essential extensions (redis, mbstring, xml, curl, mysql)
- **Redis** in-memory data store (optional)
- **MariaDB** database server (optional)
- **Laravel** PHP framework (optional)
- **PowerShell-based** setup and management
- **Session management** scripts for both CMD and PowerShell

## 📋 Prerequisites

- Windows 10/11
- PowerShell 5.1 or later
- Administrator privileges (required for some operations)
- Internet connection (for downloading components)

## 🛠️ Installation

1. **Clone the repository** or extract the project files to your desired location
2. **Run the setup script** in PowerShell:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   .\setup.ps1
   ```
3. **Follow the on-screen prompts** to select which components to install
4. **Review the logs** in the `logs/` directory if needed

## 🔧 Configuration

Edit `config.json` to customize the installation:

```json
{
  "components": {
    "php": {
      "enabled": true,
      "version": "8.3",
      "extensions": ["redis", "mbstring", "xml", "curl", "mysql"]
    },
    "redis": {
      "enabled": false,
      "port": 6379
    },
    "mariadb": {
      "enabled": false,
      "port": 3306,
      "root_password": "",
      "database": "laravel",
      "username": "laravel",
      "password": ""
    },
    "laravel": {
      "enabled": false,
      "project_path": "C:\\path\\to\\laravel"
    }
  }
}
```

## 🚦 Usage

### PHP Environment

#### PowerShell:
```powershell
.\scripts\use_php.ps1
```

#### Command Prompt:
```batch
scripts\use_php.bat
```

### Database Management

#### Redis
- Start: `redis-server`
- Test: `scripts\test_redis.ps1`

#### MariaDB
- Start: `net start mariadb`
- Test: `scripts\test_mariadb.ps1`

### Laravel Development

1. Navigate to your Laravel project directory
2. Start the development server:
   ```bash
   php artisan serve
   ```
3. Access the application at `http://localhost:8000`

## 🌐 API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/products` | GET | List all products |
| `/api/products/{id}` | GET | Get specific product |
| `/api/products` | POST | Create new product |
| `/api/products/{id}` | PUT/PATCH | Update product |
| `/api/products/{id}` | DELETE | Delete product |
| `/api/redis-status` | GET | Check Redis connection |

## 🔍 Troubleshooting

1. **PHP not recognized**
   - Ensure you've run the appropriate `use_php` script for your shell
   - Verify PHP is in your system PATH

2. **Port conflicts**
   - Check if another service is using the required ports (80, 8000, 3306, 6379)
   - Update the ports in `config.json` if needed

3. **Installation issues**
   - Check the latest logs in the `logs/` directory
   - Ensure you have sufficient permissions

## 📜 License

This project is open-source and available under the MIT License.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 Changelog

### v2.0.0
- Complete rewrite of the setup script
- Added support for PHP 8.3
- Improved error handling and logging
- Added configuration via JSON
- Better PowerShell integration
- Session management scripts for both CMD and PowerShell

---

💡 **Tip**: For the best experience, use Windows Terminal with PowerShell 7+ and run as Administrator when needed.
