#Requires -Version 7.0
<#
.SYNOPSIS
    End-to-End Test Orchestrator for Invoice Forgery Detection System
    
.DESCRIPTION
    Runs complete E2E test suite across frontend and backend:
    - Starts backend server in test mode
    - Runs backend integration tests (pytest)
    - Builds frontend for testing
    - Runs Flutter integration tests
    - Generates consolidated report
    
    Test Scenarios:
    1. Happy Path: Upload → OCR → validation → ML → results
    2. Async Flow: Polling fallback vs SSE
    3. Error Handling: Invalid files, timeouts, graceful recovery
    4. Cross-Platform: Web, Windows, Mobile
    
.PARAMETER TestMode
    Test mode: smoke, full, or ci
    
.PARAMETER Platform
    Target platform: web, windows, mobile, or all
    
.PARAMETER ReportPath
    Path for test report output
    
.EXAMPLE
    # Quick smoke test
    .\scripts\run-e2e-tests.ps1 -TestMode smoke
    
    # Full test suite
    .\scripts\run-e2e-tests.ps1 -TestMode full -Platform all
    
    # CI mode (no prompts, exit codes)
    .\scripts\run-e2e-tests.ps1 -TestMode ci
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("smoke", "full", "ci")]
    [string]$TestMode = "smoke",
    
    [Parameter()]
    [ValidateSet("web", "windows", "mobile", "all")]
    [string]$Platform = "web",
    
    [Parameter()]
    [string]$ReportPath = "$PSScriptRoot\..\reports\e2e-test-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ProjectRoot = Resolve-Path "$PSScriptRoot\.."
$BackendPath = "$ProjectRoot\backend"
$FrontendPath = "$ProjectRoot\frontend"
$ReportDir = Split-Path -Parent $ReportPath

# Test results
$TestResults = @{
    Backend = @{ Passed = 0; Failed = 0; Skipped = 0; Duration = 0 }
    Frontend = @{ Passed = 0; Failed = 0; Skipped = 0; Duration = 0 }
    StartTime = Get-Date
    EndTime = $null
}

# ============================================================================
# LOGGING
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [switch]$NoNewline
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        "SUCCESS" { "Green" }
        "SECTION" { "Cyan" }
        default { "White" }
    }
    
    $params = @{
        Object = "[$timestamp] $Message"
        ForegroundColor = $color
        NoNewline = $NoNewline
    }
    
    Write-Host @params
}

function Write-Section {
    param([string]$Title)
    Write-Log "" -Level "SECTION"
    Write-Log "=" * 60 -Level "SECTION"
    Write-Log $Title -Level "SECTION"
    Write-Log "=" * 60 -Level "SECTION"
}

# ============================================================================
# TEST PHASES
# ============================================================================

function Start-BackendServer {
    Write-Section "PHASE 1: Starting Backend Server"
    
    # Check if server is already running
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:8000/health" -TimeoutSec 5 -ErrorAction Stop
        Write-Log "Backend server already running (health check passed)" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Backend server not running, attempting to start..." -Level "WARN"
    }
    
    # Start server in background
    $env:PYTHONPATH = $BackendPath
    $job = Start-Job -ScriptBlock {
        param($BackendPath)
        Set-Location $BackendPath
        .\venv\Scripts\python.exe main.py 2>&1
    } -ArgumentList $BackendPath
    
    Write-Log "Waiting for server to start..." -NoNewline
    $maxAttempts = 30
    $attempt = 0
    
    while ($attempt -lt $maxAttempts) {
        Start-Sleep -Seconds 1
        try {
            $response = Invoke-RestMethod -Uri "http://localhost:8000/health" -TimeoutSec 2 -ErrorAction Stop
            Write-Log " READY!" -Level "SUCCESS"
            return $true
        }
        catch {
            $attempt++
            Write-Log "." -NoNewline
        }
    }
    
    Write-Log " TIMEOUT!" -Level "ERROR"
    Write-Log "Failed to start backend server after $maxAttempts seconds" -Level "ERROR"
    return $false
}

function Run-BackendTests {
    Write-Section "PHASE 2: Backend Integration Tests"
    
    Set-Location $BackendPath
    
    # Check if pytest is available
    $pytestPath = ".\venv\Scripts\pytest.exe"
    if (!(Test-Path $pytestPath)) {
        Write-Log "pytest not found, installing..." -Level "WARN"
        .\venv\Scripts\pip.exe install pytest pytest-html -q
    }
    
    $startTime = Get-Date
    
    # Run pytest
    $testArgs = @(
        "tests\integration\test_scan_pipeline.py",
        "-v",
        "--tb=short"
    )
    
    if ($TestMode -eq "smoke") {
        $testArgs += "-k", "TestHealth or TestAPIContract"
    }
    
    if ($TestMode -eq "ci") {
        $testArgs += "--html=$ReportPath.backend.html", "--self-contained-html"
    }
    
    Write-Log "Running: pytest $($testArgs -join ' ')"
    
    try {
        $output = & $pytestPath @testArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        # Parse output for results
        $passed = ($output | Select-String "passed" | ForEach-Object { $_ } | Select-Object -First 1)
        $failed = ($output | Select-String "failed" | ForEach-Object { $_ } | Select-Object -First 1)
        $skipped = ($output | Select-String "skipped" | ForEach-Object { $_ } | Select-Object -First 1)
        
        $TestResults.Backend.Duration = ((Get-Date) - $startTime).TotalSeconds
        
        if ($exitCode -eq 0) {
            Write-Log "Backend tests PASSED" -Level "SUCCESS"
            $TestResults.Backend.Passed = 1
        }
        else {
            Write-Log "Backend tests FAILED (exit code: $exitCode)" -Level "ERROR"
            $TestResults.Backend.Failed = 1
            
            # Show last 20 lines of output
            Write-Log "Last output lines:" -Level "WARN"
            $output | Select-Object -Last 20 | ForEach-Object { Write-Log "  $_" }
        }
        
        return $exitCode -eq 0
    }
    catch {
        Write-Log "Error running backend tests: $_" -Level "ERROR"
        $TestResults.Backend.Failed = 1
        return $false
    }
}

function Run-FrontendTests {
    Write-Section "PHASE 3: Frontend Integration Tests"
    
    Set-Location $FrontendPath
    
    # Check Flutter is available
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if (!$flutterCmd) {
        Write-Log "Flutter not found in PATH" -Level "ERROR"
        $TestResults.Frontend.Failed = 1
        return $false
    }
    
    $startTime = Get-Date
    
    # Determine target device
    $device = switch ($Platform) {
        "web" { "chrome" }
        "windows" { "windows" }
        "mobile" { "emulator-5554" }
        default { "chrome" }
    }
    
    Write-Log "Running Flutter integration tests on $device"
    
    # Run integration tests
    $testArgs = @(
        "test",
        "integration_test"
    )
    
    if ($TestMode -eq "smoke") {
        $testArgs += "--reporter=compact"
    }
    
    if ($Platform -eq "web" -or $Platform -eq "all") {
        $testArgs += "-d", "chrome"
    }
    
    if ($TestMode -eq "ci") {
        $testArgs += "--machine" | Out-File -FilePath "$ReportPath.frontend.json"
    }
    
    Write-Log "Running: flutter $($testArgs -join ' ')"
    
    try {
        $output = & flutter @testArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        $TestResults.Frontend.Duration = ((Get-Date) - $startTime).TotalSeconds
        
        if ($exitCode -eq 0) {
            Write-Log "Frontend tests PASSED" -Level "SUCCESS"
            $TestResults.Frontend.Passed = 1
        }
        else {
            Write-Log "Frontend tests FAILED (exit code: $exitCode)" -Level "ERROR"
            $TestResults.Frontend.Failed = 1
        }
        
        return $exitCode -eq 0
    }
    catch {
        Write-Log "Error running frontend tests: $_" -Level "ERROR"
        $TestResults.Frontend.Failed = 1
        return $false
    }
}

function New-TestReport {
    Write-Section "PHASE 4: Generating Test Report"
    
    $TestResults.EndTime = Get-Date
    $totalDuration = ($TestResults.EndTime - $TestResults.StartTime).TotalSeconds
    
    $reportHtml = @"
<!DOCTYPE html>
<html>
<head>
    <title>E2E Test Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #1976D2; padding-bottom: 10px; }
        .summary { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin: 30px 0; }
        .metric { background: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center; }
        .metric-value { font-size: 36px; font-weight: bold; color: #1976D2; }
        .metric-label { color: #666; margin-top: 5px; }
        .section { margin: 30px 0; }
        .section-title { font-size: 20px; font-weight: 600; color: #333; margin-bottom: 15px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #e0e0e0; }
        th { background: #f5f5f5; font-weight: 600; }
        .status-pass { color: #4CAF50; font-weight: bold; }
        .status-fail { color: #f44336; font-weight: bold; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #e0e0e0; color: #666; font-size: 14px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>End-to-End Test Report</h1>
        <p>Generated: $($TestResults.EndTime)</p>
        <p>Test Mode: $TestMode | Platform: $Platform</p>
        
        <div class="summary">
            <div class="metric">
                <div class="metric-value">$($TestResults.Backend.Passed + $TestResults.Frontend.Passed)</div>
                <div class="metric-label">Tests Passed</div>
            </div>
            <div class="metric">
                <div class="metric-value">$($TestResults.Backend.Failed + $TestResults.Frontend.Failed)</div>
                <div class="metric-label">Tests Failed</div>
            </div>
            <div class="metric">
                <div class="metric-value">$([math]::Round($totalDuration, 1))s</div>
                <div class="metric-label">Total Duration</div>
            </div>
        </div>
        
        <div class="section">
            <div class="section-title">Backend Tests</div>
            <table>
                <tr>
                    <th>Status</th>
                    <th>Passed</th>
                    <th>Failed</th>
                    <th>Skipped</th>
                    <th>Duration</th>
                </tr>
                <tr>
                    <td class="$(if ($TestResults.Backend.Failed -eq 0) { 'status-pass' } else { 'status-fail' })">
                        $(if ($TestResults.Backend.Failed -eq 0) { '✅ PASS' } else { '❌ FAIL' })
                    </td>
                    <td>$($TestResults.Backend.Passed)</td>
                    <td>$($TestResults.Backend.Failed)</td>
                    <td>$($TestResults.Backend.Skipped)</td>
                    <td>$([math]::Round($TestResults.Backend.Duration, 1))s</td>
                </tr>
            </table>
        </div>
        
        <div class="section">
            <div class="section-title">Frontend Tests</div>
            <table>
                <tr>
                    <th>Status</th>
                    <th>Passed</th>
                    <th>Failed</th>
                    <th>Skipped</th>
                    <th>Duration</th>
                </tr>
                <tr>
                    <td class="$(if ($TestResults.Frontend.Failed -eq 0) { 'status-pass' } else { 'status-fail' })">
                        $(if ($TestResults.Frontend.Failed -eq 0) { '✅ PASS' } else { '❌ FAIL' })
                    </td>
                    <td>$($TestResults.Frontend.Passed)</td>
                    <td>$($TestResults.Frontend.Failed)</td>
                    <td>$($TestResults.Frontend.Skipped)</td>
                    <td>$([math]::Round($TestResults.Frontend.Duration, 1))s</td>
                </tr>
            </table>
        </div>
        
        <div class="footer">
            <p><strong>Test Coverage:</strong></p>
            <ul>
                <li>Happy Path: Upload → OCR → Validation → ML → Results</li>
                <li>Async Flow: Polling fallback vs SSE</li>
                <li>Error Handling: Invalid files, timeouts, graceful recovery</li>
                <li>Cross-Platform: Web, Windows, Mobile</li>
            </ul>
            <p><strong>Next Steps:</strong></p>
            <ul>
                <li>Review failed tests and fix issues</li>
                <li>Re-run with: .\scripts\run-e2e-tests.ps1 -TestMode full</li>
                <li>Check detailed logs in reports directory</li>
            </ul>
        </div>
    </div>
</body>
</html>
"@
    
    # Ensure report directory exists
    if (!(Test-Path $ReportDir)) {
        New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
    }
    
    # Write report
    $reportHtml | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-Log "Test report generated: $ReportPath" -Level "SUCCESS"
    
    # Also show summary in console
    Write-Log "" -Level "SECTION"
    Write-Log "TEST SUMMARY" -Level "SECTION"
    Write-Log "Backend: $($TestResults.Backend.Passed) passed, $($TestResults.Backend.Failed) failed" -Level $(if ($TestResults.Backend.Failed -eq 0) { "SUCCESS" } else { "ERROR" })
    Write-Log "Frontend: $($TestResults.Frontend.Passed) passed, $($TestResults.Frontend.Failed) failed" -Level $(if ($TestResults.Frontend.Failed -eq 0) { "SUCCESS" } else { "ERROR" })
    Write-Log "Total Duration: $([math]::Round($totalDuration, 1))s" -Level "INFO"
    Write-Log "" -Level "SECTION"
}

# ============================================================================
# MAIN
# ============================================================================

Write-Section "End-to-End Test Orchestrator"
Write-Log "Project: $ProjectRoot"
Write-Log "Mode: $TestMode | Platform: $Platform"
Write-Log "Report: $ReportPath"
Write-Log ""

# Verify project structure
if (!(Test-Path $BackendPath)) {
    Write-Log "Backend not found at: $BackendPath" -Level "ERROR"
    exit 1
}

if (!(Test-Path $FrontendPath)) {
    Write-Log "Frontend not found at: $FrontendPath" -Level "ERROR"
    exit 1
}

# Run test phases
$backendReady = Start-BackendServer
if (!$backendReady) {
    Write-Log "Cannot proceed without backend server" -Level "ERROR"
    exit 1
}

$backendSuccess = Run-BackendTests

# Only run frontend tests if backend passed (or in full/ci mode)
if ($backendSuccess -or $TestMode -eq "full") {
    $frontendSuccess = Run-FrontendTests
}
else {
    Write-Log "Skipping frontend tests (backend failed)" -Level "WARN"
    $frontendSuccess = $false
}

# Generate report
New-TestReport

# Final status
$overallSuccess = $backendSuccess -and $frontendSuccess

if ($overallSuccess) {
    Write-Log "✅ ALL TESTS PASSED" -Level "SUCCESS"
    exit 0
}
else {
    Write-Log "❌ SOME TESTS FAILED" -Level "ERROR"
    exit 1
}
