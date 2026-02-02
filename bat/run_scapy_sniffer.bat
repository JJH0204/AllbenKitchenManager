@echo off
chcp 65001 >nul
setlocal
:: 관리자 권한 체크
openfiles >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] 이 스크립트는 관리자 권한으로 실행되어야 합니다.
    echo 오른쪽 클릭 후 '관리자 권한으로 실행'을 선택해 주세요.
    pause
    exit /b %errorlevel%
)

echo [*] Scapy MySQL Sniffer를 시작합니다...
echo [*] 사용 중인 파이썬: ..\python_runtime\python.exe

:: 실행 위치 기준 설정
cd /d "%~dp0"

:: 상위 폴더의 python_runtime을 사용하여 scapy_main.py 실행
..\python_runtime\python.exe ..\python_packetSnip\scapy_main.py

if %errorlevel% neq 0 (
    echo [ERROR] 스니퍼 실행 중 오류가 발생했습니다.
    pause
)
pause
