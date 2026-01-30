try:
    import pyshark
    import requests
except ImportError:
    print("Error: 필수 패키지(pyshark, requests)가 설치되어 있지 않습니다.")
    print("설치 방법: pip install pyshark requests")
    sys.exit(1)

import json
import sys
from datetime import datetime

# Dart Server Endpoint
SERVER_URL = "http://localhost:8080/api/external_order"

def find_loopback_adapter():
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
    except:
        pass
    return r'\Device\NPF_Loopback'

# [설정] 명령줄 인자가 있으면 사용, 없으면 자동 검색
if len(sys.argv) > 1:
    INTERFACE_NAME = sys.argv[1]
else:
    INTERFACE_NAME = find_loopback_adapter()

MYSQL_PORT = 3306

def send_to_server(data):
    try:
        response = requests.post(SERVER_URL, json=data, timeout=2)
        if response.status_code == 200:
            print(f"[OK] Data sent to server: {data.get('type')}")
        else:
            print(f"[ERR] Server returned {response.status_code}")
    except Exception as e:
        print(f"[ERR] Failed to send data: {e}")

def process_mysql_packet(packet):
    try:
        if 'MYSQL' in packet and hasattr(packet.mysql, 'command'):
            if packet.mysql.command == '23': # COM_STMT_EXECUTE
                values = [f.get_default_value() for f in packet.mysql.value.all_fields]
                
                # 1. tb_order (주문 마스터) 탐지
                if len(values) >= 17:
                    order_data = {
                        "type": "tb_order",
                        "seat_no": values[9],
                        "total_price": values[7],
                        "order_time": values[16],
                        "raw_values": values
                    }
                    print(f"\n[NEW ORDER] Seat: {order_data['seat_no']} | Total: {order_data['total_price']}")
                    send_to_server(order_data)

                # 2. tb_suborder (상세 메뉴) 탐지
                elif "tb_suborder" in str(packet.mysql.query).lower() or len(values) < 15:
                    suborder_data = {
                        "type": "tb_suborder",
                        "items": values
                    }
                    print(f"[SUBORDER] Items: {values}")
                    send_to_server(suborder_data)

    except Exception as e:
        pass

def start_sniffing():
    print(f"[*] MySQL Sniffer Started on {INTERFACE_NAME}")
    sys.stdout.flush() # Ensure Dart receives this immediately
    
    capture = pyshark.LiveCapture(
        interface=INTERFACE_NAME,
        display_filter=f'tcp.port == {MYSQL_PORT} && mysql.command == 23'
    )
    
    for packet in capture.sniff_continuously():
        process_mysql_packet(packet)

if __name__ == "__main__":
    start_sniffing()
