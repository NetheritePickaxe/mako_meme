[Setup]
AppName=Mako Meme
AppVersion=1.0.0
AppPublisher=Mako Meme
AppPublisherURL=https://github.com/NetheritePickaxe/mako_meme
AppSupportURL=https://github.com/NetheritePickaxe/mako_meme/issues
AppUpdatesURL=https://github.com/NetheritePickaxe/mako_meme/releases
DefaultDirName={autopf}\Mako Meme
DefaultGroupName=Mako Meme
OutputDir=..\build\windows\x64\runner\Release
OutputBaseFilename=mako_meme-1.0.0-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
DisableReadyPage=no
AllowNoIcons=yes
DisableProgramGroupPage=no

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Tasks]
Name: desktopicon; Description: "Create desktop shortcut"; GroupDescription: "Additional tasks:"; Flags: checkedonce

[Icons]
Name: "{userdesktop}\Mako Meme"; Filename: "{app}\mako_meme.exe"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon
Name: "{group}\Mako Meme"; Filename: "{app}\mako_meme.exe"
Name: "{group}\Uninstall Mako Meme"; Filename: "{uninstallexe}"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{group}"
