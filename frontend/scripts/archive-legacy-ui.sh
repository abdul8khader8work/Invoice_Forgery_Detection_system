#!/bin/bash

# Script to archive legacy UI files to lib/legacy/ui/
# This script should be run from the frontend directory

echo "Archiving legacy UI files to lib/legacy/ui/"

# Create legacy directory if it doesn't exist
mkdir -p lib/legacy/ui
mkdir -p lib/legacy/widgets

# Move screen files
echo "Moving screen files..."
mv lib/screens/home_screen.dart lib/legacy/ui/
mv lib/screens/scan_result_screen.dart lib/legacy/ui/
mv lib/screens/verification_screen.dart lib/legacy/ui/
mv lib/screens/active_learning_verification_screen.dart lib/legacy/ui/
mv lib/screens/invoice_chat_screen.dart lib/legacy/ui/
mv lib/screens/invoice_preview_screen.dart lib/legacy/ui/
mv lib/screens/smart_ingestion_screen.dart lib/legacy/ui/

# Move widget files
echo "Moving widget files..."
mv lib/widgets/batch_invoice_uploader.dart lib/legacy/widgets/
mv lib/widgets/pre_upload_preview.dart lib/legacy/widgets/
mv lib/widgets/recent_scans.dart lib/legacy/widgets/

# Create placeholder files with deprecation warnings
echo "Creating placeholder files with deprecation warnings..."

# Create placeholder for home_screen.dart
cat > lib/screens/home_screen.dart << 'EOF'
@Deprecated('Use features/scan/screens/scan_upload_screen.dart instead')
library;

// Legacy UI archived to lib/legacy/ui/
// Use the new scan flow at features/scan/screens/scan_upload_screen.dart
// Emergency access available at /legacy-home route
EOF

# Create placeholder for other screens
for file in scan_result_screen verification_screen active_learning_verification_screen invoice_chat_screen invoice_preview_screen smart_ingestion_screen; do
  cat > lib/screens/${file}.dart << EOF
@Deprecated('Use features/scan/ instead')
library;

// Legacy UI archived to lib/legacy/ui/${file}.dart
// Use the new scan flow at features/scan/
// Emergency access available at /legacy-home route
EOF
done

echo "Legacy UI archival complete!"
echo "Run 'flutter pub run build_runner build --delete-conflicting-outputs' to update generated files"
