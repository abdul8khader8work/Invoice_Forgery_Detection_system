# Script to archive legacy UI files to lib/legacy/ui/
# This script should be run from the frontend directory

Write-Host "Archiving legacy UI files to lib/legacy/ui/" -ForegroundColor Yellow

# Create legacy directory if it doesn't exist
if (-not (Test-Path "lib/legacy/ui")) {
    New-Item -ItemType Directory -Path "lib/legacy/ui" -Force
}
if (-not (Test-Path "lib/legacy/widgets")) {
    New-Item -ItemType Directory -Path "lib/legacy/widgets" -Force
}

# Move screen files
Write-Host "Moving screen files..." -ForegroundColor Cyan
Move-Item -Path "lib/screens/home_screen.dart" -Destination "lib/legacy/ui/" -Force -ErrorAction SilentlyContinue
Move-Item -Path "lib/screens/scan_result_screen.dart" -Destination "lib/legacy/ui/" -Force -ErrorAction SilentlyContinue
Move-Item -Path "lib/screens/verification_screen.dart" -Destination "lib/legacy/ui/" -Force -ErrorAction SilentlyContinue
Move-Item -Path "lib/screens/active_learning_verification_screen.dart" -Destination "lib/legacy/ui/" -Force -ErrorAction SilentlyContinue
Move-Item -Path "lib/screens/invoice_chat_screen.dart" -Destination "lib/legacy/ui/" -Force -ErrorAction SilentlyContinue
Move-Item -Path "lib/screens/invoice_preview_screen.dart" -Destination "lib/legacy/ui/" -Force -ErrorAction SilentlyContinue
Move-Item -Path "lib/screens/smart_ingestion_screen.dart" -Destination "lib/legacy/ui/" -Force -ErrorAction SilentlyContinue

# Move widget files
Write-Host "Moving widget files..." -ForegroundColor Cyan
Move-Item -Path "lib/widgets/batch_invoice_uploader.dart" -Destination "lib/legacy/widgets/" -Force -ErrorAction SilentlyContinue
Move-Item -Path "lib/widgets/pre_upload_preview.dart" -Destination "lib/legacy/widgets/" -Force -ErrorAction SilentlyContinue
Move-Item -Path "lib/widgets/recent_scans.dart" -Destination "lib/legacy/widgets/" -Force -ErrorAction SilentlyContinue

# Create placeholder files with deprecation warnings
Write-Host "Creating placeholder files with deprecation warnings..." -ForegroundColor Cyan

# Create placeholder for home_screen.dart
@"
@Deprecated('Use features/scan/screens/scan_upload_screen.dart instead')
library;

// Legacy UI archived to lib/legacy/ui/
// Use the new scan flow at features/scan/screens/scan_upload_screen.dart
// Emergency access available at /legacy-home route
"@ | Out-File -FilePath "lib/screens/home_screen.dart" -Encoding utf8

# Create placeholders for other screens
$screenFiles = @("scan_result_screen", "verification_screen", "active_learning_verification_screen", "invoice_chat_screen", "invoice_preview_screen", "smart_ingestion_screen")

foreach ($file in $screenFiles) {
    @"
@Deprecated('Use features/scan/ instead')
library;

// Legacy UI archived to lib/legacy/ui/${file}.dart
// Use the new scan flow at features/scan/
// Emergency access available at /legacy-home route
"@ | Out-File -FilePath "lib/screens/${file}.dart" -Encoding utf8
}

Write-Host "Legacy UI archival complete!" -ForegroundColor Green
Write-Host "Update main.dart imports to reference lib/legacy/ui/" -ForegroundColor Yellow
