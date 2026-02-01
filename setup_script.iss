; Allben Kitchen Manager Inno Setup Script
; Version: 2.0

[Setup]
AppId={{A6B2D8C1-E5D7-4B3F-8E4D-7F9C5A8B2E1D}}
AppName=Allben Kitchen Manager
AppVersion=2.0
DefaultDirName={autopf}\AllbenKitchenManager
DefaultGroupName=Allben Kitchen Manager
OutputDir=.
OutputBaseFilename=Allben_Setup_v2.0
SetupIconFile=admin_console\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter Build Output
Source: "admin_console\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Dependencies
Source: "dependencies\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\Allben Kitchen Manager"; Filename: "{app}\AllbenKitchenAdmin.exe"
Name: "{group}\{cm:UninstallProgram,Allben Kitchen Manager}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Allben Kitchen Manager"; Filename: "{app}\AllbenKitchenAdmin.exe"; Tasks: desktopicon

[Run]
; Install VC++ Redistributable
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/quiet /install"; StatusMsg: "{cm:InstallingVC}"; Flags: waituntilterminated

[CustomMessages]
korean.InstallingVC=Visual C++ 재배포 가능 패키지를 설치하는 중...
english.InstallingVC=Installing Visual C++ Redistributable...

[Code]
function InitializeSetup: Boolean;
var
  ErrorCode: Integer;
  PythonPath: String;
begin
  Result := True;

  // 1. Check Npcap (Required for packet capture)
  if not RegKeyExists(HKLM, 'SOFTWARE\Npcap') then
  begin
    if MsgBox('필요한 도구(Npcap)가 설치되어 있지 않습니다. 공식 다운로드 페이지를 여시겠습니까?' + #13#10 + '(Npcap은 패킷 수집에 필수적입니다.)', mbConfirmation, MB_YESNO) = IDYES then
    begin
      ShellExec('open', 'https://npcap.com/#download', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
    end;
    Result := False;
  end;

  // 2. Check Wireshark/TShark (Required for pyshark parsing)
  if Result and (not RegKeyExists(HKLM, 'SOFTWARE\Wireshark')) and (not RegKeyExists(HKLM64, 'SOFTWARE\Wireshark')) then
  begin
    if MsgBox('필요한 도구(Wireshark/TShark)가 설치되어 있지 않습니다. 공식 다운로드 페이지를 여시겠습니까?' + #13#10 + '(TShark는 데이터 분석에 필수적입니다.)', mbConfirmation, MB_YESNO) = IDYES then
    begin
      ShellExec('open', 'https://www.wireshark.org/download.html', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
    end;
    Result := False;
  end;

  // 3. Check Tailscale (Optional but recommended)
  if Result and (not RegValueExists(HKLM, 'SOFTWARE\Tailscale', 'InstallDir')) and (not RegKeyExists(HKLM, 'SOFTWARE\Tailscale')) then
  begin
    if MsgBox('네트워크 도구(Tailscale)가 설치되어 있지 않습니다. 공식 다운로드 페이지를 여시겠습니까?' + #13#10 + '(Tailscale은 원격 연결 및 보안 네트워크 구성에 권장됩니다.)', mbConfirmation, MB_YESNO) = IDYES then
    begin
      ShellExec('open', 'https://tailscale.com/download', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
    end;
    Result := False; 
  end;
end;
