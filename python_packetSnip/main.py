import sys
import json
import threading
import queue
import time
import traceback
from datetime import datetime

try:
    import pyshark
    import requests
except ImportError:
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] [ERROR] 필수 패키지(pyshark, requests)가 설치되어 있지 않습니다.")
    print("설치 방법: pip install pyshark requests")
    sys.exit(1)

# [설정] Dart 서버 엔드포인트
SERVER_URL = "http://localhost:8080/api/external_order"
MYSQL_PORT = 3306

# State Management: Prepared Statement ID 추적
# PREPARE 단계에서 쿼리문을 저장하고, EXECUTE 단계에서 ID로 대조하기 위함
prepared_statements = {}

# 비동기 전송을 위한 큐 설정
data_queue = queue.Queue()

def log(level, message):
    """표준화된 로그 출력 함수"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] [{level}] {message}")
    sys.stdout.flush()

def find_loopback_adapter():
    """NPF_Loopback 어댑터를 자동으로 찾습니다."""
    try:
        interfaces = pyshark.tshark.tshark.get_tshark_interfaces()
        for line in interfaces:
            if r"\Device\NPF_Loopback" in line:
                return r"\Device\NPF_Loopback"
        for line in interfaces:
            if "loopback" in line.lower():
                parts = line.split()
                if len(parts) >= 2:
                    return parts[1]
    except Exception as e:
        log("ERROR", f"Adapter search failed: {e}\n{traceback.format_exc()}")
    return r'\Device\NPF_Loopback'

def send_worker():
    """큐에서 데이터를 가져와 서버로 전송하는 워커 스레드"""
    log("INFO", "Send worker thread started.")
    while True:
        try:
            data = data_queue.get()
            if data is None: break
            
            try:
                response = requests.post(SERVER_URL, json=data, timeout=0.5)
                if response.status_code == 200:
                    log("INFO", f"Data sent: {data.get('type')} (Seat: {data.get('seat_no')})")
                else:
                    log("ERROR", f"Server error {response.status_code}")
            except requests.exceptions.RequestException as e:
                log("ERROR", f"Network error: {e}")
            
            data_queue.task_done()
        except Exception as e:
            log("ERROR", f"Worker error: {e}")

def process_mysql_packet(packet):
    """
    [MySQL Protocol 기술 검증]
    1. COM_STMT_PREPARE (22): 서버에 쿼리 템플릿을 등록하고 Statement ID를 발급받는 단계.
    2. COM_STMT_EXECUTE (23): 발급받은 ID와 바이너리로 바인딩된 파라미터들을 전송하는 단계.
    3. Binary Protocol Value: 파라미터는 Null Bitmap 이후 정해진 순서(Index)대로 데이터가 위치함.
    4. TCP Reassembly: 대용량 주문(분할 패킷) 처리를 위해 tcp.desegment_tcp_streams 활성화 필수.
    """
    try:
        if not hasattr(packet, 'mysql'):
            return

        mysql_layer = packet.mysql
        command = getattr(mysql_layer, 'command', None)

        # 1. Statement Prepare 캐싱 (Query 문맥 확보)
        if command == '22' and hasattr(mysql_layer, 'query'):
            query = mysql_layer.query.lower()
            stmt_id = getattr(mysql_layer, 'stmt_id', None)
            if stmt_id and ('tb_order' in query or 'tb_suborder' in query):
                prepared_statements[stmt_id] = query
                log("DEBUG", f"Statement Cached: ID={stmt_id} | Query={query[:50]}...")

        # 2. Statement Execute 분석 (실제 데이터 추출)
        elif command == '23':
            stmt_id = getattr(mysql_layer, 'stmt_id', None)
            context = prepared_statements.get(stmt_id, "Unknown Context")
            
            log("DEBUG", f"Command 23 Detected (ID: {stmt_id} | Context: {context})")

            try:
                # 바이너리 파라미터 추출 (Pyshark의 .all_fields 활용)
                params = []
                if hasattr(mysql_layer, 'value'):
                    params = [f.get_default_value() for f in mysql_layer.value.all_fields]
                elif hasattr(mysql_layer, 'string'):
                    params = [f.get_default_value() for f in mysql_layer.string.all_fields]

                # 기획 인덱스 적용: Index 9 (좌석), Index 7 (총액)
                if len(params) > 9:
                    order_data = {
                        "type": "tb_order" if 'tb_order' in context else "tb_suborder",
                        "seat_no": params[9],
                        "total_price": params[7],
                        "stmt_id": stmt_id,
                        "timestamp": datetime.now().isoformat()
                    }
                    data_queue.put(order_data)
                    log("INFO", f"Order Detected: Seat {params[9]}, Price {params[7]}")
                else:
                    # 파라미터가 부족하더라도 감지 로그는 남김 (디버깅 용도)
                    if stmt_id in prepared_statements:
                        log("DEBUG", f"Execute found but params length {len(params)} insufficient for Index 9")

            except (AttributeError, IndexError) as e:
                log("DEBUG", f"Binary field skip (Incomplete Packet): {e}")

    except Exception as e:
        log("ERROR", f"Packet analysis error: {e}")

def start_sniffing(interface):
    log("INFO", f"MySQL Sniffer Engine v2.0 Started on {interface}")
    
    worker_thread = threading.Thread(target=send_worker, daemon=True)
    worker_thread.start()
    
    capture = None
    try:
        # [고도화 캡처 설정] - TCP 재조합 및 바이너리 분석 최적화
        capture = pyshark.LiveCapture(
            interface=interface,
            display_filter=f'tcp.port == {MYSQL_PORT} && (mysql.command == 22 || mysql.command == 23)',
            use_json=True,
            include_raw=False,
            decode_as={f'tcp.port=={MYSQL_PORT}': 'mysql'},
            override_prefs={
                'tcp.desegment_tcp_streams': 'TRUE',
                'mysql.desegment_buffers': 'TRUE'
            }
        )
        
        for packet in capture.sniff_continuously():
            process_mysql_packet(packet)
            
    except KeyboardInterrupt:
        log("INFO", "Sniffer stopping...")
    except Exception as e:
        log("ERROR", f"Capture Engine Error: {e}\n{traceback.format_exc()}")
    finally:
        if capture:
            capture.close()
        data_queue.put(None)
        log("INFO", "Sniffer Engine Offline.")

if __name__ == "__main__":
    try:
        target_interface = sys.argv[1] if len(sys.argv) > 1 else find_loopback_adapter()
        start_sniffing(target_interface)
    except Exception as e:
        log("ERROR", f"Critical Startup Failure: {e}")
