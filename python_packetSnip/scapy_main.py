import sys
import threading
import time
import struct
import queue
import os
import re
import json
import uuid
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

# MySQL Packet Header: 3 bytes Length, 1 byte Sequence ID
# MySQL Commands
COM_QUERY = 0x03
COM_STMT_PREPARE = 0x16
COM_STMT_EXECUTE = 0x17
COM_STMT_CLOSE   = 0x19

# [설정]
MYSQL_PORT = 3306
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "log")
SQL_LOG_FILE = os.path.join(LOG_DIR, "sql_history.jsonl")      # Raw SQL commands
DATA_LOG_FILE = os.path.join(LOG_DIR, "data_results.jsonl")    # ResultSet rows
ORDER_LOG_FILE = os.path.join(LOG_DIR, "order_tracking.jsonl") # Analyzed orders

# 로그 디렉토리 생성 보장
if not os.path.exists(LOG_DIR):
    try:
        os.makedirs(LOG_DIR)
    except Exception:
        LOG_DIR = "."
        SQL_LOG_FILE = "sql_history.jsonl"
        DATA_LOG_FILE = "data_results.jsonl"
        ORDER_LOG_FILE = "order_tracking.jsonl"

# State Management
# stmt_map: {stmt_id: {"query": query_string, "num_params": int, "col_types": []}}
stmt_map = {}
# session_map: {(client_ip, client_port): MySQLSession}
session_map = {}
# pending_prepares: { (client_ip, client_port): query_string }
pending_prepares = {}

class MySQLSession:
    def __init__(self):
        self.state = "IDLE"
        self.cmd = 0
        self.stmt_id = None
        self.tx_id = None  # Transaction ID to link query and result
        self.col_count = 0
        self.cols_received = 0
        self.col_types = []
        self.rows_count = 0
        self.query = ""

    def reset(self, new_tx=True):
        self.state = "IDLE"
        self.cmd = 0
        self.col_count = 0
        self.cols_received = 0
        self.col_types = []
        self.rows_count = 0
        if new_tx:
            self.tx_id = str(uuid.uuid4())[:8]

# 비동기 로깅을 위한 큐와 워커 설정
log_queue = queue.Queue()

def logging_worker():
    """JSONL 형식을 지원하는 비동기 로깅 워커"""
    print("[*] Logging worker thread started.")
    while True:
        try:
            msg_type, data = log_queue.get()
            if msg_type == "EXIT":
                break
            
            # 파일 경로 결정
            if msg_type == "SQL": filename = SQL_LOG_FILE
            elif msg_type == "DATA": filename = DATA_LOG_FILE
            elif msg_type == "ORDER": filename = ORDER_LOG_FILE
            else: filename = os.path.join(LOG_DIR, "error.jsonl")

            # JSONL 기록
            with open(filename, "a", encoding="utf-8") as f:
                f.write(json.dumps(data, ensure_ascii=False) + "\n")
            
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
        if offset + 3 > len(data): return 0, 0
        return struct.unpack('<H', data[offset+1:offset+3])[0], 3
    elif first == 253:
        if offset + 4 > len(data): return 0, 0
        return struct.unpack('<I', data[offset+1:offset+4] + b'\x00')[0], 4
    elif first == 254:
        if offset + 9 > len(data): return 0, 0
        return struct.unpack('<Q', data[offset+1:offset+9])[0], 9
    return 0, 1

def read_lenenc_str(data, offset):
    length, size = read_lenenc_int(data, offset)
    if size == 0: return None, 0
    offset += size
    if offset + length > len(data):
        return data[offset:].decode('utf-8', 'ignore'), size + (len(data) - offset)
    val = data[offset : offset + length].decode('utf-8', 'ignore')
    return val, size + length

def parse_text_resultset_row(data, offset, col_count):
    values = []
    for _ in range(col_count):
        if offset >= len(data): break
        if data[offset] == 0xFB: # NULL
            values.append(None)
            offset += 1
        else:
            val, size = read_lenenc_str(data, offset)
            values.append(val)
            offset += size
    return values, offset

def get_mysql_type_name(t):
    types = {0x00: "DECIMAL", 0x01: "TINY", 0x02: "SHORT", 0x03: "LONG", 0x04: "FLOAT", 0x05: "DOUBLE", 0x08: "LONGLONG", 0x0c: "DATETIME", 0x0f: "VARCHAR", 0xfc: "BLOB", 0xfd: "VAR_STRING", 0xfe: "STRING"}
    return types.get(t, f"0x{t:02x}")

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
            # Re-parse parameter types if flag is set
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
                    if p_type in [0x01]: # TINY
                        val = struct.unpack('<b', data[offset:offset+1])[0]; values.append(val); offset += 1
                    elif p_type in [0x02]: # SHORT
                        val = struct.unpack('<h', data[offset:offset+2])[0]; values.append(val); offset += 2
                    elif p_type in [0x03]: # LONG
                        val = struct.unpack('<i', data[offset:offset+4])[0]; values.append(val); offset += 4
                    elif p_type in [0x08]: # LONGLONG
                        val = struct.unpack('<q', data[offset:offset+8])[0]; values.append(val); offset += 8
                    elif p_type in [0x04]: # FLOAT
                        val = struct.unpack('<f', data[offset:offset+4])[0]; values.append(val); offset += 4
                    elif p_type in [0x05]: # DOUBLE
                        val = struct.unpack('<d', data[offset:offset+8])[0]; values.append(val); offset += 8
                    elif p_type in [0x0f, 0xfc, 0xfd, 0xfe]: # STRING/VAR_STRING/BLOB
                        val, size = read_lenenc_str(data, offset)
                        values.append(val)
                        offset += size
                    else:
                        val, size = read_lenenc_str(data, offset)
                        values.append(val if val is not None else f"Hex:{data[offset:offset+4].hex()}")
                        offset += size if size > 0 else 4
                except Exception:
                    values.append("<Error>")
    except Exception as e:
        print(f"[PARSE ERROR] {e}")
        
    return values

def log_event(msg_type, src, dst, summary, tx_id=None, extra=None):
    """구조화된 로그 생성 및 큐 전송"""
    ts = get_micro_timestamp()
    log_data = {
        "ts": ts,
        "src": src,
        "dst": dst,
        "tx_id": tx_id,
        "summary": summary
    }
    if extra:
        log_data.update(extra)
    
    # 터미널 출력 (가독성용)
    display_msg = f"[{ts}] [{src}] [Tx:{tx_id}] {summary}"
    if msg_type == "ORDER":
        print(f"\033[92m{display_msg}\033[0m", flush=True)
    else:
        print(display_msg, flush=(msg_type == "DATA"))
        
    log_queue.put((msg_type, log_data))

def find_loopback_adapter():
    """'Npcap Loopback Adapter'를 자동으로 찾습니다."""
    for iface in get_windows_if_list():
        desc = iface.get('description', '')
        name = iface.get('name', '')
        if "Npcap Loopback Adapter" in desc or "Loopback" in name:
            return iface['name']
    return None

def parse_mysql_payload(payload, src_info, dst_info, is_to_server):
    src_str = f"{src_info[0]}:{src_info[1]}"
    dst_str = f"{dst_info[0]}:{dst_info[1]}"
    client_key = src_info if is_to_server else dst_info
    
    if client_key not in session_map:
        session_map[client_key] = MySQLSession()
    session = session_map[client_key]

    offset = 0
    while offset + 4 <= len(payload):
        pkt_len = struct.unpack('<I', payload[offset:offset+3] + b'\x00')[0]
        seq_id = payload[offset+3]
        mysql_data = payload[offset+4 : offset+4+pkt_len]
        offset += 4 + pkt_len

        if not mysql_data: continue

        if is_to_server:
            cmd = mysql_data[0]
            session.reset(new_tx=True)
            session.cmd = cmd
            
            if cmd == COM_QUERY:
                query_raw = mysql_data[1:].decode('utf-8', 'ignore').strip()
                session.query = query_raw
                session.state = "AWAITING_RESULTSET"
                log_event("SQL", src_str, dst_str, f"Query: {query_raw[:100]}", tx_id=session.tx_id, extra={"full_query": query_raw, "cmd": "QUERY"})
                
            elif cmd == COM_STMT_PREPARE:
                query_raw = mysql_data[1:].decode('utf-8', 'ignore').strip()
                pending_prepares[src_info] = query_raw
                log_event("SQL", src_str, dst_str, f"Prepare: {query_raw[:100]}", tx_id=session.tx_id, extra={"full_query": query_raw, "cmd": "PREPARE"})

            elif cmd == COM_STMT_EXECUTE:
                if len(mysql_data) >= 5:
                    stmt_id = struct.unpack('<I', mysql_data[1:5])[0]
                    session.stmt_id = stmt_id
                    stmt_info = stmt_map.get(stmt_id)
                    if stmt_info:
                        session.query = stmt_info['query']
                        session.state = "AWAITING_RESULTSET"
                        params = parse_binary_values(mysql_data, 10, stmt_info['num_params'], [])
                        log_event("SQL", src_str, dst_str, f"Execute ID:{stmt_id}", tx_id=session.tx_id, extra={"query": session.query, "params": params, "cmd": "EXECUTE"})
                    else:
                        log_event("SQL", src_str, dst_str, f"Unknown Execute ID: {stmt_id}", tx_id=session.tx_id)
            
            elif cmd == COM_STMT_CLOSE:
                if len(mysql_data) >= 5:
                    stmt_id = struct.unpack('<I', mysql_data[1:5])[0]
                    stmt_map.pop(stmt_id, None)
                    log_event("SQL", src_str, dst_str, f"Close ID: {stmt_id}", tx_id=session.tx_id)

        else:
            # Server to Client Response
            first_byte = mysql_data[0]
            
            if session.state == "AWAITING_RESULTSET":
                if first_byte == 0x00: # OK Packet
                    session.reset(new_tx=False)
                elif first_byte == 0xFF: # Error Packet
                    session.reset(new_tx=False)
                else:
                    count, size = read_lenenc_int(mysql_data, 0)
                    session.col_count = count
                    session.state = "READING_COLUMNS"
                    session.cols_received = 0
                    session.col_types = []

            elif session.state == "READING_COLUMNS":
                if first_byte == 0xfe and pkt_len < 9:
                    session.state = "READING_ROWS"
                else:
                    off = 0
                    for _ in range(6):
                        _, s = read_lenenc_str(mysql_data, off)
                        off += s
                    off += 1 + 2 + 4
                    if off < len(mysql_data):
                        col_type = mysql_data[off]
                        session.col_types.append(col_type)
                    session.cols_received += 1

            elif session.state == "READING_ROWS":
                if first_byte == 0xfe and pkt_len < 9:
                    session.reset(new_tx=False)
                elif first_byte == 0x00 and session.cmd == COM_STMT_EXECUTE:
                    rows = parse_binary_values(mysql_data, 1, session.col_count, session.col_types)
                    log_event("DATA", src_str, dst_str, f"Row: {rows}", tx_id=session.tx_id, extra={"rows": rows})
                else:
                    row_data, _ = parse_text_resultset_row(mysql_data, 0, session.col_count)
                    log_event("DATA", src_str, dst_str, f"Row: {row_data}", tx_id=session.tx_id, extra={"rows": row_data})

            # Special case for COM_STMT_PREPARE response
            if src_info in pending_prepares:
                if first_byte == 0x00 and len(mysql_data) >= 9:
                    stmt_id = struct.unpack('<I', mysql_data[1:5])[0]
                    num_params = struct.unpack('<H', mysql_data[7:9])[0]
                    query = pending_prepares.pop(src_info)
                    stmt_map[stmt_id] = {"query": query, "num_params": num_params, "col_types": []}
                    log_event("SQL", src_str, dst_str, f"Prepare OK: ID {stmt_id}", tx_id=session.tx_id)

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
