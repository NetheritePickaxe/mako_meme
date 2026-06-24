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

[Languages]
Name: "chinesesimplified"; MessagesFile: "Languages\ChineseSimplified.isl"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Tasks]
Name: desktopicon; Description: "创建桌面快捷方式(&D)"; GroupDescription: "附加图标："; Flags: checkedonce

[Icons]
Name: "{userdesktop}\Mako Meme"; Filename: "{app}\mako_meme.exe"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon
Name: "{group}\Mako Meme"; Filename: "{app}\mako_meme.exe"
Name: "{group}\卸载 Mako Meme"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\mako_meme.exe"; Description: "启动 Mako Meme"; Flags: postinstall nowait skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
Type: filesandordirs; Name: "{group}"

[Code]
var
  DeleteDataPage: TInputOptionWizardPage;

function InitializeUninstall: Boolean;
begin
  DeleteDataPage := CreateInputOptionPage(
    -1,
    '删除应用数据',
    '是否同时删除所有表情包数据？',
    '此操作不可撤销。',
    True,
    False
  );
  DeleteDataPage.Add('删除所有应用数据（表情包、标签、分类）');
  DeleteDataPage.Values[0] := False;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataPath: string;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if DeleteDataPage.Values[0] then
    begin
      DataPath := ExpandConstant('{userdocs}\mako_meme');
      if DirExists(DataPath) then
        DelTree(DataPath, True, True, True);
    end;
  end;
end;