@echo off
echo ========================================
echo   IoT Enhanced Flutter App
echo ========================================
echo.

cd app_flutter

echo Checking Flutter...
flutter --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Flutter not found!
    echo Please install Flutter from: https://flutter.dev/
    echo.
    pause
    exit /b 1
)

echo Flutter found!
echo.

echo Getting dependencies...
call flutter pub get
echo.

echo Starting Flutter app on Chrome...
echo.
echo App will open in Chrome browser
echo Press Ctrl+C to stop
echo.

flutter run -d chrome -t lib/main.dart
