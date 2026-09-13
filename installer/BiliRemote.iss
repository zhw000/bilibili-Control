#define AppVersion "0.2.0"
[Setup]
AppId={{D09A7BB9-AF35-49C9-9A6E-9E11B42C81CF}
AppName=哔哩遥控
AppVersion={#AppVersion}
AppPublisher=Bili Remote
DefaultDirName={localappdata}\Programs\BiliRemote
DefaultGroupName=哔哩遥控
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\artifacts
OutputBaseFilename=BiliRemote-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\BiliRemote.exe
CloseApplications=yes
[Files]
Source: "..\artifacts\windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\哔哩遥控"; Filename: "{app}\BiliRemote.exe"
Name: "{group}\卸载哔哩遥控"; Filename: "{uninstallexe}"
[Registry]
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\com.biliremote.bridge"; ValueType: string; ValueName: ""; ValueData: "{app}\native\com.biliremote.bridge.json"; Flags: uninsdeletekey
[Run]
Filename: "{app}\BiliRemote.exe"; Description: "启动哔哩遥控电脑助手"; Flags: nowait postinstall skipifsilent
[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var NativePath: String; Content: String; Lines: TArrayOfString;
begin
  if CurStep = ssPostInstall then begin
    NativePath := ExpandConstant('{app}\native\BiliRemote.Native.exe');
    StringChangeEx(NativePath, '\', '\\', True);
    Content := '{"name":"com.biliremote.bridge","description":"Bili Remote Chrome bridge","path":"' + NativePath + '","type":"stdio","allowed_origins":["chrome-extension://penfpdlcbljgooeeabnkphfggjhbfnnj/"]}';
    SetArrayLength(Lines, 1);
    Lines[0] := Content;
    SaveStringsToUTF8FileWithoutBOM(ExpandConstant('{app}\native\com.biliremote.bridge.json'), Lines, False);
  end;
end;
