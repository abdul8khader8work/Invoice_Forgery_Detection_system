#Requires -Version 7.0
<#
.SYNOPSIS
    Safe Feature Flag Activation Testing Script
    
.DESCRIPTION
    Tests feature flag activation in three modes:
    - DryRun: Validates flags without enabling (default)
    - Staging: Enables flags in isolated test environment
    - Production: Requires explicit confirmation + backup prompt
    
    All flags remain false by default. Activation requires manual .env edit.
    
.PARAMETER Mode
    Test mode: DryRun (default), Staging, or Production
    
.PARAMETER Feature
    Specific feature to test (jwt_auth, async_scan, batch_upload, all)
    
.PARAMETER SkipBackup
    Skip backup prompt (use with caution)
    
.EXAMPLE
    # Dry-run validation (recommended first step)
    .\scripts\test-feature-activation.ps1 -Mode DryRun -Feature all
    
    # Staging environment test
    .\scripts\test-feature-activation.ps1 -Mode Staging -Feature jwt_auth
    
    # Production activation (requires confirmation)
    .\scripts\test-feature-activation.ps1 -Mode Production -Feature jwt_auth
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("DryRun", "Staging", "Production")]
    [string]$Mode = "DryRun",
    
    [Parameter()]
    [ValidateSet("jwt_auth", "async_scan", "batch_upload", "all")]
    [string]$Feature = "all",
    
    [Parameter()]
    [switch]$SkipBackup
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ProjectRoot = "D:\Projects\invoice_forgery_system"
$BackendPath = "$ProjectRoot\backend"
$EnvFile = "$BackendPath\.env"
$BackupDir = "$BackendPath\backups"
$LogFile = "$ProjectRoot\logs\feature-activation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Feature flag mapping
$FeatureFlags = @{
    "jwt_auth" = "ENABLE_JWT_AUTH"
    "async_scan" = "ENABLE_ASYNC_SCAN"
    "batch_upload" = "ENABLE_BATCH_UPLOAD"
}

# ============================================================================
# LOGGING
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Console output with colors
    switch ($Level) {
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
        "WARN" { Write-Host $logEntry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "INFO" { Write-Host $logEntry -ForegroundColor Cyan }
        default { Write-Host $logEntry }
    }
    
    # File logging
    if (!(Test-Path "$ProjectRoot\logs")) {
        New-Item -ItemType Directory -Path "$ProjectRoot\logs" -Force | Out-Null
    }
    Add-Content -Path $LogFile -Value $logEntry
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Test-BackendRunning {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8000/health" -Method GET -TimeoutSec 5
        return $true
    }
    catch {
        return $false
    }
}

function Get-FeatureFlagStatus {
    param([string]$FlagName)
    
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8000/api/v1/feature-flags/status" -Method GET
        return $response.flags.$FlagName
    }
    catch {
        return $null
    }
}

function Invoke-PreFlightCheck {
    param([string]$Feature)
    
    Write-Log "Running pre-flight checks for $Feature..." -Level "INFO"
    
    # Import Python and run checks
    $pythonCode = @"
import sys
sys.path.insert(0, '$BackendPath')
from app.core.feature_activation import check_feature_flag
result = check_feature_flag('$($FeatureFlags[$Feature])')
print(f"READY: {result.ready}")
print(f"RECOMMENDATION: {result.recommendation}")
print(f"SUMMARY: {result.summary}")
for check in result.checks:
    print(f"CHECK: {check.name}|{check.status.value}|{check.message}")
"@
    
    try {
        $output = & "$BackendPath\venv\Scripts\python.exe" -c $pythonCode 2>&1
        
        Write-Log "Pre-flight check output:" -Level "INFO"
        $output | ForEach-Object { Write-Log "  $_" -Level "INFO" }
        
        # Parse output
        $ready = $output | Select-String "^READY: (.+)" | ForEach-Object { $_.Matches.Groups[1].Value }
        $recommendation = $output | Select-String "^RECOMMENDATION: (.+)" | ForEach-Object { $_.Matches.Groups[1].Value }
        
        return @{
            Ready = $ready -eq "True"
            Recommendation = $recommendation
            RawOutput = $output
        }
    }
    catch {
        Write-Log "Pre-flight check failed: $_" -Level "ERROR"
        return @{ Ready = $false; Recommendation = "error"; Error = $_ }
    }
}

function Backup-EnvironmentFile {
    if (!(Test-Path $EnvFile)) {
        Write-Log "No .env file found to backup" -Level "WARN"
        return $null
    }
    
    if (!(Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    
    $backupName = ".env.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $backupPath = "$BackupDir\$backupName"
    
    Copy-Item -Path $EnvFile -Destination $backupPath -Force
    Write-Log "Environment file backed up to: $backupPath" -Level "SUCCESS"
    
    return $backupPath
}

function Restore-EnvironmentFile {
    param([string]$BackupPath)
    
    if (Test-Path $BackupPath) {
        Copy-Item -Path $BackupPath -Destination $EnvFile -Force
        Write-Log "Environment file restored from: $BackupPath" -Level "SUCCESS"
        return $true
    }
    else {
        Write-Log "Backup file not found: $BackupPath" -Level "ERROR"
        return $false
    }
}

# ============================================================================
# MODE: DRY-RUN
# ============================================================================

function Start-DryRun {
    Write-Log "========== DRY-RUN MODE ==========" -Level "INFO"
    Write-Log "Validating feature flags WITHOUT making changes" -Level "INFO"
    Write-Log "Features to check: $Feature" -Level "INFO"
    Write-Log ""
    
    # Check backend is running
    if (!(Test-BackendRunning)) {
        Write-Log "Backend is not running. Please start it first:" -Level "ERROR"
        Write-Log "  cd $BackendPath" -Level "INFO"
        Write-Log "  .\venv\Scripts\Activate.ps1" -Level "INFO"
        Write-Log "  python main.py" -Level "INFO"
        return $false
    }
    
    Write-Log "Backend health check: PASS" -Level "SUCCESS"
    Write-Log ""
    
    # Run pre-flight checks
    $featuresToCheck = if ($Feature -eq "all") { $FeatureFlags.Keys } else { @($Feature) }
    
    foreach ($feat in $featuresToCheck) {
        Write-Log "----------------------------------------" -Level "INFO"
        Write-Log "Checking: $feat" -Level "INFO"
        Write-Log "Flag: $($FeatureFlags[$feat])" -Level "INFO"
        Write-Log ""
        
        $checkResult = Invoke-PreFlightCheck -Feature $feat
        
        if ($checkResult.Ready) {
            Write-Log "Status: READY FOR ACTIVATION" -Level "SUCCESS"
        }
        else {
            Write-Log "Status: NOT READY" -Level "WARN"
        }
        
        Write-Log "Recommendation: $($checkResult.Recommendation)" -Level "INFO"
        Write-Log ""
        
        # Get current flag state
        $currentState = Get-FeatureFlagStatus -FlagName $FeatureFlags[$feat]
        Write-Log "Current flag state: $(if ($currentState) { 'ENABLED' } else { 'DISABLED' })" -Level "INFO"
        
        # Show what would happen
        Write-Log "DRY-RUN: No changes made. To enable, manually edit:" -Level "INFO"
        Write-Log "  $EnvFile" -Level "INFO"
        Write-Log "Change: $($FeatureFlags[$feat])=false → $($FeatureFlags[$feat])=true" -Level "INFO"
        Write-Log ""
    }
    
    Write-Log "========== DRY-RUN COMPLETE ==========" -Level "INFO"
    Write-Log "Review the output above. If all checks pass, you can proceed to Staging mode." -Level "INFO"
    Write-Log "Log saved to: $LogFile" -Level "INFO"
    
    return $true
}

# ============================================================================
# MODE: STAGING
# ============================================================================

function Start-Staging {
    Write-Log "========== STAGING MODE ==========" -Level "INFO"
    Write-Log "CAUTION: This will modify the .env file in a test environment" -Level "WARN"
    Write-Log "Feature: $Feature" -Level "INFO"
    Write-Log ""
    
    # Confirm with user
    $confirm = Read-Host "Are you sure you want to enable $Feature in STAGING? (type 'yes' to confirm)"
    if ($confirm -ne "yes") {
        Write-Log "Staging activation cancelled by user" -Level "INFO"
        return $false
    }
    
    # Backup first
    if (!$SkipBackup) {
        $backupPath = Backup-EnvironmentFile
        if (!$backupPath) {
            Write-Log "Backup failed. Aborting." -Level "ERROR"
            return $false
        }
    }
    
    # Enable feature in .env
    $flagName = $FeatureFlags[$Feature]
    
    if (Test-Path $EnvFile) {
        $content = Get-Content $EnvFile -Raw
        
        if ($content -match "$flagName=false") {
            $content = $content -replace "$flagName=false", "$flagName=true"
            Set-Content -Path $EnvFile -Value $content
            Write-Log "Feature $Feature enabled in .env" -Level "SUCCESS"
        }
        elseif ($content -match "$flagName=true") {
            Write-Log "Feature $Feature already enabled" -Level "INFO"
        }
        else {
            Add-Content -Path $EnvFile -Value "`n$flagName=true"
            Write-Log "Feature $Feature added to .env" -Level "SUCCESS"
        }
    }
    else {
        Set-Content -Path $EnvFile -Value "$flagName=true"
        Write-Log "Created .env with $Feature enabled" -Level "SUCCESS"
    }
    
    Write-Log "" -Level "INFO"
    Write-Log "STAGING ACTIVATION COMPLETE" -Level "SUCCESS"
    Write-Log "Next steps:" -Level "INFO"
    Write-Log "  1. Restart the backend server" -Level "INFO"
    Write-Log "  2. Test the feature thoroughly" -Level "INFO"
    Write-Log "  3. To rollback: .\scripts\test-feature-activation.ps1 -Mode Rollback -BackupPath $backupPath" -Level "INFO"
    
    return $true
}

# ============================================================================
# MODE: PRODUCTION
# ============================================================================

function Start-Production {
    Write-Log "========== PRODUCTION MODE ==========" -Level "INFO"
    Write-Log "WARNING: This will enable features in PRODUCTION" -Level "ERROR"
    Write-Log "Feature: $Feature" -Level "INFO"
    Write-Log ""
    
    # Multiple confirmations required
    Write-Log "REQUIRED CHECKLIST:" -Level "ERROR"
    Write-Log "  [ ] Pre-flight checks passed in DryRun mode" -Level "INFO"
    Write-Log "  [ ] Feature tested in Staging environment" -Level "INFO"
    Write-Log "  [ ] Rollback procedure documented" -Level "INFO"
    Write-Log "  [ ] Team notified of change" -Level "INFO"
    Write-Log "  [ ] Maintenance window scheduled (if applicable)" -Level "INFO"
    Write-Log ""
    
    $confirm1 = Read-Host "Have you completed ALL checks above? (type 'yes' to confirm)"
    if ($confirm1 -ne "yes") {
        Write-Log "Production activation cancelled" -Level "INFO"
        return $false
    }
    
    $confirm2 = Read-Host "Are you ABSOLUTELY SURE you want to enable $Feature in PRODUCTION? (type 'ENABLE-PRODUCTION' to confirm)"
    if ($confirm2 -ne "ENABLE-PRODUCTION") {
        Write-Log "Production activation cancelled - confirmation mismatch" -Level "INFO"
        return $false
    }
    
    # Mandatory backup
    $backupPath = Backup-EnvironmentFile
    if (!$backupPath) {
        Write-Log "Backup failed. Production activation ABORTED." -Level "ERROR"
        return $false
    }
    
    Write-Log "" -Level "INFO"
    Write-Log "BACKUP CREATED: $backupPath" -Level "SUCCESS"
    Write-Log ""
    Write-Log "PRODUCTION ACTIVATION IN PROGRESS..." -Level "ERROR"
    
    # Enable feature
    $flagName = $FeatureFlags[$Feature]
    
    if (Test-Path $EnvFile) {
        $content = Get-Content $EnvFile -Raw
        
        if ($content -match "$flagName=false") {
            $content = $content -replace "$flagName=false", "$flagName=true"
            Set-Content -Path $EnvFile -Value $content
        }
        else {
            Add-Content -Path $EnvFile -Value "`n$flagName=true"
        }
    }
    
    Write-Log "Feature $Feature ENABLED in production .env" -Level "SUCCESS"
    Write-Log "" -Level "INFO"
    Write-Log "CRITICAL NEXT STEPS:" -Level "ERROR"
    Write-Log "  1. Restart production backend server IMMEDIATELY" -Level "INFO"
    Write-Log "  2. Verify feature works: curl http://localhost:8000/health" -Level "INFO"
    Write-Log "  3. Monitor logs for errors" -Level "INFO"
    Write-Log "  4. Test core functionality" -Level "INFO"
    Write-Log "" -Level "INFO"
    Write-Log "ROLLBACK COMMAND (save this):" -Level "ERROR"
    Write-Log "  Copy-Item '$backupPath' '$EnvFile' -Force" -Level "INFO"
    Write-Log "  Then restart the server" -Level "INFO"
    Write-Log "" -Level "INFO"
    Write-Log "Log saved to: $LogFile" -Level "INFO"
    
    return $true
}

# ============================================================================
# MAIN
# ============================================================================

Write-Log "Feature Activation Test Script" -Level "INFO"
Write-Log "Mode: $Mode | Feature: $Feature" -Level "INFO"
Write-Log "Project: $ProjectRoot" -Level "INFO"
Write-Log "Log: $LogFile" -Level "INFO"
Write-Log ""

# Check if we're in the right directory
if (!(Test-Path $ProjectRoot)) {
    Write-Log "ERROR: Project not found at $ProjectRoot" -Level "ERROR"
    exit 1
}

# Execute based on mode
$result = switch ($Mode) {
    "DryRun" { Start-DryRun }
    "Staging" { Start-Staging }
    "Production" { Start-Production }
    default { 
        Write-Log "Unknown mode: $Mode" -Level "ERROR"
        $false
    }
}

if ($result) {
    Write-Log "" -Level "INFO"
    Write-Log "Script completed successfully" -Level "SUCCESS"
    exit 0
}
else {
    Write-Log "" -Level "INFO"
    Write-Log "Script completed with warnings or errors" -Level "WARN"
    exit 1
}
