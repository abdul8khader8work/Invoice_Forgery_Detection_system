# Mobile Build Guide

## Android Build

### Prerequisites
- Android SDK installed
- Java JDK 11 or higher
- Keystore file for signing (production)

### Development Build
```bash
flutter build apk --debug
```

### Release Build (APK)
```bash
flutter build apk --release
```

### Release Build (App Bundle - Recommended for Play Store)
```bash
flutter build appbundle --release
```

### Using Build Script
```powershell
.\scripts\build-android-appbundle.ps1
```

### Signing Configuration

#### Development (Debug)
- Uses debug keystore (auto-generated)
- No manual configuration needed

#### Production (Release)
1. Create keystore:
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Add to `android/key.properties`:
```properties
storePassword=your_password
keyPassword=your_password
keyAlias=upload
storeFile=../upload-keystore.jks
```

3. Update `android/app/build.gradle`:
```gradle
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
        storePassword keystoreProperties['storePassword']
    }
}
```

### Android Configuration

#### Minimum SDK
```gradle
android {
    defaultConfig {
        minSdkVersion 21  // Android 5.0 Lollipop
        targetSdkVersion 34  // Android 14
    }
}
```

#### Permissions
Add to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
```

## iOS Build

### Prerequisites
- macOS with Xcode 15+
- Apple Developer account
- Provisioning profile

### Development Build
```bash
flutter build ios --debug
```

### Release Build (IPA)
```bash
flutter build ipa --release
```

### Using Build Script
```powershell
.\scripts\build-ios-ipa.ps1
```

### Signing Configuration

#### Development
- Uses automatic signing
- No manual configuration needed

#### Production
1. Create App ID in Apple Developer Console
2. Create provisioning profile
3. Download and add to Xcode
4. Update signing in Xcode project settings

### iOS Configuration

#### Minimum iOS Version
Update `ios/Runner/Info.plist`:
```xml
<key>MinimumOSVersion</key>
<string>12.0</string>
```

#### Permissions
Add to `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera is required to scan invoices</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library is required to select invoices</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Photo library is required to save processed invoices</string>
```

#### Adaptive Icon
Add adaptive icon assets to `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

## Build Verification

### Android
```bash
flutter doctor -v
flutter build appbundle --release
# Check build/app/outputs/bundle/release/
```

### iOS
```bash
flutter doctor -v
flutter build ipa --release
# Check build/ios/archive/
```

## Troubleshooting

### Android Build Fails
- Check Java version (must be 11)
- Check Android SDK path
- Verify keystore configuration
- Run `flutter clean` and retry

### iOS Build Fails
- Check Xcode version (must be 15+)
- Check provisioning profile
- Verify signing in Xcode
- Run `flutter clean` and retry

## Deployment

### Android to Google Play
1. Upload .aab file to Google Play Console
2. Complete store listing
3. Submit for review

### iOS to App Store
1. Upload .ipa via Xcode or Transporter
2. Complete store listing
3. Submit for review
