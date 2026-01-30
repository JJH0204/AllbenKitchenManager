import pyshark
import json
import sys
from datetime import datetime

def find_loopback_adapter():
    try:
        interfaces = pyshark.tshark.tshark.get_tshark_interfaces()
        # 1순위: \Device\NPF_Loopback (직접 매칭)
        for line in interfaces:
            if r"\Device\NPF_Loopback" in line:
                return r"\Device\NPF_Loopback"
        
        # 2순위: 'loopback' 키워드가 포함된 인터페이스
        for line in interfaces:
            if "loopback" in line.lower():
                parts = line.split()
                if len(parts) >= 2:
                    return parts[1]
    except:
        pass
    return r'\Device\NPF_Loopback' # Default fallback

# [설정] Npcap 루프백 인터페이스 이름 자동 확인
INTERFACE_NAME = find_loopback_adapter() 
MYSQL_PORT = 3306

def process_mysql_packet(packet):
    try:
        # MySQL 계층 존재 여부 및 Execute Statement(23) 확인
        if 'MYSQL' in packet and hasattr(packet.mysql, 'command'):
            if packet.mysql.command == '23': # COM_STMT_EXECUTE
                
                # 바인딩된 파라미터 값 추출 (mysql.value 필드 리스트)
                # Pyshark는 동일 필드명을 리스트로 가져올 수 있음
                values = [f.get_default_value() for f in packet.mysql.value.all_fields]
                
                # 1. tb_order (주문 마스터) 탐지: 약 19개 파라미터
                if len(values) >= 17:
                    seat_no = values[9]    # Index 9: 좌석 번호
                    total_price = values[7] # Index 7: 결제 금액
                    order_time = values[16] # Index 16: 등록 시간
                    
                    order_time = values[16] # Index 16: 등록 시간
                    
                    print(f"\n[NEW ORDER - tb_order]")
                    print(f"[Seat]: {seat_no} | [Total]: {total_price} | [Time]: {order_time}")
                    print("-" * 50)

                # 2. tb_suborder (상세 메뉴) 탐지
                # 상세 메뉴는 GoodsNo와 단가가 포함된 특정 인덱스 패턴을 따름
                elif "tb_suborder" in str(packet.mysql.query).lower() or len(values) < 15:
                    # 상세 내역 파싱 로직 (GoodsNo 추출)
                    print(f"[Suborder Items]: {values}")

    except Exception as e:
        pass # 비정상 패킷 무시

def start_sniffing():
    print(f"[*] MySQL Monitoring Started (Port: {MYSQL_PORT}, Adapter: {INTERFACE_NAME})...")
    # Npcap 루프백 어댑터를 통해 3306 포트 필터링
    capture = pyshark.LiveCapture(
        interface=INTERFACE_NAME,
        display_filter=f'tcp.port == {MYSQL_PORT} && mysql.command == 23'
    )
    
    for packet in capture.sniff_continuously():
        process_mysql_packet(packet)

if __name__ == "__main__":
    start_sniffing()