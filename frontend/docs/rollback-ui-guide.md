# UI Rollback Guide

## Overview
This guide provides instructions for rolling back from the new scan UI to the legacy UI in case of critical issues.

## Rollback Triggers
Consider rollback if:
- Critical bugs prevent users from scanning invoices
- App crash rate > 1%
- Scan success rate < 90%
- Average scan time > 60 seconds
- User complaints > 5 per day

## Emergency Rollback (Quick Fix)

### Option 1: Use Debug Overlay (Fastest)
1. Open the app with debug mode enabled
2. Click the orange settings icon (top-right corner)
3. Click "Go to Legacy UI" button
4. This provides immediate access to legacy UI without code changes

### Option 2: Use Legacy Route
Navigate to `/legacy-home` route:
```dart
Navigator.pushNamed(context, '/legacy-home');
```

## Full Rollback (Code Changes)

### Windows PowerShell
```powershell
cd frontend
.\scripts\rollback-ui.ps1
flutter pub get
flutter run
```

### Linux/macOS Bash
```bash
cd frontend
bash scripts/rollback-ui.sh
flutter pub get
flutter run
```

### Manual Rollback Steps
If scripts fail, perform these steps manually:

1. **Restore Feature Flag Default**
   - Edit `lib/core/config/feature_flags.dart`
   - Change line 37 from `return true;` to `return false;`

2. **Restore main.dart Imports**
   - Edit `lib/main.dart`
   - Change imports from `legacy/` back to direct paths:
   ```dart
   import 'screens/home_screen.dart';
   import 'screens/scan_result_screen.dart';
   import 'screens/verification_screen.dart';
   import 'widgets/batch_invoice_uploader.dart';
   ```

3. **Restore Home Route**
   - Edit `lib/main.dart`
   - Change `home: ScanUploadScreen()` to `home: HomeScreen()`
   - Remove `legacy.` prefix from routes

4. **Restore Legacy Files**
   ```powershell
   Move-Item lib/legacy/ui/* lib/screens/ -Force
   Move-Item lib/legacy/widgets/* lib/widgets/ -Force
   ```

5. **Clean Up Placeholders**
   - Delete placeholder files in `lib/screens/` and `lib/widgets/`

6. **Update Dependencies**
   ```bash
   flutter pub get
   flutter clean
   flutter run
   ```

## Verification Checklist After Rollback

- [ ] App starts successfully
- [ ] Legacy home screen loads
- [ ] Legacy scan flow works
- [ ] No import errors
- [ ] No build errors
- [ ] Feature flag shows as disabled in debug overlay

## Rollback Validation Commands

```bash
# Check for build errors
flutter analyze

# Try to build
flutter build apk --debug

# Run tests
flutter test
```

## Rollback Confirmation

After rollback, verify:
- [ ] Users can scan invoices
- [ ] Scan success rate > 95%
- [ ] App crash rate < 0.1%
- [ ] User feedback positive

## Re-rollout to New UI

After fixing issues, re-rollout:

1. Re-apply Phase 3A changes
2. Test thoroughly
3. Gradual rollout following rollout checklist
4. Monitor metrics closely

## Support Contacts

If rollback fails or issues persist:
- Check logs in `flutter run` output
- Review error messages
- Check git history for recent changes
- Contact development team

## Rollback Timeline

- **Day 0-7**: Legacy UI available at `/legacy-home` route
- **Day 7**: Remove legacy route if no rollback needed
- **Day 7-14**: Keep legacy files in `lib/legacy/` for safety
- **Day 14**: Delete legacy files if stable

## Important Notes

- Rollback is reversible - you can re-rollout after fixing issues
- Legacy UI remains functional during 7-day window
- Debug overlay provides instant access to legacy UI
- Always test rollback procedure before deployment
