import sys
import threading
import time
import struct
import queue
import os
import re
from datetime import datetime

# Diagnostic Print
print(f"[*] Python Version: {sys.version}")
print(f"[*] Python Path: {sys.path}")

# Windows Scapy setup for Npcap/WinPcap
try:
    from scapy.all import sniff, TCP, IP, conf
    import scapy
    print(f"[*] Scapy loaded from: {scapy.__file__}")
    try:
        from scapy.arch.windows import get_windows_if_list
    except ImportError:
        try:
            from scapy.all import get_windows_if_list
        except ImportError:
            print("[WARNING] get_windows_if_list 를 찾을 수 없습니다.")
            def get_windows_if_list(): return []
except ImportError as e:
    import traceback
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] [ERROR] scapy is not installed or dependency missing: {e}")
    traceback.print_exc()
    print("Run: pip install scapy")
    sys.exit(1)

# [설정]
MYSQL_PORT = 3306
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "log")
RAW_LOG_FILE = os.path.join(LOG_DIR, "raw_packet_log.txt")
ORDER_LOG_FILE = os.path.join(LOG_DIR, "order_events.txt")

# 로그 디렉토리 생성 보장
if not os.path.exists(LOG_DIR):
    try:
        os.makedirs(LOG_DIR)
    except Exception:
        # 권한 문제 등으로 실패 시 현재 디렉토리 사용
        LOG_DIR = "."
        RAW_LOG_FILE = "raw_packet_log.txt"
        ORDER_LOG_FILE = "order_events.txt"

# State Management
# stmt_map: {stmt_id: {"query": query_string, "num_params": int}}
stmt_map = {}
# pending_prepares: { (client_ip, client_port): query_string }
pending_prepares = {}
# active_params_map: { stmt_id: [param_types] }
active_params_map = {}

# 비동기 로깅을 위한 큐와 워커 설정
log_queue = queue.Queue()

def logging_worker():
    """파일 I/O 병목을 방지하기 위한 비동기 로깅 스레드"""
    print("[*] Logging worker thread started.")
    while True:
        try:
            msg_type, content = log_queue.get()
            if msg_type == "EXIT":
                break
            
            filename = RAW_LOG_FILE if msg_type == "RAW" else ORDER_LOG_FILE
            with open(filename, "a", encoding="utf-8") as f:
                f.write(content + "\n")
            
            log_queue.task_done()
        except Exception as e:
            print(f"[LOG ERROR] {e}")

# 로깅 스레드 시작
threading.Thread(target=logging_worker, daemon=True).start()

def get_micro_timestamp():
    """마이크로초 단위 타임스탬프 반환"""
    return datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')

def normalize_query(query):
    """SQL 쿼리 정규화: 특수문자([], `) 제거 및 공백 정규화, 소문자화"""
    if not query: return ""
    query = re.sub(r'[\[\]`]', '', query)
    query = re.sub(r'\s+', ' ', query).strip()
    return query.lower()

def read_lenenc_int(data, offset):
    if offset >= len(data): return 0, 0
    first = data[offset]
    if first < 251:
        return first, 1
    elif first == 252:
        return struct.unpack('<H', data[offset+1:offset+3])[0], 3
    elif first == 253:
        return struct.unpack('<I', data[offset+1:offset+5] + b'\x00')[0], 4
    elif first == 254:
        return struct.unpack('<Q', data[offset+1:offset+9])[0], 9
    return 0, 1

def parse_binary_values(data, offset, num_params, param_types):
    values = []
    if offset >= len(data): return values
    
    try:
        # Null bitmap: (num_params + 7 + 2) // 8? EXECUTE: (num_params + 7) // 8
        null_bitmap_len = (num_params + 7) // 8
        if offset + null_bitmap_len > len(data): return values
        null_bitmap = data[offset : offset + null_bitmap_len]
        offset += null_bitmap_len
        
        # New parameters bound flag
        if offset >= len(data): return values
        new_params_bound = data[offset]
        offset += 1
        
        if new_params_bound:
            param_types = []
            for _ in range(num_params):
                if offset + 2 > len(data): break
                p_type = struct.unpack('<H', data[offset:offset+2])[0]
                param_types.append(p_type & 0xFF)
                offset += 2

        for i in range(num_params):
            if i < len(param_types):
                p_type = param_types[i]
                byte_idx = i // 8
                bit_idx = i % 8
                if byte_idx < len(null_bitmap) and (null_bitmap[byte_idx] & (1 << bit_idx)):
                    values.append(None)
                    continue

                try:
                    if p_type in [0x03]: # MYSQL_TYPE_LONG
                        if offset + 4 <= len(data):
                            val = struct.unpack('<i', data[offset:offset+4])[0]
                            values.append(val)
                            offset += 4
                        else: values.append("IndexError")
                    elif p_type in [0x08]: # MYSQL_TYPE_LONGLONG
                        if offset + 8 <= len(data):
                            val = struct.unpack('<q', data[offset:offset+8])[0]
                            values.append(val)
                            offset += 8
                        else: values.append("IndexError")
                    elif p_type in [0x0f, 0xfc, 0xfd, 0xfe]: # STRING/VAR_STRING/BLOB
                        length, size = read_lenenc_int(data, offset)
                        offset += size
                        if offset + length <= len(data):
                            raw_val = data[offset:offset+length]
                            val = raw_val.decode('utf-8', 'ignore')
                            values.append(val)
                            offset += length
                        else: values.append("IndexError")
                    else:
                        if offset + 4 <= len(data):
                            raw_val = data[offset:offset+4]
                            values.append(f"Hex:{raw_val.hex()}")
                            offset += 4
                        else: values.append("IndexError")
                except Exception:
                    values.append("<Error>")
    except Exception as e:
        print(f"[PARSE ERROR] {e}")
        
    return values

def log_raw(src, dst, cmd_id, summary):
    ts = get_micro_timestamp()
    log_msg = f"[{ts}] [{src} -> {dst}] [Cmd:{cmd_id:02x}] {summary}"
    print(log_msg)
    log_queue.put(("RAW", log_msg))

def log_order(order_type, seat, price, details=""):
    ts = get_micro_timestamp()
    # 형식: [Timestamp] [Order ID/Type] [Seat: 39번] [Total: 13,000원] [Items: ...]
    log_msg = f"[{ts}] [{order_type}] [Seat: {seat}] [Total: {price}] [Details: {details}]"
    print(f"\033[92m{log_msg}\033[0m") # Highlight order in console
    log_queue.put(("ORDER", log_msg))

def find_loopback_adapter():
    """'Npcap Loopback Adapter'를 자동으로 찾습니다."""
    for iface in get_windows_if_list():
        desc = iface.get('description', '')
        name = iface.get('name', '')
        if "Npcap Loopback Adapter" in desc or "Loopback" in name:
            return iface['name']
    return None

def parse_mysql_payload(payload, src_info, dst_info, is_to_server):
    if len(payload) < 4: return
    pkt_len = struct.unpack('<I', payload[:3] + b'\x00')[0]
    mysql_data = payload[4:4+pkt_len]
    if not mysql_data: return
    
    src_str = f"{src_info[0]}:{src_info[1]}"
    dst_str = f"{dst_info[0]}:{dst_info[1]}"

    if is_to_server:
        cmd = mysql_data[0]
        summary = ""
        
        if cmd == 0x03: # COM_QUERY
            query_raw = mysql_data[1:].decode('utf-8', 'ignore').strip()
            query_norm = normalize_query(query_raw)
            summary = f"Query: {query_raw[:100]}"
            log_raw(src_str, dst_str, cmd, summary)
            
            # 유연한 테이블 매칭 및 명령어 감지 (Insert/Update + order/suborder/toll/billing)
            if any(k in query_norm for k in ['order', 'suborder', 'toll', 'billing']) and any(c in query_norm for c in ['insert', 'update']):
                log_order("QUERY_ORDER", "N/A", "N/A", f"Query: {query_raw[:100]}")

        elif cmd == 0x16: # COM_STMT_PREPARE
            query_raw = mysql_data[1:].decode('utf-8', 'ignore').strip()
            pending_prepares[src_info] = query_raw
            summary = f"Prepare: {query_raw[:100]}"
            log_raw(src_str, dst_str, cmd, summary)

        elif cmd == 0x17: # COM_STMT_EXECUTE
            if len(mysql_data) >= 5:
                stmt_id = struct.unpack('<I', mysql_data[1:5])[0]
                stmt_info = stmt_map.get(stmt_id)
                if stmt_info:
                    query_raw = stmt_info['query']
                    query_norm = normalize_query(query_raw)
                    params = parse_binary_values(mysql_data, 10, stmt_info['num_params'], [])
                    summary = f"Execute ID:{stmt_id} | {query_raw[:50]}"
                    
                    # Robust matching for any order-related table (Case-insensitive via normalize_query)
                    is_order = any(k in query_norm for k in ['order', 'suborder', 'toll', 'billing']) and any(c in query_norm for c in ['insert', 'update'])
                    
                    if is_order:
                        # Safe parameter extraction (handle IndexError)
                        seat = "N/A"
                        if len(params) > 9 and params[9] is not None:
                            seat = f"{params[9]}번"
                            
                        price = "0원"
                        if len(params) > 7 and params[7] is not None:
                            if isinstance(params[7], (int, float)):
                                price = f"{params[7]:,}원"
                            else:
                                price = f"{params[7]}"
                        
                        log_order("STMT_ORDER", seat, price, f"Query: {query_raw[:50]} | Params: {params}")
                    
                    log_raw(src_str, dst_str, cmd, summary)
                else:
                    summary = f"Unknown Execute ID: {stmt_id}"
                    log_raw(src_str, dst_str, cmd, summary)
    else:
        # Server to Client Response
        if src_info in pending_prepares:
            if mysql_data[0] == 0x00 and len(mysql_data) >= 9:
                stmt_id = struct.unpack('<I', mysql_data[1:5])[0]
                num_params = struct.unpack('<H', mysql_data[7:9])[0]
                query = pending_prepares.pop(src_info)
                stmt_map[stmt_id] = {"query": query, "num_params": num_params}
                log_raw(src_str, dst_str, 0x00, f"Prepare OK: ID {stmt_id} (Params: {num_params})")
        else:
             log_raw(src_str, dst_str, mysql_data[0], "Response Captured")

def packet_callback(pkt):
    try:
        if pkt.haslayer(TCP) and pkt.haslayer(IP):
            ip_layer = pkt[IP]
            tcp_layer = pkt[TCP]
            payload = bytes(tcp_layer.payload)
            if not payload: return

            if tcp_layer.dport == MYSQL_PORT:
                parse_mysql_payload(payload, (ip_layer.src, tcp_layer.sport), (ip_layer.dst, tcp_layer.dport), True)
            elif tcp_layer.sport == MYSQL_PORT:
                parse_mysql_payload(payload, (ip_layer.src, tcp_layer.sport), (ip_layer.dst, tcp_layer.dport), False)
    except Exception:
        pass

def start_sniffing():
    adapter = find_loopback_adapter()
    if not adapter:
        print("[ERROR] Npcap Loopback Adapter를 찾을 수 없습니다.")
        return

    print(f"[*] Sniffing on {adapter} (MySQL: {MYSQL_PORT})")
    print(f"[*] Logs will be saved to: {LOG_DIR}")
    conf.sniff_promisc = True
    
    try:
        # L3RawSocket is often better for Windows loopback
        sniff(iface=adapter, filter=f"tcp port {MYSQL_PORT}", prn=packet_callback, store=0)
    except KeyboardInterrupt:
        print("\n[*] Stopping...")
        log_queue.put(("EXIT", ""))
    except Exception as e:
        print(f"[CRITICAL ERROR] {e}")

if __name__ == "__main__":
    start_sniffing()
