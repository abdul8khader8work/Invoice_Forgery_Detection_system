# Script to build Windows MSIX package with Auto-Update support
# Run this script from the frontend directory
# Auto-update URL: Configure in pubspec.yaml under msix_config

param(
    [string]$Version = "1.0.0",
    [string]$UpdateUrl = "",
    [switch]$SkipAutoUpdate = $false
)

Write-Host "=== Building Windows MSIX Package ===" -ForegroundColor Yellow
Write-Host "Version: $Version" -ForegroundColor Cyan
if (-not $SkipAutoUpdate -and $UpdateUrl) {
    Write-Host "Auto-update URL: $UpdateUrl" -ForegroundColor Cyan
}
Write-Host ""

# Step 1: Update version in pubspec.yaml if provided
if ($Version -ne "1.0.0") {
    Write-Host "Step 1: Updating version to $Version..." -ForegroundColor Cyan
    $pubspecPath = "pubspec.yaml"
    $pubspecContent = Get-Content $pubspecPath -Raw
    
    # Update version line
    $pubspecContent = $pubspecContent -replace "version: .*", "version: $Version"
    
    Set-Content $pubspecPath $pubspecContent
    Write-Host "Version updated to $Version" -ForegroundColor Green
} else {
    Write-Host "Step 1: Using existing version from pubspec.yaml" -ForegroundColor Cyan
}

# Step 2: Configure auto-update in pubspec.yaml if URL provided
if (-not $SkipAutoUpdate -and $UpdateUrl) {
    Write-Host "Step 2: Configuring auto-update..." -ForegroundColor Cyan
    $pubspecPath = "pubspec.yaml"
    $pubspecContent = Get-Content $pubspecPath -Raw
    
    # Check if msix_config exists
    if ($pubspecContent -match "msix_config:") {
        # Add/update update URL
        if ($pubspecContent -match "update_url:") {
            $pubspecContent = $pubspecContent -replace "update_url: .*", "update_url: $UpdateUrl"
        } else {
            # Insert update_url after msix_config:
            $pubspecContent = $pubspecContent -replace "(msix_config:)", "`$1`n    update_url: $UpdateUrl"
        }
        
        Set-Content $pubspecPath $pubspecContent
        Write-Host "Auto-update configured" -ForegroundColor Green
    } else {
        Write-Host "Warning: msix_config not found in pubspec.yaml" -ForegroundColor Yellow
    }
}

# Step 3: Get dependencies
Write-Host "Step 3: Getting dependencies..." -ForegroundColor Cyan
flutter pub get

# Step 4: Build Windows release
Write-Host "Step 4: Building Windows release..." -ForegroundColor Cyan
flutter build windows --release

if ($LASTEXITCODE -ne 0) {
    Write-Host "Windows build failed!" -ForegroundColor Red
    exit 1
}

# Step 5: Create MSIX package
Write-Host "Step 5: Creating MSIX package..." -ForegroundColor Cyan
flutter pub run msix:create

if ($LASTEXITCODE -ne 0) {
    Write-Host "MSIX package creation failed!" -ForegroundColor Red
    exit 1
}

# Step 6: Generate update manifest (for auto-update)
if (-not $SkipAutoUpdate) {
    Write-Host "Step 6: Generating update manifest..." -ForegroundColor Cyan
    
    $buildDir = "build/windows/x64/runner/Release"
    $msixFile = Get-ChildItem -Path $buildDir -Filter "*.msix" | Select-Object -First 1
    
    if ($msixFile) {
        $manifest = @{
            version = $Version
            file_name = $msixFile.Name
            file_size = $msixFile.Length
            checksum = (Get-FileHash $msixFile.FullName -Algorithm SHA256).Hash
            release_date = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            mandatory = $false
            release_notes = "Auto-generated release"
        } | ConvertTo-Json
        
        $manifestPath = "$buildDir/update_manifest.json"
        $manifest | Out-File $manifestPath
        Write-Host "Update manifest created: $manifestPath" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "MSIX package location: build/windows/x64/runner/Release/" -ForegroundColor Yellow
Write-Host ""
Write-Host "To install:" -ForegroundColor Cyan
Write-Host "  1. Right-click the .msix file"
Write-Host "  2. Select 'Install'"
Write-Host "  3. Follow the prompts" -ForegroundColor Yellow
Write-Host ""
if (-not $SkipAutoUpdate -and $UpdateUrl) {
    Write-Host "Auto-update configured!" -ForegroundColor Green
    Write-Host "Update URL: $UpdateUrl" -ForegroundColor Cyan
    Write-Host "Upload update_manifest.json and .msix to the update server" -ForegroundColor Yellow
}
