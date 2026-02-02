; Scapy MySQL Sniffer Setup Script for Inno Setup
#define MyAppName "Allben Scapy Sniffer"
#define MyAppVersion "1.0"
#define MyAppPublisher "Allben"
#define MyAppExeName "run_scapy_sniffer.bat"

[Setup]
AppId={{E6A0B4D1-5C9E-4F8A-9D8B-4B6A7C8D9E0F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\
OutputBaseFilename=AllbenScapySniffer_Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; 관리자 권한 필수
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Files]
; Python Runtime (인베디드 파이썬 및 Scapy 라이브러리)
Source: "..\python_runtime\*"; DestDir: "{app}\python_runtime"; Flags: ignoreversion recursesubdirs createallsubdirs
; Scapy Sniffer Script
Source: "..\python_packetSnip\scapy_main.py"; DestDir: "{app}\python_packetSnip"; Flags: ignoreversion
; Execution BAT Script
Source: "..\bat\run_scapy_sniffer.bat"; DestDir: "{app}\bat"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\bat\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\bat\{#MyAppExeName}"; IconFilename: "{app}\bat\{#MyAppExeName}"

[Run]
Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; StatusMsg: "Scapy Sniffer를 시작하는 중..."; Filename: "{app}\bat\{#MyAppExeName}"; Flags: shellexec postinstall skipifsilent
