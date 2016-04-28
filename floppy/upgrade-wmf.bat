:::::::
:: Script pulled from:
:: https://blogs.technet.microsoft.com/pstips/2015/04/11/powershell-4-0-deployment/
:::::::
@echo off
title %~nx0
cls


set "outputFolder=%TEMP%"
if /i not exist "%outputFolder%" md "%outputFolder%"
>> "%outputFolder%\%~n0.log" 2>&1 (
call :START ) & endlocal & goto:eof


:START
echo %date% %time% - %~nx0 started
if /i "%PROCESSOR_ARCHITECTURE%"=="x86" (
    if not defined PROCESSOR_ARCHITEW6432 (
        set BITNESS=x86
    ) else (
        set BITNESS=x64
    )
) else (
    set BITNESS=x64
)


:NETFX45
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\.NETFramework\v4.0.30319\SKUs\.NETFramework,Version=v4.5" 2>NUL
if %ERRORLEVEL% equ 0 (
    echo .NET Framework 4.5 is already installed
    goto WMF4
)
echo Downloading .NET Framework 4.5 Offline Installer...
powershell.exe -File A:\wget.ps1 https://download.microsoft.com/download/E/2/1/E21644B5-2DF2-47C2-91BD-63C560427900/NDP452-KB2901907-x86-x64-AllOS-ENU.exe %outputFolder%\NDP452-KB2901907-x86-x64-AllOS-ENU.exe

echo Installing .NET Framework 4.5
start /wait %outputFolder%\NDP452-KB2901907-x86-x64-AllOS-ENU.exe /q /log %outputFolder%\netfx45.htm /norestart%
if %ERRORLEVEL% equ 0 goto WMF4
:: ERROR_SUCCESS_REBOOT_INITIATED
if %ERRORLEVEL% equ 1641 goto WMF4
:: ERROR_SUCCESS_REBOOT_REQUIRED
if %ERRORLEVEL% equ 3010 (
    goto WMF4
) else (
    echo There was an error [%ERRORLEVEL%] during the .NET Framework 4.5 installation
    echo Check the logs for more details
    echo Windows Management Framework 4.0 installation aborted!
    goto EXIT
)


:WMF4
reg query "HKLM\SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine" /v PowerShellVersion 2>&1 | find "4.0" 2>&1>NUL
if %ERRORLEVEL% equ 0 (
    echo Windows Management Framework 4.0 is already installed
    goto EXIT
)

echo Downloaing Windows Management Framwork 4.0 (%BITNESS%)
powershell.exe -File A:\wget.ps1 https://download.microsoft.com/download/3/D/6/3D61D262-8549-4769-A660-230B67E15B25/Windows6.1-KB2819745-%BITNESS%-MultiPkg.msu %outputFolder%/Windows6.1-KB2819745-%BITNESS%-MultiPkg.msu
echo Installing Windows Management Framework 4.0 (%BITNESS%)
start /wait wusa.exe %outputFolder%/Windows6.1-KB2819745-%BITNESS%-MultiPkg.msu /quiet /norestart
if %ERRORLEVEL% equ 0 (
    echo Windows Management Framework 4.0 installed successfully
    goto EXIT
)
:: ERROR_SUCCESS_REBOOT_REQUIRED
if %ERRORLEVEL% equ 3010 (
    echo Windows Management Framework 4.0 installed successfully - restart required
    goto EXIT
)
:: WU_S_ALREADY_INSTALLED
if %ERRORLEVEL% equ 2359302 (
    echo Windows Management Framework 4.0 is already installed
) else (
    echo There was an error [%ERRORLEVEL%] during the Windows Management Framework 4.0 installation
    echo Check the logs for more details
)


:EXIT
echo. & echo %date% %time% - %~nx0 ended & echo.
