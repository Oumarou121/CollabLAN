; Installateur Windows de LocaLink (Inno Setup 6).
;
; Compile par le workflow GitHub (.github/workflows/build.yml) a partir du
; dossier deploye (windeployqt + runtime Visual C++) :
;   iscc /DAppVersion=1.0.42 /DSourceDir=<dossier deploye> /DOutputDir=<sortie> LocaLink.iss
;
; - installation pour tous les utilisateurs (Program Files), raccourcis menu
;   Demarrer et bureau (optionnel) ;
; - regle du pare-feu Windows pour LocaLink.exe : sans elle, Windows bloque ou
;   demande l'autorisation au premier lancement, et les autres postes ne
;   decouvrent pas celui-ci ;
; - une nouvelle version remplace la precedente (meme AppId) ; LocaLink est
;   ferme s'il tourne ;
; - la desinstallation retire le programme et la regle du pare-feu, pas les
;   donnees de l'utilisateur (%APPDATA%\LocaLink).

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist\LocaLink"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

#define AppName "LocaLink"
#define AppExe "LocaLink.exe"

[Setup]
; Identifiant fixe : ne jamais le changer, il relie les versions entre elles.
AppId={{6F3C2B8E-4D1A-4E7B-9C55-2A1F0D8B7E43}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=LocaLink
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
; Droits administrateur : installation dans Program Files et regle de pare-feu.
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Qt 6 : Windows 10 1809 (build 17763) ou plus recent.
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=LocaLink-Setup-{#AppVersion}
SetupIconFile={#SourceDir}\app.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
; Regle de pare-feu (tous profils : un reseau domestique est souvent classe
; « public » par Windows). Les postes LocaLink s'authentifient entre eux (TLS).
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#AppName}"""; Flags: runhidden; StatusMsg: "Configuration du pare-feu..."
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#AppName}"" dir=in action=allow program=""{app}\{#AppExe}"" enable=yes profile=any"; Flags: runhidden
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#AppName}"""; Flags: runhidden; RunOnceId: "FirewallRule"
