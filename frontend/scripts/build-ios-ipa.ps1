# Script to build iOS IPA (macOS only)
# Run this script from the frontend directory on macOS

Write-Host "=== Building iOS IPA ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "Note: This script requires macOS with Xcode installed" -ForegroundColor Yellow
Write-Host ""

# Check if running on macOS
if ($IsWindows) {
    Write-Host "Error: This script must be run on macOS" -ForegroundColor Red
    exit 1
}

# Step 1: Get dependencies
Write-Host "Step 1: Getting dependencies..." -ForegroundColor Cyan
flutter pub get

# Step 2: Build iOS IPA (release)
Write-Host "Step 2: Building iOS IPA..." -ForegroundColor Cyan
flutter build ipa --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "iOS IPA build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "IPA location: build/ios/archive/" -ForegroundColor Yellow
Write-Host ""
Write-Host "To upload to App Store:" -ForegroundColor Cyan
Write-Host "  1. Open Xcode" -ForegroundColor Yellow
Write-Host "  2. Go to Product > Archive" -ForegroundColor Yellow
Write-Host "  3. Upload to App Store Connect" -ForegroundColor Yellow
