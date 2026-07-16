@echo off
setlocal DisableDelayedExpansion

:: Setup Colors for Windows 10/11 cmd
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "Green=%ESC%[92m"
set "Yellow=%ESC%[93m"
set "Blue=%ESC%[96m"
set "Reset=%ESC%[0m"

title Tiny11 Image Creator

:: Check for Administrator Privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo %Yellow%This script requires Administrator privileges.%Reset%
    echo %Blue%Please right-click and run as Administrator.%Reset%
    pause
    exit /b
)

echo %Green%Welcome to the Tiny11 Image Creator!%Reset%
echo.

:: Set Scratch Disk (Default to current directory)
set "ScratchDisk=%~dp0"
:: Remove trailing backslash for consistency
if "%ScratchDisk:~-1%"=="\" set "ScratchDisk=%ScratchDisk:~0,-1%"
echo %Blue%Scratch disk set to: %ScratchDisk%%Reset%
echo.

:: XML Selection Prompt
:SelectXML
echo %Blue%Which Autounattend.xml do you want to inject?%Reset%
echo %Yellow%1. Disk 0 Format%Reset%
echo %Yellow%2. Manual Disk Selection%Reset%
set /p xmlChoice="%Yellow%Enter your choice (1 or 2): %Reset%"

if "%xmlChoice%"=="1" (
    set "SelectedXML=Disk 0 Format.xml"
) else if "%xmlChoice%"=="2" (
    set "SelectedXML=Manual Disk Selection.xml"
) else (
    echo %Yellow%Invalid selection. Please try again.%Reset%
    goto SelectXML
)
echo %Green%Selected: %SelectedXML%%Reset%
echo.

:: Check and Download Required Files
:CheckFiles
set "MissingFiles=0"
if not exist "%~dp0Disk 0 Format.xml" set "MissingFiles=1"
if not exist "%~dp0Manual Disk Selection.xml" set "MissingFiles=1"
if not exist "%~dp0oscdimg.exe" set "MissingFiles=1"

if "%MissingFiles%"=="1" (
    :: Internet Connection Check
    ping -n 1 8.8.8.8 >nul 2>&1
    if errorlevel 1 (
        echo %Yellow%Required files are missing and no internet connection detected.%Reset%
        echo %Blue%Please connect to the internet and press any key to try again.%Reset%
        pause >nul
        goto CheckFiles
    )
    
    echo %Blue%Downloading required files...%Reset%
    
    if not exist "%~dp0Disk 0 Format.xml" (
        echo %Blue%Downloading Disk 0 Format.xml...%Reset%
        curl -sL -o "%~dp0Disk 0 Format.xml" "https://raw.githubusercontent.com/windowslitex/Lite11/main/Disk%%200%%20Format.xml"
    )
    if not exist "%~dp0Manual Disk Selection.xml" (
        echo %Blue%Downloading Manual Disk Selection.xml...%Reset%
        curl -sL -o "%~dp0Manual Disk Selection.xml" "https://raw.githubusercontent.com/windowslitex/Lite11/main/Manual%%20Disk%%20Selection.xml"
    )
    if not exist "%~dp0oscdimg.exe" (
        echo %Blue%Downloading oscdimg.exe...%Reset%
        curl -sL -o "%~dp0oscdimg.exe" "https://raw.githubusercontent.com/windowslitex/Lite11/main/oscdimg.exe"
    )
    echo %Green%Files downloaded successfully.%Reset%
) else (
    echo %Green%All required dependency files are present locally.%Reset%
)
echo.

:: Get Target Drive
:GetDrive
set /p DriveLetter="%Yellow%Please enter the drive letter for the Windows 11 image (e.g., D): %Reset%"
if not exist "%DriveLetter%:\sources" (
    echo %Yellow%Cannot find Windows OS Installation files in %DriveLetter%:\%Reset%
    goto GetDrive
)
set "DriveLetter=%DriveLetter%:"
echo %Green%Drive letter set to %DriveLetter%%Reset%
echo.

:: Setup Directories (Using New Folder Names)
if not exist "%ScratchDisk%\ISO-WorkSpace\sources" mkdir "%ScratchDisk%\ISO-WorkSpace\sources"

:: Check ESD / WIM and Convert if needed
if not exist "%DriveLetter%\sources\install.wim" (
    if exist "%DriveLetter%\sources\install.esd" (
        echo %Blue%Found install.esd, preparing to convert to install.wim...%Reset%
        dism /Get-WimInfo /WimFile:"%DriveLetter%\sources\install.esd"
        set /p WimIndex="%Yellow%Please enter the image index to convert: %Reset%"
        echo %Blue%Converting install.esd to install.wim. This may take a while...%Reset%
        dism /Export-Image /SourceImageFile:"%DriveLetter%\sources\install.esd" /SourceIndex:%WimIndex% /DestinationImageFile:"%ScratchDisk%\ISO-WorkSpace\sources\install.wim" /Compress:max /CheckIntegrity
        echo %Green%Conversion complete!%Reset%
    ) else (
        echo %Yellow%Cannot find install.wim or install.esd in the specified drive.%Reset%
        pause
        exit /b
    )
) else (
    dism /Get-WimInfo /WimFile:"%DriveLetter%\sources\install.wim"
    set /p WimIndex="%Yellow%Please enter the image index you want to modify: %Reset%"
)

echo %Blue%Copying Windows image contents (Excluding ESD if present)...%Reset%
xcopy "%DriveLetter%\*" "%ScratchDisk%\ISO-WorkSpace\" /E /I /H /Y >nul 2>&1
if exist "%ScratchDisk%\ISO-WorkSpace\sources\install.esd" del /f /q "%ScratchDisk%\ISO-WorkSpace\sources\install.esd"
echo %Green%Copy complete!%Reset%
timeout /t 2 >nul
cls

:: Get Dynamic Name and Date for ISO
echo %Blue%Retrieving index name for final ISO dynamically...%Reset%
for /f "delims=" %%I in ('powershell -NoProfile -Command "(Get-WindowsImage -ImagePath '%ScratchDisk%\ISO-WorkSpace\sources\install.wim' -Index %WimIndex%).ImageName"') do set "ImageName=%%I"
for /f "delims=" %%D in ('powershell -NoProfile -Command "Get-Date -Format 'MMMM dd, yyyy'"') do set "TodayDate=%%D"
set "FinalIsoName=%ImageName% Lite - %TodayDate%.iso"
echo %Green%Final ISO will be named: %FinalIsoName%%Reset%
echo.

echo %Blue%Mounting Windows image. This may take a while...%Reset%
if not exist "%ScratchDisk%\Index-WorkSpace" mkdir "%ScratchDisk%\Index-WorkSpace"
attrib -R "%ScratchDisk%\ISO-WorkSpace\sources\install.wim" >nul 2>&1
dism /Mount-Image /ImageFile:"%ScratchDisk%\ISO-WorkSpace\sources\install.wim" /Index:%WimIndex% /MountDir:"%ScratchDisk%\Index-WorkSpace"
echo %Green%Mounting complete!%Reset%

echo %Blue%Performing removal of bloatware applications...%Reset%
powershell -NoProfile -Command "$packages = (Get-AppxProvisionedPackage -Path '%ScratchDisk%\Index-WorkSpace').PackageName; $prefixes = 'Clipchamp.Clipchamp_','Microsoft.BingNews_','Microsoft.BingWeather_','Microsoft.GamingApp_','Microsoft.GetHelp_','Microsoft.Getstarted_','Microsoft.MicrosoftOfficeHub_','Microsoft.MicrosoftSolitaireCollection_','Microsoft.People_','Microsoft.PowerAutomateDesktop_','Microsoft.Todos_','Microsoft.WindowsAlarms_','microsoft.windowscommunicationsapps_','Microsoft.WindowsFeedbackHub_','Microsoft.WindowsMaps_','Microsoft.WindowsSoundRecorder_','Microsoft.Xbox.TCUI_','Microsoft.XboxGamingOverlay_','Microsoft.XboxGameOverlay_','Microsoft.XboxSpeechToTextOverlay_','Microsoft.YourPhone_','Microsoft.ZuneMusic_','Microsoft.ZuneVideo_','MicrosoftCorporationII.MicrosoftFamily_','MicrosoftCorporationII.QuickAssist_','MicrosoftTeams_','Microsoft.549981C3F5F10_','Microsoft.Windows.Copilot','MSTeams_','Microsoft.OutlookForWindows_','Microsoft.Windows.Teams_','Microsoft.Copilot_'; foreach ($pkg in $packages) { foreach ($prefix in $prefixes) { if ($pkg -like """$prefix*""") { Write-Host 'Removing' $pkg; Remove-AppxProvisionedPackage -Path '%ScratchDisk%\Index-WorkSpace' -PackageName $pkg >$null } } }"

echo %Blue%Removing OneDrive setup...%Reset%
takeown /f "%ScratchDisk%\Index-WorkSpace\Windows\System32\OneDriveSetup.exe" >nul 2>&1
icacls "%ScratchDisk%\Index-WorkSpace\Windows\System32\OneDriveSetup.exe" /grant administrators:F /T /C >nul 2>&1
del /f /q "%ScratchDisk%\Index-WorkSpace\Windows\System32\OneDriveSetup.exe" >nul 2>&1
echo %Green%Removal complete!%Reset%
timeout /t 2 >nul
cls

echo %Blue%Loading registry...%Reset%
reg load HKLM\zCOMPONENTS "%ScratchDisk%\Index-WorkSpace\Windows\System32\config\COMPONENTS" >nul 2>&1
reg load HKLM\zDEFAULT "%ScratchDisk%\Index-WorkSpace\Windows\System32\config\default" >nul 2>&1
reg load HKLM\zNTUSER "%ScratchDisk%\Index-WorkSpace\Users\Default\ntuser.dat" >nul 2>&1
reg load HKLM\zSOFTWARE "%ScratchDisk%\Index-WorkSpace\Windows\System32\config\SOFTWARE" >nul 2>&1
reg load HKLM\zSYSTEM "%ScratchDisk%\Index-WorkSpace\Windows\System32\config\SYSTEM" >nul 2>&1

echo %Blue%Applying Registry Tweaks (Bypassing requirements, Disabling Telemetry, etc)...%Reset%
reg add "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache" /v "SV1" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache" /v "SV2" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache" /v "SV1" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache" /v "SV2" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassCPUCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassRAMCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassSecureBootCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassStorageCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassTPMCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\MoSetup" /v "AllowUpgradesWithUnsupportedTPMOrCPU" /t REG_DWORD /d 1 /f >nul

reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "OemPreInstalledAppsEnabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEnabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SilentInstalledAppsEnabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableWindowsConsumerFeatures" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "ContentDeliveryAllowed" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start" /v "ConfigureStartPins" /t REG_SZ /d "{\"pinnedList\": [{}]}" /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "FeatureManagementEnabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "PreInstalledAppsEverEnabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SoftLandingEnabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SubscribedContentEnabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v "SystemPaneSuggestionsEnabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall" /v "DisablePushToInstall" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\MRT" /v "DontOfferThroughWUAU" /t REG_DWORD /d 1 /f >nul
reg delete "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions" /f >nul 2>&1
reg delete "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps" /f >nul 2>&1
reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableConsumerAccountStateContent" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent" /v "DisableCloudOptimizedContent" /t REG_DWORD /d 1 /f >nul

reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v "BypassNRO" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager" /v "ShippedWithReserves" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zSYSTEM\ControlSet001\Control\BitLocker" /v "PreventDeviceEncryption" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat" /v "ChatIcon" /t REG_DWORD /d 3 /f >nul
reg add "HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v "TaskbarMn" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" /v "DisableFileSyncNGSC" /t REG_DWORD /d 1 /f >nul

reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v "Enabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy" /v "TailoredExperiencesWithDiagnosticDataEnabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" /v "HasAccepted" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Input\TIPC" /v "Enabled" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\InputPersonalization" /v "RestrictImplicitInkCollection" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\InputPersonalization" /v "RestrictImplicitTextCollection" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore" /v "HarvestContacts" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Software\Microsoft\Personalization\Settings" /v "AcceptedPrivacyPolicy" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection" /v "AllowTelemetry" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice" /v "Start" /t REG_DWORD /d 4 /f >nul

reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate" /v "workCompleted" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate" /v "workCompleted" /t REG_DWORD /d 1 /f >nul
reg delete "HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate" /f >nul 2>&1
reg delete "HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate" /f >nul 2>&1

reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" /v "TurnOffWindowsCopilot" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer" /v "DisableSearchBoxSuggestions" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\Teams" /v "DisableInstallation" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail" /v "PreventRun" /t REG_DWORD /d 1 /f >nul

echo %Blue%Deleting scheduled task definition files...%Reset%
set "tasksPath=%ScratchDisk%\Index-WorkSpace\Windows\System32\Tasks"
rmdir /s /q "%tasksPath%\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" >nul 2>&1
rmdir /s /q "%tasksPath%\Microsoft\Windows\Customer Experience Improvement Program" >nul 2>&1
rmdir /s /q "%tasksPath%\Microsoft\Windows\Application Experience\ProgramDataUpdater" >nul 2>&1
rmdir /s /q "%tasksPath%\Microsoft\Windows\Chkdsk\Proxy" >nul 2>&1
rmdir /s /q "%tasksPath%\Microsoft\Windows\Windows Error Reporting\QueueReporting" >nul 2>&1
echo %Green%Tasks deleted.%Reset%

echo %Blue%Unmounting Registry...%Reset%
reg unload HKLM\zCOMPONENTS >nul 2>&1
reg unload HKLM\zDEFAULT >nul 2>&1
reg unload HKLM\zNTUSER >nul 2>&1
reg unload HKLM\zSOFTWARE >nul 2>&1
reg unload HKLM\zSYSTEM >nul 2>&1

echo %Blue%Cleaning up image (StartComponentCleanup -ResetBase)...%Reset%
dism /Image:"%ScratchDisk%\Index-WorkSpace" /Cleanup-Image /StartComponentCleanup /ResetBase
echo %Green%Cleanup complete.%Reset%

echo %Blue%Unmounting install.wim and saving changes...%Reset%
dism /Unmount-Image /MountDir:"%ScratchDisk%\Index-WorkSpace" /Commit
echo %Green%Windows install.wim processed. Continuing with boot.wim.%Reset%
timeout /t 2 >nul
cls

echo %Blue%Mounting boot image...%Reset%
attrib -R "%ScratchDisk%\ISO-WorkSpace\sources\boot.wim" >nul 2>&1
dism /Mount-Image /ImageFile:"%ScratchDisk%\ISO-WorkSpace\sources\boot.wim" /Index:2 /MountDir:"%ScratchDisk%\Index-WorkSpace"

echo %Blue%Loading registry from Boot.wim...%Reset%
reg load HKLM\zCOMPONENTS "%ScratchDisk%\Index-WorkSpace\Windows\System32\config\COMPONENTS" >nul 2>&1
reg load HKLM\zDEFAULT "%ScratchDisk%\Index-WorkSpace\Windows\System32\config\default" >nul 2>&1
reg load HKLM\zNTUSER "%ScratchDisk%\Index-WorkSpace\Users\Default\ntuser.dat" >nul 2>&1
reg load HKLM\zSOFTWARE "%ScratchDisk%\Index-WorkSpace\Windows\System32\config\SOFTWARE" >nul 2>&1
reg load HKLM\zSYSTEM "%ScratchDisk%\Index-WorkSpace\Windows\System32\config\SYSTEM" >nul 2>&1

echo %Blue%Bypassing system requirements on the setup image...%Reset%
reg add "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache" /v "SV1" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache" /v "SV2" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache" /v "SV1" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache" /v "SV2" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassCPUCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassRAMCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassSecureBootCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassStorageCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\LabConfig" /v "BypassTPMCheck" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\zSYSTEM\Setup\MoSetup" /v "AllowUpgradesWithUnsupportedTPMOrCPU" /t REG_DWORD /d 1 /f >nul
echo %Green%Tweaking complete!%Reset%

echo %Blue%Unmounting Registry...%Reset%
reg unload HKLM\zCOMPONENTS >nul 2>&1
reg unload HKLM\zDEFAULT >nul 2>&1
reg unload HKLM\zNTUSER >nul 2>&1
reg unload HKLM\zSOFTWARE >nul 2>&1
reg unload HKLM\zSYSTEM >nul 2>&1

echo %Blue%Unmounting boot image...%Reset%
dism /Unmount-Image /MountDir:"%ScratchDisk%\Index-WorkSpace" /Commit
cls

echo %Blue%Setting up Autounattend.xml in ISO and $OEM$ folder...%Reset%
if not exist "%ScratchDisk%\ISO-WorkSpace\$OEM$" mkdir "%ScratchDisk%\ISO-WorkSpace\$OEM$"

:: Delete existing XML files if they are already present
if exist "%ScratchDisk%\ISO-WorkSpace\autounattend.xml" (
    echo %Yellow%Found existing autounattend.xml in ISO root. Deleting it...%Reset%
    del /f /q "%ScratchDisk%\ISO-WorkSpace\autounattend.xml" >nul 2>&1
)
if exist "%ScratchDisk%\ISO-WorkSpace\$OEM$\autounattend.xml" (
    echo %Yellow%Found existing autounattend.xml in $OEM$ folder. Deleting it...%Reset%
    del /f /q "%ScratchDisk%\ISO-WorkSpace\$OEM$\autounattend.xml" >nul 2>&1
)

copy /y "%~dp0%SelectedXML%" "%ScratchDisk%\ISO-WorkSpace\autounattend.xml" >nul 2>&1
copy /y "%~dp0%SelectedXML%" "%ScratchDisk%\ISO-WorkSpace\$OEM$\autounattend.xml" >nul 2>&1
echo %Green%XML applied successfully!%Reset%

echo %Blue%Creating ISO image...%Reset%
"%~dp0oscdimg.exe" -m -o -u2 -udfver102 -bootdata:2#p0,e,b"%ScratchDisk%\ISO-WorkSpace\boot\etfsboot.com"#pEF,e,b"%ScratchDisk%\ISO-WorkSpace\efi\microsoft\boot\efisys.bin" "%ScratchDisk%\ISO-WorkSpace" "%ScratchDisk%\%FinalIsoName%"

echo %Blue%Performing Cleanup...%Reset%
rmdir /s /q "%ScratchDisk%\ISO-WorkSpace" >nul 2>&1
rmdir /s /q "%ScratchDisk%\Index-WorkSpace" >nul 2>&1

echo %Green%Creation completed! ISO File Created: "%ScratchDisk%\%FinalIsoName%"%Reset%
echo.
pause
exit