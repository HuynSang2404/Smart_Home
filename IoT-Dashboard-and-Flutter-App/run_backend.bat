@echo off
echo ========================================
echo   IoT Enhanced Backend Server
echo ========================================
echo.

cd backend

echo Checking Node.js...
node --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: Node.js not found!
    echo Please install Node.js from: https://nodejs.org/
    echo.
    pause
    exit /b 1
)

echo Node.js found!
echo.

echo Checking dependencies...
if not exist "node_modules" (
    echo Installing dependencies...
    call npm install
    echo.
)

echo Checking .env file...
if not exist ".env" (
    echo WARNING: .env file not found!
    echo Copying .env.example to .env...
    copy .env.example .env
    echo.
    echo IMPORTANT: Please edit .env file with your Supabase credentials!
    echo Press any key to open .env file...
    pause >nul
    notepad .env
    echo.
)

echo Starting backend server...
echo.
echo Backend will run on: http://localhost:8080
echo Health check: http://localhost:8080/health
echo.
echo Press Ctrl+C to stop server
echo.

npm start
