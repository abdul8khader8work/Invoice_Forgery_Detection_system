# Script to build Android App Bundle
# Run this script from the frontend directory

Write-Host "=== Building Android App Bundle ===" -ForegroundColor Yellow
Write-Host ""

# Step 1: Get dependencies
Write-Host "Step 1: Getting dependencies..." -ForegroundColor Cyan
flutter pub get

# Step 2: Build Android App Bundle (release)
Write-Host "Step 2: Building Android App Bundle..." -ForegroundColor Cyan
flutter build appbundle --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "Android App Bundle build failed!" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "App Bundle location: build/app/outputs/bundle/release/" -ForegroundColor Yellow
Write-Host ""
Write-Host "To upload to Google Play:" -ForegroundColor Cyan
Write-Host "  1. Go to Google Play Console" -ForegroundColor Yellow
Write-Host "  2. Create new release" -ForegroundColor Yellow
Write-Host "  3. Upload the .aab file" -ForegroundColor Yellow
