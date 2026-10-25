!include "MUI2.nsh"

!ifndef APP_VERSION
  !define APP_VERSION "1.0.2.3"
!endif

Name "DropDial"
Caption "DropDial Setup"

!ifndef OUT_FILE
  !ifdef $%OS%
    !define OUT_FILE "website\downloads\DropDial-Setup.exe"
  !else
    !define OUT_FILE "website/downloads/DropDial-Setup.exe"
  !endif
!endif
OutFile "${OUT_FILE}"

InstallDir "$LOCALAPPDATA\Programs\DropDial"
InstallDirRegKey HKCU "Software\DropDial" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma

; UI Settings
!define MUI_ABORTWARNING
!ifdef $%OS%
  !define MUI_ICON "work\DropDial\assets\dropdial.ico"
  !define MUI_UNICON "work\DropDial\assets\dropdial.ico"
!else
  !define MUI_ICON "work/DropDial/assets/dropdial.ico"
  !define MUI_UNICON "work/DropDial/assets/dropdial.ico"
!endif

; Pages
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_RUN "$INSTDIR\DropDial.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch DropDial now"
!insertmacro MUI_PAGE_FINISH

; Uninstaller Pages
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Languages
!insertmacro MUI_LANGUAGE "English"

Section "MainSection" SEC01
  ; Close existing running instance if any
  ExecWait 'taskkill /F /IM DropDial.exe'
  Sleep 500

  SetOutPath "$INSTDIR"
  SetOverwrite on

  ; Copy all files recursively from outputs/DropDial
  !ifdef SOURCE_DIR
    !ifdef $%OS%
      File /r "${SOURCE_DIR}\*.*"
    !else
      File /r "${SOURCE_DIR}/*.*"
    !endif
  !else
    !ifdef $%OS%
      File /r "outputs\DropDial\*.*"
    !else
      File /r "outputs/DropDial/*.*"
    !endif
  !endif

  ; Store installation folder
  WriteRegStr HKCU "Software\DropDial" "InstallDir" "$INSTDIR"

  ; Create uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Shortcuts
  CreateDirectory "$SMPROGRAMS\DropDial"
  CreateShortcut "$SMPROGRAMS\DropDial\DropDial.lnk" "$INSTDIR\DropDial.exe" "" "$INSTDIR\DropDial.exe" 0
  CreateShortcut "$SMPROGRAMS\DropDial\Uninstall DropDial.lnk" "$INSTDIR\Uninstall.exe" "" "$INSTDIR\Uninstall.exe" 0
  CreateShortcut "$DESKTOP\DropDial.lnk" "$INSTDIR\DropDial.exe" "" "$INSTDIR\DropDial.exe" 0

  ; Write registry keys for Windows Apps & Features
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial" "DisplayName" "DropDial"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial" "DisplayIcon" "$INSTDIR\DropDial.exe,0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial" "Publisher" "DropDial"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial" "HelpLink" "https://dropdial.app"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial" "URLInfoAbout" "https://dropdial.app"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial" "NoRepair" 1
SectionEnd

Section "Uninstall"
  ExecWait 'taskkill /F /IM DropDial.exe'
  Sleep 500

  ; Remove shortcuts
  Delete "$DESKTOP\DropDial.lnk"
  Delete "$SMPROGRAMS\DropDial\DropDial.lnk"
  Delete "$SMPROGRAMS\DropDial\Uninstall DropDial.lnk"
  RMDir "$SMPROGRAMS\DropDial"

  ; Remove installed files
  RMDir /r "$INSTDIR"

  ; Remove registry keys
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\DropDial"
  DeleteRegKey HKCU "Software\DropDial"
SectionEnd

