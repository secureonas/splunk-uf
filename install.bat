@echo off
:: Ensure the script is running with Administrative privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ERROR: This script must be run as an Administrator.
    pause
    exit /b 1
)

:: --- CONFIGURATION VARIABLES ---
set "SPLUNK_MSI=splunkforwarder-10.0.4-5ea723e837ec-windows-x64.msi"
set "SPLUNK_SERVER=10.220.64.10"
set "SPLUNK_DIR=C:\Program Files\SplunkUniversalForwarder"
set "SPLUNK_BIN=%SPLUNK_DIR%\bin\splunk.exe"

:: Verify the installer file actually exists in the current directory
if not exist "%SPLUNK_MSI%" (
    echo ERROR: %SPLUNK_MSI% not found in the current directory!
    exit /b 1
)

echo Installing Splunk Universal Forwarder...
:: Running msiexec with cleared syntax and proper quotes
msiexec.exe /i "%SPLUNK_MSI%" USE_LOCAL_SYSTEM=1 AGREETOLICENSE=Yes DEPLOYMENT_SERVER="%SPLUNK_SERVER%:8089" INSTALLDIR="%SPLUNK_DIR%" /quiet /L*v install_log.txt

if %errorlevel% equ 0 (
    echo Installation success!
    
    echo Restarting Splunk Service to apply changes...
    "%SPLUNK_BIN%" restart --accept-license --answer-yes --no-prompt
    
    echo Updating Splunk Windows Service Configurations...
    :: Set service to Delayed Start
    sc config SplunkForwarder start=delayed-auto
    
    :: Set recovery actions (Restart service after 1 minute on 1st/2nd failures)
    sc failure SplunkForwarder actions=restart/60000/restart/60000/""/60000 reset=86400
    
    echo Configuration update complete.
) else (
    echo ERROR: File %SPLUNK_MSI% installation failed with exit code %errorlevel%!
    echo Check install_log.txt for details.
)

echo.