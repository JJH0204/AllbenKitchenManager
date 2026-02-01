import sys
import json
import threading
import queue
import time
from datetime import datetime

try:
    import pyshark
    import requests
except ImportError:
    print("Error: 필수 패키지(pyshark, requests)가 설치되어 있지 않습니다.")
    print("설치 방법: pip install pyshark requests")
    sys.exit(1)

# [설정] Dart 서버 엔드포인트
SERVER_URL = "http://localhost:8080/api/external_order"
MYSQL_PORT = 3306

# 비동기 전송을 위한 큐 설정
data_queue = queue.Queue()

def find_loopback_adapter():
    """NPF_Loopback 어댑터를 자동으로 찾습니다."""
    try:
        # tshark 인터페이스 목록 가져오기
        interfaces = pyshark.tshark.tshark.get_tshark_interfaces()
        # 1. NPF_Loopback 명시적 검색
        for line in interfaces:
            if r"\Device\NPF_Loopback" in line:
                return r"\Device\NPF_Loopback"
        # 2. 'loopback' 키워드 검색
        for line in interfaces:
            if "loopback" in line.lower():
                parts = line.split()
                if len(parts) >= 2:
                    return parts[1]
    except Exception as e:
        print(f"[*] Adapter search failed: {e}")
    
    # 기본값 반환
    return r'\Device\NPF_Loopback'

def send_worker():
    """큐에서 데이터를 가져와 서버로 전송하는 워커 스레드"""
    print("[*] Send worker thread started.")
    while True:
        try:
            data = data_queue.get()
            if data is None: # 종료 신호
                break
            
            try:
                # 타임아웃을 짧게(0.5초) 설정하여 전송 지연이 큐에 쌓이는 것을 방지
                response = requests.post(SERVER_URL, json=data, timeout=0.5)
                if response.status_code == 200:
                    print(f"[OK] Data sent: {data.get('type')}")
                else:
                    print(f"[ERR] Server returned {response.status_code}")
            except requests.exceptions.RequestException as e:
                print(f"[ERR] Network error: {e}")
            
            data_queue.task_done()
            sys.stdout.flush()
        except Exception as e:
            print(f"[ERR] Worker error: {e}")

def process_mysql_packet(packet):
    """패킷에서 필요한 데이터만 추출하여 큐에 삽입"""
    try:
        # pyshark 최적화(use_json=True) 시 필드 접근 방식
        if hasattr(packet, 'mysql'):
            mysql_layer = packet.mysql
            
            # COM_STMT_EXECUTE (23) 또는 일반 Query (3) 등 필요한 명령 확인
            command = getattr(mysql_layer, 'command', None)
            
            if command == '23': # COM_STMT_EXECUTE
                # 필요한 필드만 즉시 추출 (무거운 전체 필드 리스트화 지양)
                values = [f.get_default_value() for f in mysql_layer.value.all_fields] if hasattr(mysql_layer, 'value') else []
                
                # 데이터 유무에 따른 분류
                if len(values) >= 17:
                    order_data = {
                        "type": "tb_order",
                        "seat_no": values[9],
                        "total_price": values[7],
                        "order_time": values[16],
                        "timestamp": datetime.now().isoformat()
                    }
                    data_queue.put(order_data)
                
                elif len(values) > 0:
                    suborder_data = {
                        "type": "tb_suborder",
                        "items": values,
                        "timestamp": datetime.now().isoformat()
                    }
                    data_queue.put(suborder_data)

    except Exception:
        # 패킷 분석 중 오류는 무시하고 흐름 유지
        pass

def start_sniffing(interface):
    """패킷 캡처 시작 및 메인 루프"""
    print(f"[*] MySQL Sniffer Started on {interface}")
    sys.stdout.flush()
    
    # 전송 워커 스레드 시작
    worker_thread = threading.Thread(target=send_worker, daemon=True)
    worker_thread.start()
    
    capture = None
    try:
        # 성능 최적화를 위한 LiveCapture 설정
        capture = pyshark.LiveCapture(
            interface=interface,
            display_filter=f'tcp.port == {MYSQL_PORT} && mysql.command == 23',
            use_json=True,      # JSON 엔진 사용으로 파싱 속도 향상
            include_raw=False,  # Raw 데이터 제외로 메모리 절약
            decode_as={f'tcp.port=={MYSQL_PORT}': 'mysql'} # 3306 포트를 mysql로 강제 지정
        )
        
        for packet in capture.sniff_continuously():
            process_mysql_packet(packet)
            
    except KeyboardInterrupt:
        print("\n[*] Stopping sniffer...")
    except Exception as e:
        print(f"[CRITICAL] Capture error: {e}")
    finally:
        if capture:
            capture.close()
        # 워커 종료 신호
        data_queue.put(None)
        print("[*] Cleanup finished.")
        sys.stdout.flush()

if __name__ == "__main__":
    # 인터페이스 결정
    if len(sys.argv) > 1:
        target_interface = sys.argv[1]
    else:
        target_interface = find_loopback_adapter()
    
    start_sniffing(target_interface)
