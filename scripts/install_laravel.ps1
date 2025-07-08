# Laravel Installation Script
# This script creates a new Laravel project with Redis and MariaDB integration

param (
    [string]$ProjectName = "laravel-redis-mariadb",
    [string]$Version = "^12.0",
    [string]$CacheDriver = "redis",
    [string]$DatabaseDriver = "mysql",
    [string]$RedisClient = "predis",
    [bool]$CreateApi = $true,
    [string]$ProjectRoot = "c:\Users\Public\dev--path\v3--dev\poc--nix",
    [string]$DbName = "laravel_db",
    [string]$DbUser = "laravel_user",
    [string]$DbPassword = "laravel_password",
    [int]$RedisPort = 6379
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Log file
$logFile = Join-Path $PSScriptRoot "..\logs\laravel_install_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

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

Write-Log "Starting Laravel installation..."

# Check if project already exists
$projectPath = Join-Path $ProjectRoot $ProjectName
if (Test-Path $projectPath) {
    Write-Log "Laravel project already exists at: $projectPath" "WARNING"
    $overwrite = Read-Host "Do you want to overwrite the existing project? (y/n)"
    if ($overwrite -ne "y") {
        Write-Log "Installation cancelled by user" "WARNING"
        exit 0
    }
    
    # Backup existing project
    $backupPath = "$projectPath.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Write-Log "Backing up existing project to: $backupPath" "INFO"
    Move-Item -Path $projectPath -Destination $backupPath -Force
}

# Check if Composer is installed
try {
    $composerVersion = composer --version
    Write-Log "Composer is installed: $composerVersion" "SUCCESS"
} catch {
    Write-Log "Composer is not installed. Installing..." "INFO"
    
    try {
        # Download Composer installer
        $installerUrl = "https://getcomposer.org/installer"
        $installerPath = Join-Path $env:TEMP "composer-setup.php"
        
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
        
        # Install Composer
        php $installerPath --install-dir="$env:ProgramFiles\Composer" --filename=composer
        
        # Add Composer to PATH
        $env:Path += ";$env:ProgramFiles\Composer"
        [Environment]::SetEnvironmentVariable("Path", $env:Path, "Machine")
        
        Write-Log "Composer installed successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to install Composer: $_" "ERROR"
        exit 1
    }
}

# Create Laravel project
try {
    Write-Log "Creating Laravel project: $ProjectName" "INFO"
    
    # Create project directory if it doesn't exist
    if (-not (Test-Path $projectPath)) {
        New-Item -ItemType Directory -Path $projectPath -Force | Out-Null
    }
    
    # Navigate to project directory
    Set-Location $projectPath
    
    # Create Laravel project
    composer create-project laravel/laravel:$Version .
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to create Laravel project" "ERROR"
        exit 1
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
    $envContent = $envContent -replace "CACHE_DRIVER=.*", "CACHE_DRIVER=$CacheDriver"
    $envContent = $envContent -replace "DB_CONNECTION=.*", "DB_CONNECTION=$DatabaseDriver"
    $envContent = $envContent -replace "DB_HOST=.*", "DB_HOST=127.0.0.1"
    $envContent = $envContent -replace "DB_PORT=.*", "DB_PORT=3306"
    $envContent = $envContent -replace "DB_DATABASE=.*", "DB_DATABASE=$DbName"
    $envContent = $envContent -replace "DB_USERNAME=.*", "DB_USERNAME=$DbUser"
    $envContent = $envContent -replace "DB_PASSWORD=.*", "DB_PASSWORD=$DbPassword"
    
    # Add Redis configuration
    $envContent += @"

REDIS_CLIENT=$RedisClient
REDIS_HOST=127.0.0.1
REDIS_PASSWORD=null
REDIS_PORT=$RedisPort
"@
    
    # Write updated .env file
    $envContent | Set-Content $envPath
    
    Write-Log ".env file configured successfully" "SUCCESS"
    
    # Create API if enabled
    if ($CreateApi) {
        Write-Log "Setting up API..." "INFO"
        
        # Create Product model and migration
        php artisan make:model Product -m
        
        # Update migration file
        $migrationFiles = Get-ChildItem -Path (Join-Path $projectPath "database\migrations") -Filter "*_create_products_table.php"
        if ($migrationFiles.Count -gt 0) {
            $migrationPath = $migrationFiles[0].FullName
            
            $migrationContent = Get-Content $migrationPath
            $updatedMigration = $migrationContent -replace "Schema::create\('products', function \(Blueprint \$table\) {(\s+)\$table->id\(\);", "Schema::create('products', function (Blueprint \$table) {`$1`$table->id();`$1`$table->string('name');`$1`$table->text('description')->nullable();`$1`$table->decimal('price', 10, 2);`$1`$table->integer('stock')->default(0);`$1`$table->string('category')->nullable();"
            
            $updatedMigration | Set-Content $migrationPath
            Write-Log "Updated products migration file" "SUCCESS"
        }
        
        # Create API controller
        php artisan make:controller Api/ProductController --api
        
        # Update ProductController
        $controllerPath = Join-Path $projectPath "app\Http\Controllers\Api\ProductController.php"
        
        $controllerContent = @"
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Product;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Validator;

class ProductController extends Controller
{
    /**
     * Display a listing of the resource.
     */
    public function index()
    {
        // Get products with Redis caching (60 seconds)
        \$products = Cache::store('redis')->remember('products.all', 60, function () {
            return Product::all();
        });
        
        return response()->json([
            'success' => true,
            'data' => \$products
        ]);
    }

    /**
     * Store a newly created resource in storage.
     */
    public function store(Request \$request)
    {
        \$validator = Validator::make(\$request->all(), [
            'name' => 'required|string|max:255',
            'description' => 'nullable|string',
            'price' => 'required|numeric|min:0',
            'stock' => 'required|integer|min:0',
            'category' => 'nullable|string|max:100',
        ]);
        
        if (\$validator->fails()) {
            return response()->json([
                'success' => false,
                'errors' => \$validator->errors()
            ], 422);
        }
        
        \$product = Product::create(\$request->all());
        
        // Clear cache when a new product is added
        Cache::store('redis')->forget('products.all');
        
        return response()->json([
            'success' => true,
            'data' => \$product
        ], 201);
    }

    /**
     * Display the specified resource.
     */
    public function show(string \$id)
    {
        // Get product with Redis caching (60 seconds)
        \$product = Cache::store('redis')->remember("products.{\$id}", 60, function () use (\$id) {
            return Product::find(\$id);
        });
        
        if (!\$product) {
            return response()->json([
                'success' => false,
                'message' => 'Product not found'
            ], 404);
        }
        
        return response()->json([
            'success' => true,
            'data' => \$product
        ]);
    }

    /**
     * Update the specified resource in storage.
     */
    public function update(Request \$request, string \$id)
    {
        \$product = Product::find(\$id);
        
        if (!\$product) {
            return response()->json([
                'success' => false,
                'message' => 'Product not found'
            ], 404);
        }
        
        \$validator = Validator::make(\$request->all(), [
            'name' => 'string|max:255',
            'description' => 'nullable|string',
            'price' => 'numeric|min:0',
            'stock' => 'integer|min:0',
            'category' => 'nullable|string|max:100',
        ]);
        
        if (\$validator->fails()) {
            return response()->json([
                'success' => false,
                'errors' => \$validator->errors()
            ], 422);
        }
        
        \$product->update(\$request->all());
        
        // Clear cache when a product is updated
        Cache::store('redis')->forget("products.{\$id}");
        Cache::store('redis')->forget('products.all');
        
        return response()->json([
            'success' => true,
            'data' => \$product
        ]);
    }

    /**
     * Remove the specified resource from storage.
     */
    public function destroy(string \$id)
    {
        \$product = Product::find(\$id);
        
        if (!\$product) {
            return response()->json([
                'success' => false,
                'message' => 'Product not found'
            ], 404);
        }
        
        \$product->delete();
        
        // Clear cache when a product is deleted
        Cache::store('redis')->forget("products.{\$id}");
        Cache::store('redis')->forget('products.all');
        
        return response()->json([
            'success' => true,
            'message' => 'Product deleted successfully'
        ]);
    }
    
    /**
     * Clear the Redis cache for products.
     */
    public function clearCache()
    {
        Cache::store('redis')->flush();
        
        return response()->json([
            'success' => true,
            'message' => 'Product cache cleared successfully'
        ]);
    }
}
"@
        
        $controllerContent | Set-Content $controllerPath
        Write-Log "Created ProductController with Redis caching" "SUCCESS"
        
        # Update Product model
        $modelPath = Join-Path $projectPath "app\Models\Product.php"
        
        $modelContent = @"
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Product extends Model
{
    use HasFactory;
    
    /**
     * The attributes that are mass assignable.
     *
     * @var array<int, string>
     */
    protected \$fillable = [
        'name',
        'description',
        'price',
        'stock',
        'category',
    ];
}
"@
        
        $modelContent | Set-Content $modelPath
        Write-Log "Updated Product model" "SUCCESS"
        
        # Create routes file for API
        $apiRoutesPath = Join-Path $projectPath "routes\api.php"
        
        $apiRoutesContent = @"
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
Route::post('products/clear-cache', [ProductController::class, 'clearCache']);

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
"@
        
        $apiRoutesContent | Set-Content $apiRoutesPath
        Write-Log "Updated API routes" "SUCCESS"
        
        # Create database seeder
        $seederPath = Join-Path $projectPath "database\seeders\ProductSeeder.php"
        
        $seederContent = @"
<?php

namespace Database\Seeders;

use App\Models\Product;
use Illuminate\Database\Seeder;

class ProductSeeder extends Seeder
{
    /**
     * Run the database seeds.
     */
    public function run(): void
    {
        \$products = [
            [
                'name' => 'Laptop',
                'description' => 'High-performance laptop with 16GB RAM and 512GB SSD',
                'price' => 1299.99,
                'stock' => 10,
                'category' => 'Electronics'
            ],
            [
                'name' => 'Smartphone',
                'description' => 'Latest smartphone with 6.5-inch display and 128GB storage',
                'price' => 899.99,
                'stock' => 15,
                'category' => 'Electronics'
            ],
            [
                'name' => 'Headphones',
                'description' => 'Noise-cancelling wireless headphones',
                'price' => 199.99,
                'stock' => 20,
                'category' => 'Audio'
            ],
            [
                'name' => 'Coffee Maker',
                'description' => 'Programmable coffee maker with thermal carafe',
                'price' => 79.99,
                'stock' => 8,
                'category' => 'Appliances'
            ],
            [
                'name' => 'Desk Chair',
                'description' => 'Ergonomic desk chair with lumbar support',
                'price' => 249.99,
                'stock' => 5,
                'category' => 'Furniture'
            ]
        ];
        
        foreach (\$products as \$product) {
            Product::create(\$product);
        }
    }
}
"@
        
        # Create directory if it doesn't exist
        $seederDir = Join-Path $projectPath "database\seeders"
        if (-not (Test-Path $seederDir)) {
            New-Item -ItemType Directory -Path $seederDir -Force | Out-Null
        }
        
        $seederContent | Set-Content $seederPath
        Write-Log "Created ProductSeeder" "SUCCESS"
        
        # Update DatabaseSeeder
        $dbSeederPath = Join-Path $projectPath "database\seeders\DatabaseSeeder.php"
        
        $dbSeederContent = Get-Content $dbSeederPath
        $updatedDbSeeder = $dbSeederContent -replace "// \\\App\\\Models\\\User::factory\(10\)->create\(\);", "// \App\Models\User::factory(10)->create();`n        \$this->call(ProductSeeder::class);"
        
        $updatedDbSeeder | Set-Content $dbSeederPath
        Write-Log "Updated DatabaseSeeder" "SUCCESS"
        
        # Create Redis test controller
        $redisTestPath = Join-Path $projectPath "app\Http\Controllers\RedisTestController.php"
        
        $redisTestContent = @"
<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Redis;

class RedisTestController extends Controller
{
    public function index()
    {
        try {
            Redis::set('test_key', 'Hello from Redis!');
            \$value = Redis::get('test_key');
            
            \$info = Redis::info();
            \$ping = Redis::ping();
            
            return view('redis-test', [
                'status' => 'connected',
                'value' => \$value,
                'info' => \$info,
                'ping' => \$ping
            ]);
        } catch (\Exception \$e) {
            return view('redis-test', [
                'status' => 'disconnected',
                'error' => \$e->getMessage()
            ]);
        }
    }
}
"@
        
        # Create directory if it doesn't exist
        $controllerDir = Join-Path $projectPath "app\Http\Controllers"
        if (-not (Test-Path $controllerDir)) {
            New-Item -ItemType Directory -Path $controllerDir -Force | Out-Null
        }
        
        $redisTestContent | Set-Content $redisTestPath
        Write-Log "Created RedisTestController" "SUCCESS"
        
        # Create Redis test view
        $viewsDir = Join-Path $projectPath "resources\views"
        $redisViewPath = Join-Path $viewsDir "redis-test.blade.php"
        
        $redisViewContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Redis Test</title>
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
        .connected {
            background-color: #d4edda;
            color: #155724;
        }
        .disconnected {
            background-color: #f8d7da;
            color: #721c24;
        }
        pre {
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            overflow: auto;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Redis Connection Test</h1>
        
        <p>
            Status: 
            <span class="status {{ \$status === 'connected' ? 'connected' : 'disconnected' }}">
                {{ \$status === 'connected' ? 'Connected' : 'Disconnected' }}
            </span>
        </p>
        
        @if (\$status === 'connected')
            <h2>Test Value</h2>
            <p>{{ \$value }}</p>
            
            <h2>Ping Response</h2>
            <p>{{ \$ping }}</p>
            
            <h2>Redis Info</h2>
            <pre>{{ print_r(\$info, true) }}</pre>
        @else
            <h2>Error</h2>
            <p>{{ \$error }}</p>
        @endif
    </div>
</body>
</html>
"@
        
        $redisViewContent | Set-Content $redisViewPath
        Write-Log "Created Redis test view" "SUCCESS"
        
        # Update web routes
        $webRoutesPath = Join-Path $projectPath "routes\web.php"
        
        $webRoutesContent = Get-Content $webRoutesPath
        $updatedWebRoutes = $webRoutesContent + @"

// Redis Test Route
Route::get('/redis-test', [App\Http\Controllers\RedisTestController::class, 'index']);
"@
        
        $updatedWebRoutes | Set-Content $webRoutesPath
        Write-Log "Updated web routes" "SUCCESS"
        
        Write-Log "API setup completed successfully" "SUCCESS"
    }
    
    # Create Laravel start script
    $laravelStartPath = Join-Path $PSScriptRoot "start_laravel.bat"
    
    @"
@echo off
REM Laravel Start Script
echo Starting Laravel development server...

cd $projectPath
php artisan serve

echo Laravel server stopped.
"@ | Out-File -FilePath $laravelStartPath -Encoding ASCII
    
    Write-Log "Created Laravel start script at: $laravelStartPath" "SUCCESS"
    
    # Create Laravel migration script
    $laravelMigratePath = Join-Path $PSScriptRoot "migrate_laravel.bat"
    
    @"
@echo off
REM Laravel Migration Script
echo Running Laravel migrations and seeders...

cd $projectPath
php artisan migrate:fresh --seed

echo Migrations and seeders completed.
"@ | Out-File -FilePath $laravelMigratePath -Encoding ASCII
    
    Write-Log "Created Laravel migration script at: $laravelMigratePath" "SUCCESS"
    
    # Create Postman collection for API testing
    $postmanDir = Join-Path $PSScriptRoot "postman"
    if (-not (Test-Path $postmanDir)) {
        New-Item -ItemType Directory -Path $postmanDir -Force | Out-Null
    }
    
    $postmanPath = Join-Path $postmanDir "Laravel_Redis_API.postman_collection.json"
    
    $postmanContent = @"
{
	"info": {
		"_postman_id": "$(New-Guid)",
		"name": "Laravel Redis API",
		"description": "API endpoints for Laravel with Redis caching",
		"schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
	},
	"item": [
		{
			"name": "Get All Products",
			"request": {
				"method": "GET",
				"header": [],
				"url": {
					"raw": "http://localhost:8000/api/products",
					"protocol": "http",
					"host": [
						"localhost"
					],
					"port": "8000",
					"path": [
						"api",
						"products"
					]
				},
				"description": "Get all products with Redis caching"
			},
			"response": []
		},
		{
			"name": "Get Product by ID",
			"request": {
				"method": "GET",
				"header": [],
				"url": {
					"raw": "http://localhost:8000/api/products/1",
					"protocol": "http",
					"host": [
						"localhost"
					],
					"port": "8000",
					"path": [
						"api",
						"products",
						"1"
					]
				},
				"description": "Get a specific product by ID with Redis caching"
			},
			"response": []
		},
		{
			"name": "Create Product",
			"request": {
				"method": "POST",
				"header": [
					{
						"key": "Content-Type",
						"value": "application/json",
						"type": "text"
					},
					{
						"key": "Accept",
						"value": "application/json",
						"type": "text"
					}
				],
				"body": {
					"mode": "raw",
					"raw": "{\n    \"name\": \"New Product\",\n    \"description\": \"This is a new product\",\n    \"price\": 99.99,\n    \"stock\": 50,\n    \"category\": \"New Category\"\n}"
				},
				"url": {
					"raw": "http://localhost:8000/api/products",
					"protocol": "http",
					"host": [
						"localhost"
					],
					"port": "8000",
					"path": [
						"api",
						"products"
					]
				},
				"description": "Create a new product"
			},
			"response": []
		},
		{
			"name": "Update Product",
			"request": {
				"method": "PUT",
				"header": [
					{
						"key": "Content-Type",
						"value": "application/json",
						"type": "text"
					},
					{
						"key": "Accept",
						"value": "application/json",
						"type": "text"
					}
				],
				"body": {
					"mode": "raw",
					"raw": "{\n    \"name\": \"Updated Product\",\n    \"price\": 129.99,\n    \"stock\": 25\n}"
				},
				"url": {
					"raw": "http://localhost:8000/api/products/1",
					"protocol": "http",
					"host": [
						"localhost"
					],
					"port": "8000",
					"path": [
						"api",
						"products",
						"1"
					]
				},
				"description": "Update an existing product"
			},
			"response": []
		},
		{
			"name": "Delete Product",
			"request": {
				"method": "DELETE",
				"header": [
					{
						"key": "Accept",
						"value": "application/json",
						"type": "text"
					}
				],
				"url": {
					"raw": "http://localhost:8000/api/products/1",
					"protocol": "http",
					"host": [
						"localhost"
					],
					"port": "8000",
					"path": [
						"api",
						"products",
						"1"
					]
				},
				"description": "Delete a product"
			},
			"response": []
		},
		{
			"name": "Clear Cache",
			"request": {
				"method": "POST",
				"header": [
					{
						"key": "Accept",
						"value": "application/json",
						"type": "text"
					}
				],
				"url": {
					"raw": "http://localhost:8000/api/products/clear-cache",
					"protocol": "http",
					"host": [
						"localhost"
					],
					"port": "8000",
					"path": [
						"api",
						"products",
						"clear-cache"
					]
				},
				"description": "Clear the Redis cache for products"
			},
			"response": []
		},
		{
			"name": "Redis Status",
			"request": {
				"method": "GET",
				"header": [
					{
						"key": "Accept",
						"value": "application/json",
						"type": "text"
					}
				],
				"url": {
					"raw": "http://localhost:8000/api/redis-status",
					"protocol": "http",
					"host": [
						"localhost"
					],
					"port": "8000",
					"path": [
						"api",
						"redis-status"
					]
				},
				"description": "Check Redis connection status"
			},
			"response": []
		}
	]
}
"@
    
    $postmanContent | Set-Content $postmanPath
    Write-Log "Created Postman collection for API testing" "SUCCESS"
} catch {
    Write-Log "Failed to set up Laravel: $_" "ERROR"
    exit 1
}

Write-Log "Laravel installation and configuration completed successfully" "SUCCESS"
