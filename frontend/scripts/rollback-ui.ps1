# Rollback script to revert to legacy UI
# This script flips the feature flag default back to false and restores legacy imports
# Run this script from the frontend directory

Write-Host "=== UI Rollback Script ===" -ForegroundColor Yellow
Write-Host "This will revert the app to use the legacy UI" -ForegroundColor Yellow
Write-Host ""

# Step 1: Restore feature flag default to false
Write-Host "Step 1: Restoring feature flag default to false..." -ForegroundColor Cyan
$featureFlagFile = "lib/core/config/feature_flags.dart"
if (Test-Path $featureFlagFile) {
    (Get-Content $featureFlagFile) -replace 'return true;', 'return false;' | Set-Content $featureFlagFile
    Write-Host "Feature flag default set to false" -ForegroundColor Green
} else {
    Write-Host "Feature flag file not found: $featureFlagFile" -ForegroundColor Red
    exit 1
}

# Step 2: Restore main.dart imports
Write-Host "Step 2: Restoring main.dart imports..." -ForegroundColor Cyan
$mainDartFile = "lib/main.dart"
if (Test-Path $mainDartFile) {
    # Restore original imports
    $content = @"
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';
import 'screens/scan_result_screen.dart';
import 'screens/verification_screen.dart';
import 'widgets/batch_invoice_uploader.dart';
import 'core/widgets/debug_feature_flag_overlay.dart';
import 'features/scan/screens/scan_upload_screen.dart';
"@
    
    # Update the imports section
    $currentContent = Get-Content $mainDartFile -Raw
    $newContent = $currentContent -replace '(?s)import.*?import.*?;', $content
    Set-Content $mainDartFile -Value $newContent
    
    # Restore home route
    $newContent = (Get-Content $mainDartFile -Raw) -replace 'ScanUploadScreen\(\)', 'HomeScreen()'
    Set-Content $mainDartFile -Value $newContent
    
    # Restore routes
    $newContent = (Get-Content $mainDartFile -Raw) -replace 'legacy\.', ''
    Set-Content $mainDartFile -Value $newContent
    
    Write-Host "main.dart imports restored" -ForegroundColor Green
} else {
    Write-Host "main.dart not found: $mainDartFile" -ForegroundColor Red
    exit 1
}

# Step 3: Restore legacy files from lib/legacy/ui/ to lib/screens/
Write-Host "Step 3: Restoring legacy files..." -ForegroundColor Cyan
if (Test-Path "lib/legacy/ui") {
    Move-Item -Path "lib/legacy/ui/*" -Destination "lib/screens/" -Force -ErrorAction SilentlyContinue
    Write-Host "Legacy screen files restored" -ForegroundColor Green
}
if (Test-Path "lib/legacy/widgets") {
    Move-Item -Path "lib/legacy/widgets/*" -Destination "lib/widgets/" -Force -ErrorAction SilentlyContinue
    Write-Host "Legacy widget files restored" -ForegroundColor Green
}

# Step 4: Clean up placeholder files
Write-Host "Step 4: Cleaning up placeholder files..." -ForegroundColor Cyan
Get-ChildItem -Path "lib/screens" -Filter "*.dart" | Where-Object { $_.Length -lt 100 } | Remove-Item -Force
Get-ChildItem -Path "lib/widgets" -Filter "*.dart" | Where-Object { $_.Length -lt 100 } | Remove-Item -Force
Write-Host "Placeholder files cleaned up" -ForegroundColor Green

Write-Host ""
Write-Host "=== Rollback Complete ===" -ForegroundColor Green
Write-Host "Run 'flutter pub get' to update dependencies" -ForegroundColor Yellow
Write-Host "Run 'flutter run' to test the legacy UI" -ForegroundColor Yellow
