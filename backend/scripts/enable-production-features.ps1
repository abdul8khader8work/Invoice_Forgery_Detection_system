# Enable Production Features Script
# Safe, auditable pathway to enable Phase 4 production features
# Context: D:\Projects\invoice_forgery_system\backend

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("jwt_auth", "async_scan", "db_v2", "security_hardening", "all")]
    [string]$Feature = "all",
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun,
    
    [Parameter(Mandatory=$false)]
    [switch]$Rollback
)

# Configuration
$ProjectRoot = "D:\Projects\invoice_forgery_system"
$BackendDir = "$ProjectRoot\backend"
$EnvFile = "$BackendDir\.env"
$LogFile = "$BackendDir\logs\feature-activation.log"
$BackupDir = "$BackendDir\logs\backups"

# Ensure logs directory exists
if (-not (Test-Path "$BackendDir\logs")) {
    New-Item -ItemType Directory -Path "$BackendDir\logs" -Force | Out-Null
}
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

# Logging function
function Log-Message {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Host $LogEntry
    Add-Content -Path $LogFile -Value $LogEntry
}

# Pre-flight check: JWT Auth
function Test-JWTAuthReadiness {
    Log-Message "Running pre-flight checks for ENABLE_JWT_AUTH..."
    
    $ChecksPassed = @()
    $ChecksFailed = @()
    
    # Check 1: JWT_SECRET length and strength
    $JWTSecret = $env:JWT_SECRET
    if (-not $JWTSecret) {
        $JWTSecret = (Get-Content $EnvFile | Select-String "JWT_SECRET").ToString().Split("=")[1].Trim()
    }
    
    if ($JWTSecret -and $JWTSecret.Length -ge 32) {
        $ChecksPassed += "JWT_SECRET is strong (length: $($JWTSecret.Length))"
    } else {
        $ChecksFailed += "JWT_SECRET not set or too weak (minimum 32 characters required)"
    }
    
    # Check 2: PostgreSQL users table exists
    try {
        $DBUrl = $env:DATABASE_URL
        if (-not $DBUrl) {
            $DBUrl = (Get-Content $EnvFile | Select-String "DATABASE_URL").ToString().Split("=")[1].Trim()
        }
        
        if ($DBUrl -match "postgresql") {
            # TODO: Add actual database connection check
            $ChecksPassed += "PostgreSQL DATABASE_URL is configured"
        } else {
            $ChecksFailed += "DATABASE_URL must be PostgreSQL for JWT auth (currently: $DBUrl)"
        }
    } catch {
        $ChecksFailed += "Failed to check DATABASE_URL: $_"
    }
    
    # Check 3: JWT dependencies installed
    try {
        $Result = & "$BackendDir\venv\Scripts\python.exe" -c "import jwt; import passlib" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $ChecksPassed += "JWT dependencies (python-jose, passlib) installed"
        } else {
            $ChecksFailed += "JWT dependencies not installed"
        }
    } catch {
        $ChecksFailed += "Failed to check JWT dependencies: $_"
    }
    
    # Check 4: JWT auth middleware exists
    if (Test-Path "$BackendDir\middleware\jwt_auth.py") {
        $ChecksPassed += "JWT auth middleware file exists"
    } else {
        $ChecksFailed += "JWT auth middleware file missing"
    }
    
    Log-Message "JWT Auth Pre-flight Checks:"
    foreach ($Check in $ChecksPassed) {
        Log-Message "  ✅ $Check" "INFO"
    }
    foreach ($Check in $ChecksFailed) {
        Log-Message "  ❌ $Check" "ERROR"
    }
    
    return @{
        Passed = $ChecksPassed.Count -gt 0 -and $ChecksFailed.Count -eq 0
        PassedChecks = $ChecksPassed
        FailedChecks = $ChecksFailed
    }
}

# Pre-flight check: Async Scan
function Test-AsyncScanReadiness {
    Log-Message "Running pre-flight checks for ENABLE_ASYNC_SCAN..."
    
    $ChecksPassed = @()
    $ChecksFailed = @()
    
    # Check 1: SSE manager exists
    if (Test-Path "$BackendDir\tasks\sse_manager.py") {
        $ChecksPassed += "SSE manager file exists"
    } else {
        $ChecksFailed += "SSE manager file missing"
    }
    
    # Check 2: Async scan tasks exist
    if (Test-Path "$BackendDir\tasks\scan_tasks.py") {
        $ChecksPassed += "Async scan tasks file exists"
    } else {
        $ChecksFailed += "Async scan tasks file missing"
    }
    
    # Check 3: Redis connection (optional, can use BackgroundTasks)
    $RedisUrl = $env:REDIS_URL
    if ($RedisUrl) {
        # TODO: Add actual Redis connection check
        $ChecksPassed += "Redis URL configured (will use Celery + Redis)"
    } else {
        $ChecksPassed += "Redis not configured (will use BackgroundTasks fallback)"
    }
    
    Log-Message "Async Scan Pre-flight Checks:"
    foreach ($Check in $ChecksPassed) {
        Log-Message "  ✅ $Check" "INFO"
    }
    foreach ($Check in $ChecksFailed) {
        Log-Message "  ❌ $Check" "ERROR"
    }
    
    return @{
        Passed = $ChecksPassed.Count -gt 0 -and $ChecksFailed.Count -eq 0
        PassedChecks = $ChecksPassed
        FailedChecks = $ChecksFailed
    }
}

# Pre-flight check: DB V2 (PostgreSQL)
function Test-DBV2Readiness {
    Log-Message "Running pre-flight checks for ENABLE_DB_V2..."
    
    $ChecksPassed = @()
    $ChecksFailed = @()
    
    # Check 1: PostgreSQL connection
    $DBUrl = $env:DATABASE_URL
    if (-not $DBUrl) {
        $DBUrl = (Get-Content $EnvFile | Select-String "DATABASE_URL").ToString().Split("=")[1].Trim()
    }
    
    if ($DBUrl -match "postgresql") {
        $ChecksPassed += "PostgreSQL DATABASE_URL configured"
        
        # TODO: Add actual connection test
        # try {
        #     $Result = & "$BackendDir\venv\Scripts\python.exe" -c "import psycopg2; conn = psycopg2.connect('$DBUrl'); conn.close()"
        #     if ($LASTEXITCODE -eq 0) {
        #         $ChecksPassed += "PostgreSQL connection successful"
        #     }
        # } catch {
        #     $ChecksFailed += "PostgreSQL connection failed: $_"
        # }
    } else {
        $ChecksFailed += "DATABASE_URL must be PostgreSQL (currently: $DBUrl)"
    }
    
    # Check 2: Migration script exists
    if (Test-Path "$BackendDir\db\migrations\migrate_sqlite_to_postgres.py") {
        $ChecksPassed += "Migration script exists"
    } else {
        $ChecksFailed += "Migration script missing"
    }
    
    # Check 3: PostgreSQL migration SQL exists
    if (Test-Path "$BackendDir\db\migrations\001_init_postgres.sql") {
        $ChecksPassed += "PostgreSQL migration SQL exists"
    } else {
        $ChecksFailed += "PostgreSQL migration SQL missing"
    }
    
    # Check 4: SQLite database exists (for migration)
    if (Test-Path "$BackendDir\invoice_dev.db") {
        $ChecksPassed += "SQLite database exists (source for migration)"
    } else {
        $ChecksFailed += "SQLite database not found (cannot migrate)"
    }
    
    Log-Message "DB V2 Pre-flight Checks:"
    foreach ($Check in $ChecksPassed) {
        Log-Message "  ✅ $Check" "INFO"
    }
    foreach ($Check in $ChecksFailed) {
        Log-Message "  ❌ $Check" "ERROR"
    }
    
    return @{
        Passed = $ChecksPassed.Count -gt 0 -and $ChecksFailed.Count -eq 0
        PassedChecks = $ChecksPassed
        FailedChecks = $ChecksFailed
    }
}

# Pre-flight check: Security Hardening
function Test-SecurityHardeningReadiness {
    Log-Message "Running pre-flight checks for ENABLE_SECURITY_HARDENING..."
    
    $ChecksPassed = @()
    $ChecksFailed = @()
    
    # Check 1: Security headers middleware exists
    if (Test-Path "$BackendDir\middleware\security_headers.py") {
        $ChecksPassed += "Security headers middleware exists"
    } else {
        $ChecksFailed += "Security headers middleware missing"
    }
    
    # Check 2: Rate limiter middleware exists
    if (Test-Path "$BackendDir\middleware\rate_limiter.py") {
        $ChecksPassed += "Rate limiter middleware exists"
    } else {
        $ChecksFailed += "Rate limiter middleware missing"
    }
    
    # Check 3: File validation middleware exists
    if (Test-Path "$BackendDir\middleware\file_validation.py") {
        $ChecksPassed += "File validation middleware exists"
    } else {
        $ChecksFailed += "File validation middleware missing"
    }
    
    # Check 4: CORS configuration
    $CORSOrigins = $env:CORS_ORIGINS
    if ($CORSOrigins -and $CORSOrigins -ne "*") {
        $ChecksPassed += "CORS origins configured (not wildcard)"
    } else {
        $ChecksFailed += "CORS origins not configured or set to wildcard (security risk)"
    }
    
    # Check 5: Rate limit configuration
    $RateLimit = $env:RATE_LIMIT_REQUESTS_PER_MINUTE
    if ($RateLimit -and [int]$RateLimit -gt 0) {
        $ChecksPassed += "Rate limit configured ($RateLimit req/min)"
    } else {
        $ChecksFailed += "Rate limit not configured"
    }
    
    Log-Message "Security Hardening Pre-flight Checks:"
    foreach ($Check in $ChecksPassed) {
        Log-Message "  ✅ $Check" "INFO"
    }
    foreach ($Check in $ChecksFailed) {
        Log-Message "  ❌ $Check" "ERROR"
    }
    
    return @{
        Passed = $ChecksPassed.Count -gt 0 -and $ChecksFailed.Count -eq 0
        PassedChecks = $ChecksPassed
        FailedChecks = $ChecksFailed
    }
}

# Enable feature flag in .env
function Enable-FeatureFlag {
    param(
        [string]$FlagName,
        [string]$Value = "true"
    )
    
    $EnvContent = Get-Content $EnvFile
    $FlagLine = "$FlagName=$Value"
    $FlagFound = $false
    
    $NewContent = @()
    foreach ($Line in $EnvContent) {
        if ($Line.StartsWith("$FlagName=")) {
            $NewContent += $FlagLine
            $FlagFound = $true
        } else {
            $NewContent += $Line
        }
    }
    
    if (-not $FlagFound) {
        $NewContent += $FlagLine
    }
    
    # Backup current .env
    $BackupFile = "$BackupDir\.env.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $EnvFile $BackupFile
    Log-Message "Backed up .env to $BackupFile"
    
    # Write new content
    Set-Content -Path $EnvFile -Value $NewContent
    Log-Message "Updated $FlagName=$Value in .env"
    
    return $BackupFile
}

# Rollback function
function Rollback-FeatureFlag {
    param(
        [string]$FlagName,
        [string]$BackupFile
    )
    
    if ($BackupFile -and (Test-Path $BackupFile)) {
        Copy-Item $BackupFile $EnvFile
        Log-Message "Rolled back .env from $BackupFile" "INFO"
    } else {
        # Manual rollback
        $EnvContent = Get-Content $EnvFile
        $NewContent = @()
        foreach ($Line in $EnvContent) {
            if (-not $Line.StartsWith("$FlagName=")) {
                $NewContent += $Line
            }
        }
        $NewContent += "$FlagName=false"
        Set-Content -Path $EnvFile -Value $NewContent
        Log-Message "Manually rolled back $FlagName to false" "INFO"
    }
}

# Main execution
Log-Message "=========================================="
Log-Message "Production Feature Enablement Script"
Log-Message "=========================================="

if ($Rollback) {
    Log-Message "ROLLBACK MODE: Disabling all production features"
    Enable-FeatureFlag -FlagName "ENABLE_JWT_AUTH" -Value "false"
    Enable-FeatureFlag -FlagName "ENABLE_ASYNC_SCAN" -Value "false"
    Enable-FeatureFlag -FlagName "ENABLE_DB_V2" -Value "false"
    Enable-FeatureFlag -FlagName "ENABLE_SECURITY_HARDENING" -Value "false"
    Log-Message "All production features disabled. Restart backend to apply."
    exit 0
}

$FeaturesToEnable = @()
if ($Feature -eq "all") {
    $FeaturesToEnable = @("jwt_auth", "async_scan", "db_v2", "security_hardening")
} else {
    $FeaturesToEnable = @($Feature)
}

foreach ($FeatureName in $FeaturesToEnable) {
    Log-Message ""
    Log-Message "--- Processing: $FeatureName ---"
    
    $Result = $null
    $FlagName = ""
    
    switch ($FeatureName) {
        "jwt_auth" {
            $Result = Test-JWTAuthReadiness
            $FlagName = "ENABLE_JWT_AUTH"
        }
        "async_scan" {
            $Result = Test-AsyncScanReadiness
            $FlagName = "ENABLE_ASYNC_SCAN"
        }
        "db_v2" {
            $Result = Test-DBV2Readiness
            $FlagName = "ENABLE_DB_V2"
        }
        "security_hardening" {
            $Result = Test-SecurityHardeningReadiness
            $FlagName = "ENABLE_SECURITY_HARDENING"
        }
    }
    
    if ($Result.Passed) {
        Log-Message "✅ Pre-flight checks passed for $FlagName"
        
        if (-not $DryRun) {
            $Response = Read-Host "Enable $FlagName? (y/N)"
            if ($Response -eq "y" -or $Response -eq "Y") {
                $BackupFile = Enable-FeatureFlag -FlagName $FlagName -Value "true"
                Log-Message "✅ $FlagName enabled"
                Log-Message "Rollback command: Rollback-FeatureFlag -FlagName $FlagName -BackupFile $BackupFile"
                Log-Message "Or set $FlagName=false in .env and restart backend"
            } else {
                Log-Message "Skipped $FlagName"
            }
        } else {
            Log-Message "[DRY RUN] Would enable $FlagName"
        }
    } else {
        Log-Message "❌ Pre-flight checks failed for $FlagName. Cannot enable."
        Log-Message "Failed checks:" "ERROR"
        foreach ($Check in $Result.FailedChecks) {
            Log-Message "  - $Check" "ERROR"
        }
    }
}

Log-Message ""
Log-Message "=========================================="
Log-Message "Feature enablement process complete"
Log-Message "Log file: $LogFile"
Log-Message "Restart backend to apply changes:"
Log-Message "  cd $BackendDir"
Log-Message "  .\venv\Scripts\Activate.ps1"
Log-Message "  python main.py"
Log-Message "=========================================="
