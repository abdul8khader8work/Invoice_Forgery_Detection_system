# Cross-Platform Test Commands

## Web (Chrome with WASM)

```bash
# Run web with WASM renderer
flutter run -d chrome --web-renderer wasm --dart-define=ENABLE_NEW_SCAN_UI=true

# Build web with WASM for production
flutter build web --web-renderer wasm --release --dart-define=ENABLE_NEW_SCAN_UI=true

# Test web locally
flutter run -d chrome --release --dart-define=ENABLE_NEW_SCAN_UI=true
```

## Windows

```bash
# Run on Windows desktop
flutter run -d windows --dart-define=ENABLE_NEW_SCAN_UI=true

# Build Windows release
flutter build windows --release --dart-define=ENABLE_NEW_SCAN_UI=true
```

## Android

```bash
# Run on connected Android device
flutter run -d android --dart-define=ENABLE_NEW_SCAN_UI=true

# Build Android APK
flutter build apk --release --dart-define=ENABLE_NEW_SCAN_UI=true

# Build Android App Bundle
flutter build appbundle --release --dart-define=ENABLE_NEW_SCAN_UI=true
```

## iOS

```bash
# Run on connected iOS device (macOS only)
flutter run -d ios --dart-define=ENABLE_NEW_SCAN_UI=true

# Build iOS (macOS only)
flutter build ios --release --dart-define=ENABLE_NEW_SCAN_UI=true
```

## Deep Link Testing

```bash
# Test deep link to new scan screen
# After starting app with feature flag enabled:
# Navigate to: /new-scan
# Should show new upload screen

# Test old route still works
# Navigate to: /scan
# Should show old scan screen
```

## Platform-Specific Fixes Implemented

1. **Touch Targets**: All buttons have minimum 48px height (WCAG 2.1 AA)
2. **Keyboard Navigation**: Added Focus nodes to all interactive elements
3. **Platform Detection**: Camera button hidden on desktop/web
4. **Semantics**: Added proper accessibility labels and hints
5. **Responsive Design**: Layout adapts to different screen sizes

## Validation Checklist

- [ ] Web: Drag/drop works in Chrome
- [ ] Web: Gallery picker works
- [ ] Windows: File picker works
- [ ] Windows: Keyboard navigation works (Tab/Enter/Space)
- [ ] Android: Camera works
- [ ] Android: Gallery works
- [ ] Android: Touch targets accessible
- [ ] iOS: Camera works
- [ ] iOS: Gallery works
- [ ] iOS: Touch targets accessible
- [ ] Deep links work when feature flag enabled
- [ ] Old route (/scan) still accessible
- [ ] New route (/new-scan) only when flag enabled
