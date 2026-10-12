; Inno Setup script for the VerbNest Windows installer.
; Built by scripts/package_windows.sh, which passes the defines below:
;   -DAppVersion=<version> -DBuildNumber=<n> -DSourceDir=<Release dir>
;   -DOutputDir=<dir> -DOutputName=<file name without .exe>
; Per-user install by default (no admin prompt); the user can pick
; all-users in the wizard.

#ifndef AppVersion
  #error AppVersion is not defined
#endif

[Setup]
; AppId identifies the product for upgrades and uninstall; never change it.
AppId={{4831FE71-9D3A-4C42-B468-657CE7AA76F2}
AppName=VerbNest
AppVersion={#AppVersion}
AppVerName=VerbNest {#AppVersion}
VersionInfoVersion={#AppVersion}.{#BuildNumber}
AppPublisher=Omni
AppCopyright=Copyright (C) 2026 Omni. All rights reserved.
DefaultDirName={autopf}\VerbNest
DefaultGroupName=VerbNest
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\..\apps\verbnest_app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\verbnest_app.exe
UninstallDisplayName=VerbNest
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\VerbNest"; Filename: "{app}\verbnest_app.exe"
Name: "{autodesktop}\VerbNest"; Filename: "{app}\verbnest_app.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\verbnest_app.exe"; Description: "{cm:LaunchProgram,VerbNest}"; Flags: nowait postinstall skipifsilent
