!macro NSIS_HOOK_PREINSTALL
  DetailPrint "Terminating existing Dicty processes..."
  nsExec::Exec 'taskkill /F /IM dicty_engine.exe /T'
  nsExec::Exec 'taskkill /F /IM Dicty.exe /T'
  nsExec::Exec 'taskkill /F /IM dicty-client-tauri.exe /T'
  Sleep 1000
!macroend

!macro NSIS_HOOK_POSTINSTALL
  DetailPrint "Registering dicty:// URL protocol handler..."
  WriteRegStr HKCU "Software\Classes\dicty" "" "URL:Dicty Protocol"
  WriteRegStr HKCU "Software\Classes\dicty" "URL Protocol" ""
  WriteRegStr HKCU "Software\Classes\dicty\shell\open\command" "" '"$INSTDIR\Dicty.exe" "%1"'
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  DetailPrint "Terminating existing Dicty processes..."
  nsExec::Exec 'taskkill /F /IM dicty_engine.exe /T'
  nsExec::Exec 'taskkill /F /IM Dicty.exe /T'
  nsExec::Exec 'taskkill /F /IM dicty-client-tauri.exe /T'
  Sleep 1000
!macroend

!macro NSIS_HOOK_POSTUNINSTALL
  DetailPrint "Cleaning up Dicty user data, protocols, and webview cache..."
  DeleteRegKey HKCU "Software\Classes\dicty"
  RMDir /r "$LOCALAPPDATA\com.dicty.desktop"
  RMDir /r "$PROFILE\.dicty"
!macroend
