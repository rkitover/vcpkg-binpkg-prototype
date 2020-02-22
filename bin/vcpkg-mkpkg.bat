@echo off

set pwsh=pwsh

where pwsh >nul 2>nul
if %ERRORLEVEL% NEQ 0 set pwsh=powershell.exe

set script_dir=%~dp0

%pwsh% -ExecutionPolicy RemoteSigned -NoProfile -NoLogo -NonInteractive -Command Import-Module %script_dir%../vcpkg-binpkg.psm1; vcpkg-mkpkg %*
