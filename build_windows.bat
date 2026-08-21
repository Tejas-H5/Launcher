@echo off

SET VERSION=v0.0.1

SET OUTPUT_DIR=build\windows\output
SET BUILDS_DIR=build\windows\

rmdir /s /q %OUTPUT_DIR%
md %OUTPUT_DIR%
if %errorlevel% neq 0 (
    echo Removal failed withe error %errorlevel%
    exit /b %errorlevel%
)

odin build . -o:speed -subsystem:windows -out:%OUTPUT_DIR%\launcher.exe
if %errorlevel% neq 0 (
    echo Build failed with error %errorlevel%
    exit /b %errorlevel%
)

del /s /q "%BUILDS_DIR%\launcher-windows-%VERSION%.zip"
if %errorlevel% neq 0 (
    echo Removing the archive failed with error %errorlevel%
    exit /b %errorlevel%
)

powershell -C "Compress-Archive -Path %OUTPUT_DIR% -DestinationPath %BUILDS_DIR%\launcher-windows-%VERSION%.zip"
if %errorlevel% neq 0 (
    echo Zipping failed with error %errorlevel%
    exit /b %errorlevel%
)
