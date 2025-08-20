import machine
import time
import network
import ntptime
import ssd1306
import uasyncio as asyncio
import uos
import ujson
import _thread # 스레딩 모듈
import gc # Garbage Collector

# WDT (Watchdog Timer) 설정 - 20초
wdt = machine.WDT(timeout=320000)  # 20초 (20000ms)

# *** MQTT 라이브러리 임포트 (사용자 제공 라이브러리 기준) ***
# *** 'umqtt/simple.py' 파일이 기기에 존재해야 함 ***
try:
    from umqtt.simple import MQTTClient, MQTTException
except ImportError:
    print("오류: 'umqtt/simple.py' 라이브러리를 찾을 수 없습니다.")
    print("기기 파일 시스템에 라이브러리를 업로드하세요.")
    # 여기서 프로그램을 중단하거나, MQTT 기능 없이 계속 진행하도록 선택할 수 있습니다.
    # 예: raise ImportError("umqtt.simple not found")
    MQTTClient = None # MQTT 기능 비활성화
    MQTTException = Exception # 기본 Exception 사용

import ubinascii # Client ID 생성을 위해 추가

# --- 기본 설정 ---
machine.freq(240000000) # ESP32-S2 클럭 설정

# --- 사용자 설정 ---
# Wi-Fi 설정 (***사용자 환경에 맞게 수정***)
WIFI_SSID = "SK_4974_2.4G"      # <<<<< 실제 사용하는 Wi-Fi 이름으로 변경하세요
WIFI_PASSWORD = "BQP06@0276"  # <<<<< 실제 사용하는 Wi-Fi 비밀번호로 변경하세요

# MQTT 설정 (***사용자 환경에 맞게 수정***)
MQTT_BROKER = "spcwtech.mooo.com" # <<<<< MQTT 브로커 주소 (예: "192.168.1.100" 또는 "mqtt.eclipseprojects.io")
MQTT_PORT = 1883                  # <<<<< MQTT 브로커 포트 (기본값: 1883)
MQTT_USER = None                  # <<<<< MQTT 사용자 이름 (필요 없으면 None)
MQTT_PASSWORD = None                  # <<<<< MQTT 비밀번호 (필요 없으면 None)
# 고유한 클라이언트 ID 생성 (MAC 주소 기반)
CLIENT_ID =ubinascii.hexlify(machine.unique_id()).decode()
# *** Keep-Alive 설정 (제공된 라이브러리는 connect 시 사용) ***
MQTT_KEEP_ALIVE = 60              # MQTT Keep-Alive 간격 (초)
MQTT_RECONNECT_DELAY_S = 10           # MQTT 재연결 시도 간격 (초)

# MQTT 로그 설정
MQTT_LOG_ENABLED = True              # MQTT 로그 발행 활성화/비활성화 (False로 설정하면 로그 발행 중단)
MQTT_LOG_MAX_LENGTH = 200            # MQTT 로그 메시지 최대 길이 (바이트)
MQTT_LOG_LEVEL = "INFO"              # 로그 레벨: "DEBUG", "INFO", "WARNING", "ERROR"

# MQTT Heartbeat 설정
MQTT_HEARTBEAT_ENABLED = True        # Heartbeat 발행 활성화/비활성화
MQTT_HEARTBEAT_INTERVAL_SEC = 5     # Heartbeat 발행 간격 (초) - 기본 30초
MQTT_HEARTBEAT_PAYLOAD = "a"         # Heartbeat 메시지 내용

# MQTT 토픽 설정 (공통 포맷 적용)
MQTT_BASE_TOPIC = f"{CLIENT_ID}/DOSE"
MQTT_PUMP1_COMMAND_TOPIC = f"{MQTT_BASE_TOPIC}/con/pump1"
MQTT_PUMP2_COMMAND_TOPIC = f"{MQTT_BASE_TOPIC}/con/pump2"
MQTT_SCHEDULE_ADD_TOPIC = f"{MQTT_BASE_TOPIC}/con/schedule/add"
MQTT_SCHEDULE_DELETE_TOPIC = f"{MQTT_BASE_TOPIC}/con/schedule/delete"
MQTT_REQUEST_STATUS_TOPIC = f"{MQTT_BASE_TOPIC}/con/request_status"
MQTT_PUMP1_STATUS_TOPIC = f"{MQTT_BASE_TOPIC}/sta/pump1"
MQTT_PUMP2_STATUS_TOPIC = f"{MQTT_BASE_TOPIC}/sta/pump2"
MQTT_SCHEDULE_STATUS_TOPIC = f"{MQTT_BASE_TOPIC}/sta/schedules"
MQTT_ONLINE_STATUS_TOPIC = f"{MQTT_BASE_TOPIC}/sta/online"
MQTT_LOG_TOPIC = f"{MQTT_BASE_TOPIC}/sta/log" # 로그/에러 메시지 발행용
MQTT_HEARTBEAT_TOPIC = f"{CLIENT_ID}/DOSE/a" # Heartbeat 토픽 (폰 앱 공통)

# 핀 설정 (***사용하는 ESP32-S2 보드 및 연결에 맞게 반드시 수정***)
I2C_SCL_PIN = 9
I2C_SDA_PIN = 8
PUMP1_IN1_PIN = 4
PUMP1_IN2_PIN = 5
PUMP2_IN1_PIN = 6
PUMP2_IN2_PIN = 7
BUTTON_PINS = {
    'UP': 10,
    'DOWN': 11,
    'LEFT': 12,
    'RIGHT': 13,  # 40번 핀으로 변경
    'SELECT': 18,
    'BACK': 1
}

# 디스플레이 설정
SCREEN_WIDTH = 128
SCREEN_HEIGHT = 64
I2C_FREQ = 1600000 # I2C 클럭 800kHz (호환성 문제가 있다면 400000 또는 100000으로 낮춤)

# 펌프 작동 시간 기본값 (밀리초 단위)
DEFAULT_PUMP_DURATION_MS = 5000 # 예: 5초
MAX_PUMP_DURATION_SEC = 3600 # 최대 펌프 작동 시간 (초) - 스케줄 편집용
MIN_PUMP_DURATION_SEC = 1 # 최소 펌프 작동 시간 (초) - 스케줄 편집용

# 시간대 오프셋 (UTC+9 for KST)
TIMEZONE_OFFSET = 9 * 3600

# 스케줄 저장 파일명
SCHEDULE_FILENAME = "schedules.json"

# WiFi 연결 개선 설정
WIFI_RETRY_COUNT = 3
WIFI_RETRY_DELAYS = [1, 2, 5, 10, 20]
WIFI_RSSI_THRESHOLD = -70
WIFI_CONNECTION_TIMEOUT = 30
WIFI_MONITOR_INTERVAL = 60
WIFI_MAX_RSSI_HISTORY = 5

# ESP32 WiFi 최적화 설정
WIFI_TX_POWER = 8  # dBm (현재 설정값)
# TX Power 옵션 (ESP32-S2):
# - 20dBm: 최대 출력 (불안정할 수 있음)
# - 15dBm: 높은 출력 (일반적으로 안정)
# - 10dBm: 중간 출력 (안정성과 범위의 균형) ← 현재
# - 8dBm:  낮은 출력 (매우 안정적)
# - 5dBm:  최소 출력 (근거리용)
WIFI_RECONNECT_ATTEMPTS = 3  # 자동 재연결 시도 횟수
WIFI_CONNECTION_CHECK_INTERVAL = 500  # ms, 연결 상태 체크 간격

# 다중 네트워크 설정 (우선순위 순)
WIFI_NETWORKS = [
    (WIFI_SSID, WIFI_PASSWORD, 1, None, None),  # (ssid, password, priority, static_ip, gateway)
]

# DNS 서버 설정
WIFI_DNS_SERVERS = ["8.8.8.8", "1.1.1.1"]

# 버튼 스레드 설정
BUTTON_POLL_INTERVAL_MS = 5   # 10ms에서 5ms로 단축 (더 빠른 반응)
BUTTON_DEBOUNCE_MS = 15       # 20ms에서 15ms로 단축 (더 빠른 반응)

# --- 전역 변수 ---
i2c = None
oled = None
buttons = {} # Pin 객체 저장
pump1_in1, pump1_in2, pump2_in1, pump2_in2 = None, None, None, None
# PWM 객체를 관리하기 위한 전역 변수 추가
pump1_pwm, pump2_pwm = None, None
wlan = None
mqtt_client = None
mqtt_connected = False
mqtt_connection_attempt_time = 0 # 마지막 연결 시도 시간 기록
last_mqtt_publish_time = 0 # 주기적 상태 발행용
last_heartbeat_time = 0 # 마지막 Heartbeat 발행 시간

# WiFi 연결 관리 전역 변수
wifi_connection_attempts = 0
wifi_last_connection_time = 0
wifi_connection_stats = {'success': 0, 'failed': 0, 'total_time': 0}
wifi_retry_delays = [1, 2, 5, 10, 20]  # 지수 백오프
wifi_connection_state = {
    'status': 'disconnected',
    'ssid': '',
    'ip_address': '',
    'rssi': 0,
    'connection_time': 0,
    'last_error': '',
    'retry_count': 0
}
wifi_rssi_history = [0, 0, 0, 0, 0]  # 최근 5개 RSSI 값
wifi_rssi_index = 0
wifi_current_network_index = 0

schedules = {1: [], 2: []} # {pump_id: [(hour, minute, duration_ms, interval_days), ...]}
pump_tasks = {1: None, 2: None} # 현재 실행 중인 펌프 작업 (asyncio task)

current_screen = "MAIN" # UI 상태: MAIN, SELECT_PUMP, VIEW_SCHEDULE, ADD_SCHEDULE, PUMP_MENU, CALIBRATE_PUMP, CALIBRATE_INPUT
selected_pump = 1
manual_selected_pump = 1 # 수동 제어 화면에서 선택된 펌프
manual_pump_states = {1: False, 2: False} # 각 펌프의 수동 작동 상태 (True: 수동으로 켬)
schedule_cursor = 0
edit_hour, edit_minute, edit_duration_sec, edit_interval_days = 0, 0, 5, 1 # 기본값: 5초, 매일
edit_cursor_pos = 0 # 0: hour, 1: minute, 2: duration, 3: interval_days
editing_schedule_original = None # 수정 모드 추적용 변수 (초기값 None)

# Calibration 관련 전역 변수
pump_menu_cursor = 0  # 0: Schedule, 1: Calibration
calibrating_pump = 1  # 현재 캘리브레이션 중인 펌프
calibration_stage = 0  # 0: 준비, 1: 실행 중, 2: 입력 대기
calibration_start_time = 0
calibration_input_ml = 0  # 사용자가 입력한 실제 배출량 (ml)
calibration_input_cursor = 0  # 입력 자릿수 위치

# PWM 듀티 사이클 (기본값 - 최고값으로 설정)
pump_pwm_duty = {1: 1023, 2: 1023}  # 0-1023 범위, 최고값으로 설정

# Calibration 저장 파일명
CALIBRATION_FILENAME = "calibration.json"

# 스케줄 실행 기록 파일명
SCHEDULE_LOG_FILENAME = "schedule_log.json"

# --- 버튼 스레드용 전역 변수 ---
button_states = {name: {'pressed': False, 'last_change_time': 0, '_confirmed_state': False, '_debounce_start_time': 0} for name in BUTTON_PINS}
button_events = {name: False for name in BUTTON_PINS}
button_lock = _thread.allocate_lock()

# --- 화면 최적화용 전역 변수 ---
last_displayed_date = ""
last_displayed_time = ""
last_pump1_status = None
last_pump2_status = None
last_next_schedule = ""
last_wifi_status_str = "" # Wi-Fi/MQTT 상태 표시용
force_screen_update = True # 화면 전환 시 전체 업데이트 강제 플래그

# --- 유틸리티 함수 ---
def is_calibration_mode():
    """현재 캘리브레이션 모드인지 확인"""
    global current_screen
    return current_screen in ["CALIBRATE_PUMP", "CALIBRATE_INPUT"]

def safe_force_screen_update():
    """캘리브레이션 모드가 아닐 때만 화면 강제 업데이트"""
    global force_screen_update
    if not is_calibration_mode():
        force_screen_update = True
        return True
    else:
        log_message("DEBUG: Screen update blocked - in calibration mode", False)
        return False

def log_message(msg, publish_mqtt=True, level="INFO"):
    """콘솔과 MQTT로 로그 메시지 출력 (개선된 버전)"""
    print(msg)
    
    # MQTT 로그 발행 조건 확인
    if not publish_mqtt or not MQTT_LOG_ENABLED or not mqtt_connected or not mqtt_client:
        return
    
    # 로그 레벨 필터링
    if level == "DEBUG" and MQTT_LOG_LEVEL != "DEBUG":
        return
    
    try:
        # 메시지 길이 제한 (UTF-8 바이트 기준)
        msg_bytes = msg.encode('utf-8')
        if len(msg_bytes) > MQTT_LOG_MAX_LENGTH:
            # 메시지가 너무 긴 경우 자르고 "..." 추가
            truncated_msg = msg[:MQTT_LOG_MAX_LENGTH-10] + "...[truncated]"
            msg_bytes = truncated_msg.encode('utf-8')
            print(f"MQTT 로그 메시지 길이 제한으로 잘림: {len(msg.encode('utf-8'))} -> {len(msg_bytes)} bytes")
        
        # QoS 0으로 발행하여 블로킹 방지
        mqtt_client.publish(MQTT_LOG_TOPIC, msg_bytes, qos=0)
        
    except OSError as e:
        # 네트워크 오류 (연결 끊김 등)
        print(f"MQTT 로그 발행 실패 (OSError): {e}")
        # 연결 상태는 다른 곳에서 관리
    except MemoryError as e:
        # 메모리 부족
        print(f"MQTT 로그 발행 실패 (메모리 부족): {e}")
        gc.collect()  # 가비지 컬렉션 시도
    except Exception as e:
        # 기타 오류
        print(f"MQTT 로그 발행 실패: {e}")

# --- MQTT 관련 함수 ---
def mqtt_callback(topic, msg):
    """MQTT 메시지 수신 시 호출될 콜백 함수"""
    global schedules, current_screen, force_screen_update, schedule_cursor, selected_pump
    try:
        topic_str = topic.decode('utf-8')
        msg_str = msg.decode('utf-8')
        log_message(f"MQTT 수신: Topic='{topic_str}', Message='{msg_str}'", publish_mqtt=False)

        pump_id = -1
        if topic_str == MQTT_PUMP1_COMMAND_TOPIC: 
            pump_id = 1
        elif topic_str == MQTT_PUMP2_COMMAND_TOPIC: 
            pump_id = 2

        if pump_id != -1:
            if msg_str.upper() == "ON":
                if pump_tasks.get(pump_id) is None:
                    log_message(f"MQTT: P{pump_id} ON 요청 (1초간 실행)")
                    asyncio.create_task(run_pump_for_duration(pump_id, 1000))
                else: 
                    log_message(f"MQTT: P{pump_id} ON 요청 무시 (작동 중)")
            elif msg_str.upper() == "OFF":
                if pump_tasks.get(pump_id) is not None:
                    log_message(f"MQTT: P{pump_id} OFF 요청")
                    try:
                        pump_tasks[pump_id].cancel()
                    except asyncio.CancelledError:
                        pass
                    pump_tasks[pump_id] = None
                    pump_off(pump_id)
                    publish_pump_status(pump_id)
                    safe_force_screen_update()
                else:
                    log_message(f"MQTT: P{pump_id} OFF 요청 (이미 꺼짐)")
                    pump_off(pump_id)
                    publish_pump_status(pump_id)
                    publish_pump_status(pump_id)
            elif msg_str.upper().startswith("RUN:"):
                try:
                    duration_ms = int(msg_str.split(":")[1])
                    if duration_ms > 0:
                        if pump_tasks.get(pump_id) is None:
                            log_message(f"MQTT: P{pump_id} RUN 요청 ({duration_ms}ms)")
                            asyncio.create_task(run_pump_for_duration(pump_id, duration_ms))
                        else: 
                            log_message(f"MQTT: P{pump_id} RUN 요청 무시 (작동 중)")
                    else: 
                        log_message(f"MQTT: 잘못된 작동 시간 ({duration_ms}ms)")
                except (IndexError, ValueError) as e:
                    log_message(f"MQTT: RUN 명령어 형식 오류 '{msg_str}': {e}")
            else: 
                log_message(f"MQTT: 알 수 없는 P{pump_id} 명령어 '{msg_str}'")

        elif topic_str == MQTT_SCHEDULE_ADD_TOPIC:
            try:
                data = ujson.loads(msg_str)
                p_id = data.get('pump')
                h = data.get('hour')
                m = data.get('minute')
                dur_ms = data.get('duration_ms')
                interval_days = data.get('interval_days', 1)  # 기본값: 매일
                
                if p_id in [1, 2] and isinstance(h, int) and isinstance(m, int) and isinstance(dur_ms, int) and \
                   isinstance(interval_days, int) and 0 <= h < 24 and 0 <= m < 60 and dur_ms > 0 and interval_days >= 1:
                    new_schedule = (h, m, dur_ms, interval_days)
                    current_pump_schedules = schedules.setdefault(p_id, [])
                    
                    # 중복 체크 (시간만 체크, 기존 스케줄의 형식에 관계없이)
                    is_duplicate = False
                    for existing_schedule in current_pump_schedules:
                        if existing_schedule[0] == h and existing_schedule[1] == m:
                            is_duplicate = True
                            break
                    
                    if not is_duplicate:
                        current_pump_schedules.append(new_schedule)
                        log_message(f"MQTT: 스케줄 추가됨 - P{p_id}: {new_schedule}")
                        save_schedules()
                        safe_force_screen_update()
                    else:
                        log_message(f"MQTT: 스케줄 중복 - P{p_id} {h:02d}:{m:02d}")
                else: 
                    log_message(f"MQTT: 잘못된 스케줄 추가 데이터: {msg_str}")
            except Exception as e: 
                log_message(f"MQTT: 스케줄 추가 처리 오류: {e}")
                
        elif topic_str == MQTT_SCHEDULE_DELETE_TOPIC:
            try:
                data = ujson.loads(msg_str)
                p_id = data.get('pump')
                h = data.get('hour')
                m = data.get('minute')
                if p_id in [1, 2] and isinstance(h, int) and isinstance(m, int) and \
                   0 <= h < 24 and 0 <= m < 60:
                    current_pump_schedules = schedules.get(p_id, [])
                    schedule_to_delete = None
                    for sched in current_pump_schedules:
                        if sched[0] == h and sched[1] == m:
                            schedule_to_delete = sched
                            break
                    if schedule_to_delete:
                        current_pump_schedules.remove(schedule_to_delete)
                        log_message(f"MQTT: 스케줄 삭제됨 - P{p_id}: {schedule_to_delete}")
                        save_schedules()
                        safe_force_screen_update()
                        if current_screen == "VIEW_SCHEDULE" and selected_pump == p_id:
                            num_schedules_after_delete = len(schedules[p_id])
                            schedule_cursor = max(0, min(schedule_cursor, num_schedules_after_delete - 1))
                    else: 
                        log_message(f"MQTT: 삭제할 스케줄 없음 - P{p_id} {h:02d}:{m:02d}")
                else: 
                    log_message(f"MQTT: 잘못된 스케줄 삭제 데이터: {msg_str}")
            except Exception as e:
                log_message(f"MQTT: 스케줄 삭제 처리 오류: {e}")
                
        elif topic_str == MQTT_REQUEST_STATUS_TOPIC:
            log_message("MQTT: 상태 정보 요청 수신")
            publish_all_status()
            
    except Exception as e:
        log_message(f"MQTT 콜백 처리 중 오류: {e}")
    finally:
        gc.collect()

def connect_mqtt():
    """MQTT 브로커에 연결하고 구독 (라이브러리 호환)"""
    global mqtt_client, mqtt_connected, force_screen_update
    
    if not wlan or not wlan.isconnected():
        log_message("MQTT 연결 실패: Wi-Fi 연결 안됨", False)
        mqtt_connected = False
        return False

    if mqtt_client is None:
        if MQTTClient is None:
            return False
        log_message(f"MQTT Client 생성: ID='{CLIENT_ID}', Broker='{MQTT_BROKER}'")
        try:
            mqtt_client = MQTTClient(CLIENT_ID, MQTT_BROKER, port=MQTT_PORT, 
                                     user=MQTT_USER, password=MQTT_PASSWORD,
                                     keepalive=MQTT_KEEP_ALIVE)
            mqtt_client.set_callback(mqtt_callback)
        except Exception as e:
            log_message(f"MQTT Client 생성 실패: {e}", False)
            mqtt_client = None
            mqtt_connected = False
            return False

    log_message("MQTT 브로커 연결 시도...")
    try:
        mqtt_client.connect()
        log_message("MQTT 연결 성공")
        mqtt_connected = True
        safe_force_screen_update()

        topics_to_subscribe = [
            MQTT_PUMP1_COMMAND_TOPIC, MQTT_PUMP2_COMMAND_TOPIC,
            MQTT_SCHEDULE_ADD_TOPIC, MQTT_SCHEDULE_DELETE_TOPIC,
            MQTT_REQUEST_STATUS_TOPIC
        ]
        for topic in topics_to_subscribe:
            mqtt_client.subscribe(topic, qos=0)
            log_message(f"구독 완료: {topic}")

        publish_all_status()
        publish_status(MQTT_ONLINE_STATUS_TOPIC, "true", retain=True)
        if oled:
            oled.text("MQTT Ready!", 0, 40)
            oled.show()
            time.sleep(1.5)
        return True
        
    except Exception as e:
        log_message(f"MQTT 연결 실패: {e}")
        mqtt_connected = False
        try: 
            mqtt_client.disconnect()
        except: 
            pass
        mqtt_client = None
        if oled: 
            oled.text(f"MQTT Err", 0, 40)
            oled.show()
            time.sleep(2)
        return False
    finally:
        safe_force_screen_update()

def publish_status(topic, payload, retain=False):
    """MQTT 상태 발행 헬퍼 함수 (QoS 0 사용)"""
    global mqtt_connected, force_screen_update, mqtt_client, mqtt_connection_attempt_time
    
    if mqtt_connected and mqtt_client:
        try:
            mqtt_client.publish(topic.encode('utf-8'), payload.encode('utf-8'), retain=retain, qos=0)
        except OSError as e:
            log_message(f"MQTT 발행 오류 (OSError on {topic}): {e}. 연결 끊김 가능성.")
            mqtt_connection_attempt_time = time.ticks_ms()
        except Exception as e:
            log_message(f"MQTT 발행 중 오류 ({topic}): {e}")

def publish_pump_status(pump_id):
    """특정 펌프의 상태를 MQTT로 발행 (QoS 0)"""
    status = "ON" if pump_tasks.get(pump_id) is not None else "OFF"
    topic = MQTT_PUMP1_STATUS_TOPIC if pump_id == 1 else MQTT_PUMP2_STATUS_TOPIC
    publish_status(topic, status, retain=True)

def publish_schedule_status():
    """현재 스케줄 목록을 MQTT로 발행 (QoS 0)"""
    if not (mqtt_connected and mqtt_client): 
        return
    try:
        schedules_str_keys = {str(k): v for k, v in schedules.items()}
        payload = ujson.dumps(schedules_str_keys)
        publish_status(MQTT_SCHEDULE_STATUS_TOPIC, payload, retain=True)
    except Exception as e:
        log_message(f"스케줄 상태 발행 오류: {e}")

def publish_all_status():
    """모든 현재 상태를 MQTT로 발행 (QoS 0)"""
    if not (mqtt_connected and mqtt_client): 
        return
    log_message("전체 상태 MQTT 발행 시도 (QoS 0)...", False)
    publish_pump_status(1)
    publish_pump_status(2)
    publish_schedule_status()

def publish_heartbeat():
    """Heartbeat 메시지를 MQTT로 발행"""
    global last_heartbeat_time
    if not (mqtt_connected and mqtt_client) or not MQTT_HEARTBEAT_ENABLED:
        return
    
    current_time = time.ticks_ms()
    if time.ticks_diff(current_time, last_heartbeat_time) >= MQTT_HEARTBEAT_INTERVAL_SEC * 1000:
        try:
            # Heartbeat 메시지 발행 (retain=False, QoS=0)
            publish_status(MQTT_HEARTBEAT_TOPIC, MQTT_HEARTBEAT_PAYLOAD, retain=False)
            last_heartbeat_time = current_time
            log_message(f"Heartbeat sent: {MQTT_HEARTBEAT_PAYLOAD}", level="DEBUG")
        except Exception as e:
            log_message(f"Heartbeat 발행 실패: {e}", level="WARNING")

# --- 스케줄 저장 및 로드 ---
# (save_schedules 내부에서 publish_schedule_status 호출됨)
def save_schedules():
    """현재 스케줄을 파일에 저장"""
    global schedules
    log_message(f"'{SCHEDULE_FILENAME}'에 스케줄 저장 시도...", publish_mqtt=False)
    try:
        schedules_to_save = {}
        for pump_id, sched_list in schedules.items():
            sorted_list = sorted([tuple(s) for s in sched_list], key=lambda x: (x[0], x[1]))
            schedules_to_save[str(pump_id)] = sorted_list
        
        with open(SCHEDULE_FILENAME, 'w') as f:
            ujson.dump(schedules_to_save, f)
        log_message("스케줄 저장 완료.", publish_mqtt=False)
        
        schedules = {int(k): v for k, v in schedules_to_save.items()}
        publish_schedule_status()
        gc.collect()
    except Exception as e:
        log_message(f"스케줄 저장 실패: {e}")
        if oled: 
            oled.fill(1)
            oled.text("Save Error!", 5, 25, 0)
            oled.show()
            time.sleep(2)
            oled.fill(0)

def load_schedules():
    """파일에서 스케줄을 로드하여 전역 변수 업데이트"""
    global schedules
    log_message(f"'{SCHEDULE_FILENAME}'에서 스케줄 로드 시도...", publish_mqtt=False)
    loaded_schedules = {}
    try:
        uos.stat(SCHEDULE_FILENAME)
        with open(SCHEDULE_FILENAME, 'r') as f:
            loaded_data = ujson.load(f)
            for k_str, v_list in loaded_data.items():
                try:
                    k_int = int(k_str)
                    if k_int not in [1, 2]:
                        log_message(f"경고: 잘못된 펌프 ID '{k_str}'. 무시.", publish_mqtt=False)
                        continue
                    
                    valid_schedules = []
                    if isinstance(v_list, list):
                        for item in v_list:
                            if isinstance(item, (list, tuple)):
                                # 기존 3개 요소 형식 (hour, minute, duration_ms) 지원
                                if len(item) == 3 and all(isinstance(x, int) for x in item) and \
                                   0 <= item[0] < 24 and 0 <= item[1] < 60 and item[2] > 0:
                                    # 기본 간격 1일 추가
                                    valid_schedules.append(tuple(list(item) + [1]))
                                # 새로운 4개 요소 형식 (hour, minute, duration_ms, interval_days) 지원
                                elif len(item) == 4 and all(isinstance(x, int) for x in item) and \
                                     0 <= item[0] < 24 and 0 <= item[1] < 60 and item[2] > 0 and item[3] >= 1:
                                    valid_schedules.append(tuple(item))
                                else:
                                    log_message(f"경고: P{k_int} 잘못된 항목 {item}. 무시.", publish_mqtt=False)
                            else:
                                log_message(f"경고: P{k_int} 잘못된 항목 {item}. 무시.", publish_mqtt=False)
                    else: 
                        log_message(f"경고: P{k_int} 스케줄이 리스트 아님 {v_list}. 무시.", publish_mqtt=False)
                    
                    loaded_schedules[k_int] = sorted(valid_schedules, key=lambda x: (x[0], x[1]))
                except ValueError: 
                    log_message(f"경고: 잘못된 키 '{k_str}'. 무시.", publish_mqtt=False)
        
        if loaded_schedules:
            schedules = loaded_schedules
            if 1 not in loaded_schedules: 
                schedules[1] = []
            if 2 not in loaded_schedules: 
                schedules[2] = []
            log_message("스케줄 로드 완료.", publish_mqtt=False)
        else:
            log_message("로드된 스케줄 비어있음. 기본값 사용.", publish_mqtt=False)
            schedules = {1: [], 2: []}
            
    except OSError:
        log_message(f"'{SCHEDULE_FILENAME}' 파일 없음. 기본값 사용.", publish_mqtt=False)
        schedules = {1: [], 2: []}
    except Exception as e:
        log_message(f"스케줄 로드 실패: {e}. 기본값 사용.")
        schedules = {1: [], 2: []}
    finally:
        gc.collect()

# --- 스케줄 실행 기록 관리 ---
def load_schedule_log():
    """스케줄 실행 기록 로드"""
    try:
        with open(SCHEDULE_LOG_FILENAME, 'r') as f:
            return ujson.load(f)
    except:
        return {}

def save_schedule_log(schedule_log):
    """스케줄 실행 기록 저장"""
    try:
        with open(SCHEDULE_LOG_FILENAME, 'w') as f:
            ujson.dump(schedule_log, f)
    except Exception as e:
        log_message(f"스케줄 실행 기록 저장 실패: {e}", False)

def should_run_schedule(pump_id, hour, minute, interval_days):
    """스케줄이 실행되어야 하는지 확인 (날짜 간격 체크)"""
    if interval_days == 1:  # 매일 실행
        return True
    
    schedule_log = load_schedule_log()
    schedule_key = f"P{pump_id}_{hour:02d}_{minute:02d}"
    
    now = get_local_time()
    current_date = f"{now[0]}-{now[1]:02d}-{now[2]:02d}"
    
    if schedule_key not in schedule_log:
        # 처음 실행
        return True
    
    last_run_date = schedule_log[schedule_key]
    
    try:
        # 날짜 차이 계산
        last_year, last_month, last_day = map(int, last_run_date.split('-'))
        current_year, current_month, current_day = now[0], now[1], now[2]
        
        # 간단한 날짜 차이 계산 (년도가 바뀌지 않는다고 가정)
        import time
        last_timestamp = time.mktime((last_year, last_month, last_day, 0, 0, 0, 0, 0))
        current_timestamp = time.mktime((current_year, current_month, current_day, 0, 0, 0, 0, 0))
        days_diff = int((current_timestamp - last_timestamp) / 86400)  # 86400초 = 1일
        
        return days_diff >= interval_days
    except:
        # 날짜 파싱 오류 시 실행
        return True

def record_schedule_run(pump_id, hour, minute):
    """스케줄 실행 기록"""
    schedule_log = load_schedule_log()
    schedule_key = f"P{pump_id}_{hour:02d}_{minute:02d}"
    
    now = get_local_time()
    current_date = f"{now[0]}-{now[1]:02d}-{now[2]:02d}"
    
    schedule_log[schedule_key] = current_date
    save_schedule_log(schedule_log)


# --- 하드웨어 초기화 ---
def init_hardware():
    global i2c, oled, buttons, pump1_in1, pump1_in2, pump2_in1, pump2_in2
    log_message("하드웨어 초기화 중...", False)
    
    try: 
        machine.Pin(I2C_SCL_PIN, machine.Pin.IN)
        machine.Pin(I2C_SDA_PIN, machine.Pin.IN)
    except: 
        pass
    
    try:
        i2c = machine.I2C(0, scl=machine.Pin(I2C_SCL_PIN), sda=machine.Pin(I2C_SDA_PIN), freq=I2C_FREQ)
        devices = i2c.scan()
        log_message(f"I2C devices: {[hex(d) for d in devices]}", False)
        
        addr = 0x3c if 0x3c in devices else (0x3d if 0x3d in devices else None)
        if addr:
            oled = ssd1306.SSD1306_I2C(SCREEN_WIDTH, SCREEN_HEIGHT, i2c, addr=addr)
            oled.fill(0)
            oled.text("OLED OK", 0, 0)
            oled.show()
            time.sleep(1)
        else: 
            log_message("OLED 없음.", False)
            oled = None
    except Exception as e: 
        log_message(f"I2C/OLED 오류: {e}", False)
        oled = None

    try:
        pump1_in1 = machine.Pin(PUMP1_IN1_PIN, machine.Pin.OUT, value=0)
        pump1_in2 = machine.Pin(PUMP1_IN2_PIN, machine.Pin.OUT, value=0)
        pump2_in1 = machine.Pin(PUMP2_IN1_PIN, machine.Pin.OUT, value=0)
        pump2_in2 = machine.Pin(PUMP2_IN2_PIN, machine.Pin.OUT, value=0)
    except Exception as e: 
        log_message(f"펌프 핀 오류: {e}", False)
    
    buttons.clear()
    log_message("버튼 핀 초기화 시작...", False)
    
    for name, pin_num in BUTTON_PINS.items():
        try: 
            # 핀 생성
            pin = machine.Pin(pin_num, machine.Pin.IN, machine.Pin.PULL_UP)
            buttons[name] = pin
            
            # 풀업 저항 안정화를 위한 딜레이
            time.sleep_ms(10)
            
            # 여러 번 읽어서 안정된 값 확인
            readings = []
            for _ in range(5):
                readings.append(pin.value())
                time.sleep_ms(1)
            
            # 가장 많이 나온 값을 초기값으로 사용
            initial_value = max(set(readings), key=readings.count)
            log_message(f"Button {name} (pin {pin_num}): readings={readings}, initial={initial_value}", False)
            
            # SELECT 버튼 특별 확인
            if name == 'SELECT':
                log_message(f"SELECT button pin {pin_num} initialized with value {initial_value}", False)
                # 테스트로 몇 번 더 읽어보기
                test_readings = [pin.value() for _ in range(10)]
                log_message(f"SELECT button test readings: {test_readings}", False)
            
            # 초기값이 0이면 (눌린 상태면) 경고
            if initial_value == 0:
                log_message(f"WARNING: Button {name} shows pressed state at startup!", False)
                
        except (ValueError, TypeError) as e: 
            log_message(f"버튼 핀 {pin_num} ({name}) 오류: {e}", False)
            buttons[name] = None
    
    # 모든 버튼 초기화 후 추가 안정화 시간
    time.sleep_ms(100)
    log_message("버튼 핀 초기화 완료.", False)
    
    log_message("하드웨어 초기화 완료.", False)


# --- 펌프 제어 ---
PUMP_PWM_FREQ = 10000  # Hz, 펌프 PWM 주파수
PUMP_PWM_DUTY = 1023   # 0~1023 (50% duty, 필요시 조정)
PUMP_CAL_FILE = "pump_cal.json"
# 펌프별 1ml 펌핑에 필요한 시간(ms), 기본값 1000ms (1초)
pump_ml_ms = {1: 1000, 2: 1000}

def load_pump_cal():
    global pump_ml_ms
    try:
        with open(PUMP_CAL_FILE, "r") as f:
            pump_ml_ms.update(ujson.load(f))
    except Exception:
        pass

def save_pump_cal():
    try:
        with open(PUMP_CAL_FILE, "w") as f:
            ujson.dump(pump_ml_ms, f)
    except Exception:
        pass

def load_calibration():
    """캘리브레이션 데이터 로드"""
    global pump_pwm_duty
    try:
        with open(CALIBRATION_FILENAME, "r") as f:
            data = ujson.load(f)
            loaded_pwm = data.get('pump_pwm_duty', {})
            # 키를 정수로 통일해서 로드
            pump_pwm_duty.update({int(k): v for k, v in loaded_pwm.items()})
            log_message(f"캘리브레이션 데이터 로드됨: {pump_pwm_duty}", publish_mqtt=False)
            
            # PWM 값 로드 로그 메시지 추가
            for pump_id, pwm_value in pump_pwm_duty.items():
                log_message(f"PWM LOADED: Pump {pump_id} PWM duty = {pwm_value}", True)
                
    except Exception as e:
        log_message(f"캘리브레이션 데이터 로드 실패: {e}", publish_mqtt=False)

def save_calibration():
    """캘리브레이션 데이터 저장"""
    try:
        # 키를 정수로 통일해서 저장
        clean_pump_pwm_duty = {int(k): v for k, v in pump_pwm_duty.items()}
        data = {
            'pump_pwm_duty': clean_pump_pwm_duty
        }
        with open(CALIBRATION_FILENAME, "w") as f:
            ujson.dump(data, f)
        log_message(f"캘리브레이션 데이터 저장됨: {clean_pump_pwm_duty}", publish_mqtt=False)
        
        # PWM 저장 로그 메시지 추가
        for pump_id, pwm_value in clean_pump_pwm_duty.items():
            log_message(f"PWM SAVED: Pump {pump_id} PWM duty = {pwm_value}", True)
            
    except Exception as e:
        log_message(f"캘리브레이션 데이터 저장 실패: {e}", publish_mqtt=False)

def calibrate_pump(pump_id, ml_amount=200):
    """
    보정 모드: ml_amount(예: 200ml) 펌핑에 걸린 시간(ms)을 측정하여 1ml당 ms를 계산/저장
    사용법: 펌프에 물통 연결 후 호출, 시작/정지 버튼 등으로 측정
    """
    import sys
    print(f"펌프 {pump_id} 보정 시작: {ml_amount}ml 펌핑")
    pump_pin = pump1_in1 if pump_id == 1 else pump2_in1
    pwm = machine.PWM(pump_pin, freq=PUMP_PWM_FREQ, duty=0)
    input("엔터를 누르면 펌프가 시작됩니다.")
    start = time.ticks_ms()
    pwm.duty(PUMP_PWM_DUTY)
    input(f"{ml_amount}ml 도달 시 엔터를 누르세요.")
    pwm.duty(0)
    end = time.ticks_ms()
    elapsed = time.ticks_diff(end, start)
    per_ml = elapsed // ml_amount
    pump_ml_ms[pump_id] = per_ml
    save_pump_cal()
    print(f"펌프 {pump_id} 보정 완료: {per_ml} ms/ml")
    pwm.deinit()

def pump_on(pump_id):
    """펌프를 PWM으로 동작"""
    global pump1_pwm, pump2_pwm
    log_message(f"DEBUG: pump_on called for pump {pump_id}, PWM duty: {pump_pwm_duty[pump_id]}", False)
    
    if pump_id == 1 and pump1_in1 and pump1_in2:
        pump1_in2.off()
        if pump1_pwm is not None:
            pump1_pwm.deinit()
        pump1_pwm = machine.PWM(pump1_in1, freq=PUMP_PWM_FREQ, duty=int(pump_pwm_duty[pump_id]))
        log_message(f"DEBUG: Pump 1 PWM started with duty {int(pump_pwm_duty[pump_id])}", False)
    elif pump_id == 2 and pump2_in1 and pump2_in2:
        pump2_in2.off()
        if pump2_pwm is not None:
            pump2_pwm.deinit()
        pump2_pwm = machine.PWM(pump2_in1, freq=PUMP_PWM_FREQ, duty=int(pump_pwm_duty[pump_id]))
        log_message(f"DEBUG: Pump 2 PWM started with duty {int(pump_pwm_duty[pump_id])}", False)
    else:
        log_message(f"ERROR: pump_on failed for pump {pump_id} - pins not initialized", False)

def pump_off(pump_id):
    """PWM으로 펌프를 끔"""
    global pump1_pwm, pump2_pwm
    if pump_id == 1 and pump1_in1 and pump1_in2:
        if pump1_pwm is not None:
            pump1_pwm.deinit()
            pump1_pwm = None
        pump1_in1.off()
        pump1_in2.off()
    elif pump_id == 2 and pump2_in1 and pump2_in2:
        if pump2_pwm is not None:
            pump2_pwm.deinit()
            pump2_pwm = None
        pump2_in1.off()
        pump2_in2.off()

async def run_pump_ml(pump_id, ml):
    """ml 단위로 펌프를 동작"""
    ms = int(pump_ml_ms.get(pump_id, 1000)) * ml
    await run_pump_for_duration(pump_id, ms)

# --- 캘리브레이션 스레드 관련 전역 변수 ---
calibration_thread_running = False
calibration_thread_stop_flag = False
calibration_elapsed_sec = 0  # 스레드에서 업데이트되는 경과 시간 (초)
calibration_remaining_sec = 50  # 스레드에서 업데이트되는 남은 시간 (초)

def calibration_pump_thread(pump_id, duration_ms):
    """캘리브레이션용 펌프 실행 스레드 함수"""
    global calibration_thread_running, calibration_thread_stop_flag, calibration_stage, current_screen, pump_tasks
    global calibration_elapsed_sec, calibration_remaining_sec
    
    calibration_thread_running = True
    calibration_thread_stop_flag = False
    calibration_elapsed_sec = 0
    calibration_remaining_sec = duration_ms // 1000
    
    log_message(f"DEBUG: calibration_pump_thread started for pump {pump_id}, duration {duration_ms}ms", False)
    
    try:
        # 펌프 시작
        log_message(f"DEBUG: About to call pump_on({pump_id}) in thread", False)
        pump_on(pump_id)
        log_message(f"DEBUG: pump_on({pump_id}) called successfully in thread!", False)
        
        # 시작 시간 기록
        start_time = time.ticks_ms()
        check_interval_ms = 50
        
        while True:
            time.sleep_ms(check_interval_ms)
            
            # 실제 경과 시간 계산
            current_time = time.ticks_ms()
            elapsed_ms = time.ticks_diff(current_time, start_time)
            
            # 전역 변수 업데이트 (화면 표시용)
            calibration_elapsed_sec = elapsed_ms // 1000
            calibration_remaining_sec = max(0, (duration_ms - elapsed_ms) // 1000)
            
            # 1초마다 진행상황 로그
            if elapsed_ms % 1000 < check_interval_ms:  # 1초 근처에서만 로그
                log_message(f"DEBUG: Calibration running - {calibration_elapsed_sec}s elapsed, {calibration_remaining_sec}s remaining", False)
            
            # 종료 조건 체크
            if elapsed_ms >= duration_ms or calibration_thread_stop_flag:
                break
        
        if calibration_thread_stop_flag:
            log_message(f"P{pump_id} calibration stopped by user after {elapsed_ms}ms")
        else:
            log_message(f"P{pump_id} calibration completed after {duration_ms}ms")
            
        # 완료 상태로 변경
        calibration_stage = 2
        
        # 자동으로 입력 화면으로 이동 (중단되지 않았을 때만)
        if not calibration_thread_stop_flag:
            current_screen = "CALIBRATE_INPUT"
            log_message("DEBUG: Calibration completed - moved to input screen", False)
            
    except Exception as e:
        log_message(f"P{pump_id} error during calibration thread: {e}")
        calibration_stage = 2
        current_screen = "CALIBRATE_INPUT"
        
    finally:
        # 펌프 정지
        log_message(f"DEBUG: About to call pump_off({pump_id}) in thread", False)
        pump_off(pump_id)
        log_message(f"DEBUG: pump_off({pump_id}) called successfully in thread!", False)
        
        calibration_thread_running = False
        log_message(f"DEBUG: calibration_pump_thread finished for pump {pump_id}", False)

# --- 기존 run_calibration_pump 함수를 백업용으로 유지하되 사용하지 않음 ---
async def run_calibration_pump_backup(pump_id, duration_ms):
    """캘리브레이션용 펌프 실행 함수 (백업용 - 현재 사용 안함)"""
    global pump_tasks, force_screen_update, calibration_stage, current_screen
    log_message(f"DEBUG: run_calibration_pump called for pump {pump_id}, duration {duration_ms}ms", False)
    
    if pump_id not in [1, 2]: 
        log_message(f"ERROR: Invalid pump_id {pump_id}", False)
        return
    if pump_tasks.get(pump_id) is not None:
        log_message(f"P{pump_id} calibration request ignored, already running.", False)
        return

    task = asyncio.current_task()
    pump_tasks[pump_id] = task
    force_screen_update = True
    log_message(f"P{pump_id} Calibration ON for {duration_ms}ms")

    try:
        log_message(f"DEBUG: About to call pump_on({pump_id})", False)
        pump_on(pump_id)
        log_message(f"DEBUG: pump_on({pump_id}) called successfully!", False)
        log_message(f"DEBUG: Starting sleep for {duration_ms}ms", False)
        await asyncio.sleep_ms(duration_ms)
        log_message(f"P{pump_id} Calibration completed after {duration_ms}ms")
        calibration_stage = 2  # 완료 상태로 변경
        # 캘리브레이션 완료 시 자동으로 입력 화면으로 이동
        current_screen = "CALIBRATE_INPUT"
        if oled:
            display_calibrate_input_screen()
            log_message("DEBUG: Calibration completed - moved to input screen", False)
    except asyncio.CancelledError:
        log_message(f"P{pump_id} calibration cancelled.")
        calibration_stage = 2  # 취소되어도 입력 단계로 이동
        # 캘리브레이션 취소 시에는 입력 화면으로 이동하지 않음 (이미 버튼 핸들러에서 처리됨)
        if oled and current_screen == "CALIBRATE_PUMP":
            display_calibrate_pump_screen()
            log_message("DEBUG: Calibration cancelled - screen updated", False)
    except Exception as e:
        log_message(f"P{pump_id} error during calibration: {e}")
        calibration_stage = 2
        # 에러 시에는 입력 화면으로 이동
        current_screen = "CALIBRATE_INPUT"
        if oled:
            display_calibrate_input_screen()
            log_message("DEBUG: Calibration error - moved to input screen", False)
    finally:
        log_message(f"DEBUG: About to call pump_off({pump_id})", False)
        pump_off(pump_id)
        log_message(f"DEBUG: pump_off({pump_id}) called successfully!", False)
        if pump_tasks.get(pump_id) == task:
            pump_tasks[pump_id] = None
        force_screen_update = True

# --- 네트워크 및 시간 동기화 ---
def measure_wifi_signal_strength():
    """WiFi 신호 강도 측정 및 기록"""
    global wifi_rssi_history, wifi_rssi_index
    try:
        if wlan and wlan.isconnected():
            rssi = wlan.status('rssi')
            wifi_rssi_history[wifi_rssi_index] = rssi
            wifi_rssi_index = (wifi_rssi_index + 1) % WIFI_MAX_RSSI_HISTORY
            wifi_connection_state['rssi'] = rssi
            return rssi
    except:
        pass
    return 0

def get_average_rssi():
    """평균 RSSI 계산"""
    valid_values = [r for r in wifi_rssi_history if r != 0]
    if valid_values:
        return sum(valid_values) // len(valid_values)
    return 0

def should_attempt_wifi_reconnect():
    """재연결 필요성 판단"""
    if not wlan or not wlan.isconnected():
        return True
    
    avg_rssi = get_average_rssi()
    if avg_rssi < WIFI_RSSI_THRESHOLD:
        log_message(f"WiFi signal weak: {avg_rssi}dBm, threshold: {WIFI_RSSI_THRESHOLD}dBm")
        return True
    
    return False

async def connect_wifi_single_attempt(ssid, password, timeout=30):
    """단일 WiFi 연결 시도 (ESP32 최적화)"""
    global wlan, wifi_connection_state
    
    try:
        # 네트워크 인터페이스 완전 초기화
        if wlan is None:
            wlan = network.WLAN(network.STA_IF)
        
        # WiFi 완전 리셋 (internal error 방지)
        try:
            wlan.active(False)
            await asyncio.sleep_ms(100)
            wlan.active(True)
            await asyncio.sleep_ms(500)  # 활성화 대기
        except Exception as e:
            log_message(f"WiFi 활성화 오류: {e}")
            # 새로운 WLAN 객체 생성
            wlan = network.WLAN(network.STA_IF)
            wlan.active(True)
            await asyncio.sleep_ms(500)
        
        # ESP32 WiFi 설정 최적화
        try:
            # TX 파워 설정 (ESP32-S2 최적화)
            wlan.config(txpower=WIFI_TX_POWER)
            log_message(f"WiFi TX Power set to {WIFI_TX_POWER}dBm")
            
            # 기타 WiFi 설정 최적화
            wlan.config(reconnects=1)  # 자동 재연결 시도 횟수 (너무 많으면 문제)
            wlan.config(hostname=f"ESP32-{CLIENT_ID[-6:]}")  # 호스트명 설정
            
            # ESP32 특화 설정
            try:
                wlan.config(dhcp_hostname=f"ESP32-{CLIENT_ID[-6:]}")
                wlan.config(pm=wlan.PM_NONE)  # 전력 관리 비활성화 (연결 안정성 향상)
            except:
                pass  # 지원하지 않는 설정은 무시
            
        except Exception as e:
            log_message(f"WiFi 설정 오류 (무시): {e}")
        
        # WiFi 네트워크 스캔으로 대상 네트워크 확인
        try:
            log_message("WiFi 네트워크 스캔 중...")
            networks = wlan.scan()
            target_found = False
            
            for net in networks:
                net_ssid = net[0].decode('utf-8') if isinstance(net[0], bytes) else str(net[0])
                net_rssi = net[3]
                net_auth = net[4]
                
                if net_ssid == ssid:
                    target_found = True
                    log_message(f"대상 네트워크 발견: {net_ssid}, RSSI: {net_rssi}dBm, Auth: {net_auth}")
                    break
            
            if not target_found:
                log_message(f"경고: 대상 네트워크 '{ssid}'를 찾을 수 없습니다!")
                log_message("사용 가능한 네트워크:")
                for net in networks[:5]:  # 상위 5개만 표시
                    net_ssid = net[0].decode('utf-8') if isinstance(net[0], bytes) else str(net[0])
                    log_message(f"  - {net_ssid} (RSSI: {net[3]}dBm)")
                    
        except Exception as e:
            log_message(f"WiFi 스캔 오류 (무시): {e}")
        
        # 기존 연결 안전하게 해제
        try:
            if wlan.isconnected():
                wlan.disconnect()
                await asyncio.sleep_ms(1000)  # 연결 해제 대기 시간 증가
        except Exception as e:
            log_message(f"WiFi 연결 해제 오류 (무시): {e}")
        
        wifi_connection_state['status'] = 'connecting'
        wifi_connection_state['ssid'] = ssid
        wifi_connection_state['last_error'] = ''
        
        log_message(f"WiFi 연결 시도: {ssid}")
        if oled:
            oled.fill(0)
            oled.text("Connecting WiFi", 0, 0)
            oled.text(ssid[:16], 0, 10)
            oled.show()
        
        # WiFi 연결 시도
        log_message(f"WiFi 연결 시작: {ssid} (TX Power: 10dBm)")
        
        try:
            wlan.connect(ssid, password)
        except Exception as e:
            log_message(f"WiFi 연결 명령 실패: {e}")
            return False
        
        start_time = time.ticks_ms()
        
        # 연결 대기 (더 세밀한 상태 체크)
        connection_check_interval = 500  # 0.5초마다 체크
        last_status = None
        
        while not wlan.isconnected() and time.ticks_diff(time.ticks_ms(), start_time) < timeout * 1000:
            elapsed = time.ticks_diff(time.ticks_ms(), start_time) // 1000
            
            # WiFi 상태 체크
            try:
                current_status = wlan.status()
                if current_status != last_status:
                    status_msg = {
                        0: "IDLE",
                        1: "CONNECTING", 
                        2: "WRONG_PASSWORD",
                        3: "NO_AP_FOUND",
                        4: "CONNECT_FAIL",
                        5: "GOT_IP",
                        15: "TIMEOUT",
                        201: "BEACON_TIMEOUT", 
                        202: "NO_AP_FOUND_W",
                        203: "AUTH_FAIL",
                        204: "ASSOC_FAIL",
                        205: "HANDSHAKE_TIMEOUT",
                        1001: "CONNECTING_INTERNAL",
                        1010: "CONNECTED_STABLE"  # 안정적 연결 상태
                    }.get(current_status, f"UNKNOWN({current_status})")
                    log_message(f"WiFi Status: {status_msg}")
                    last_status = current_status
                    
                    # 특정 오류 상태에서 즉시 중단
                    if current_status in [2, 3, 4]:  # 비밀번호 오류, AP 없음, 연결 실패
                        wifi_connection_state['last_error'] = status_msg
                        log_message(f"WiFi 연결 실패: {status_msg}")
                        
                        # 비밀번호 오류인 경우 추가 정보 제공
                        if current_status == 2:
                            log_message(f"비밀번호 확인 필요 (길이: {len(password)})")
                        
                        return False
                        
            except Exception as e:
                log_message(f"WiFi 상태 체크 오류: {e}")
            
            print('.', end='')
            if oled:
                dots = '.' * (elapsed % 4)
                oled.fill_rect(0, 20, SCREEN_WIDTH, 8, 0)
                oled.text(f"Wait {elapsed}s{dots}", 0, 20)
                # 상태 표시 추가
                if last_status is not None:
                    status_text = {0: "IDLE", 1: "CONN", 5: "IP"}.get(last_status, "WAIT")
                    oled.text(status_text, 80, 20)
                oled.show()
            
            await asyncio.sleep_ms(connection_check_interval)
        
        print()
        
        if wlan.isconnected():
            # 연결 성공
            ip_addr = wlan.ifconfig()[0]
            wifi_connection_state['status'] = 'connected'
            wifi_connection_state['ip_address'] = ip_addr
            wifi_connection_state['connection_time'] = time.ticks_ms()
            
            # 신호 강도 측정
            measure_wifi_signal_strength()
            
            log_message(f'WiFi 연결 성공: {ssid} -> {ip_addr} (RSSI: {wifi_connection_state["rssi"]}dBm)')
            
            if oled:
                oled.fill(0)
                oled.text("WiFi Connected!", 0, 0)
                oled.text(ssid[:16], 0, 10)
                oled.text(ip_addr, 0, 20)
                oled.text(f"RSSI:{wifi_connection_state['rssi']}dBm", 0, 30)
                oled.show()
                await asyncio.sleep(2)
            
            return True
        else:
            # 연결 실패
            wifi_connection_state['status'] = 'failed'
            wifi_connection_state['last_error'] = 'timeout'
            log_message(f'WiFi 연결 타임아웃: {ssid}')
            return False
            
    except OSError as e:
        wifi_connection_state['status'] = 'failed'
        wifi_connection_state['last_error'] = f'OSError: {e}'
        log_message(f'WiFi 연결 오류: {ssid} - {e}')
        return False
    except Exception as e:
        wifi_connection_state['status'] = 'failed'
        wifi_connection_state['last_error'] = f'Exception: {e}'
        log_message(f'WiFi 연결 예외: {ssid} - {e}')
        return False



async def connect_wifi():
    """개선된 WiFi 연결 (다중 재시도 및 지수 백오프)"""
    global wifi_connection_attempts, wifi_connection_stats, wifi_current_network_index, force_screen_update
    
    # 이미 연결되어 있으면 신호 강도만 체크
    if wlan and wlan.isconnected():
        measure_wifi_signal_strength()
        if not should_attempt_wifi_reconnect():
            log_message(f"WiFi 이미 연결됨: {wlan.ifconfig()[0]} (RSSI: {wifi_connection_state['rssi']}dBm)")
            return True
        else:
            log_message("WiFi 신호 약함, 재연결 시도...")
    
    wifi_connection_stats['total_attempts'] = wifi_connection_stats.get('total_attempts', 0) + 1
    
    # 다중 재시도 로직
    for attempt in range(WIFI_RETRY_COUNT):
        wifi_connection_attempts = attempt
        wifi_connection_state['retry_count'] = attempt
        
        # 현재 네트워크 정보 가져오기
        if wifi_current_network_index >= len(WIFI_NETWORKS):
            wifi_current_network_index = 0
        
        current_network = WIFI_NETWORKS[wifi_current_network_index]
        ssid, password = current_network[0], current_network[1]
        
        log_message(f"WiFi 연결 시도 {attempt + 1}/{WIFI_RETRY_COUNT}: {ssid}")
        
        # 연결 시도
        connection_start = time.ticks_ms()
        
        # 기본 연결 시도
        success = await connect_wifi_single_attempt(ssid, password, WIFI_CONNECTION_TIMEOUT)
            
        connection_time = time.ticks_diff(time.ticks_ms(), connection_start)
        
        if success:
            # 연결 성공
            wifi_connection_stats['success'] = wifi_connection_stats.get('success', 0) + 1
            wifi_connection_stats['total_time'] = wifi_connection_stats.get('total_time', 0) + connection_time
            wifi_connection_attempts = 0
            force_screen_update = True
            return True
        else:
            # 연결 실패
            wifi_connection_stats['failed'] = wifi_connection_stats.get('failed', 0) + 1
            
            # 마지막 시도가 아니면 지수 백오프 대기
            if attempt < WIFI_RETRY_COUNT - 1:
                delay = wifi_retry_delays[min(attempt, len(wifi_retry_delays) - 1)]
                log_message(f"WiFi 재시도 대기: {delay}초")
                
                if oled:
                    oled.fill(0)
                    oled.text("WiFi Retry in", 0, 0)
                    oled.text(f"{delay} seconds", 0, 10)
                    oled.show()
                
                await asyncio.sleep(delay)
                
                # 다음 네트워크로 전환 (있다면)
                if len(WIFI_NETWORKS) > 1:
                    wifi_current_network_index = (wifi_current_network_index + 1) % len(WIFI_NETWORKS)
                    log_message(f"다음 네트워크로 전환: {WIFI_NETWORKS[wifi_current_network_index][0]}")
    
    # 모든 시도 실패
    wifi_connection_state['status'] = 'failed'
    log_message('WiFi 연결 최종 실패')
    log_message('WiFi 설정을 확인해주세요.')
    
    if oled:
        oled.fill(0)
        oled.text("WiFi Failed!", 0, 0)
        oled.text("Check settings", 0, 10)
        oled.show()
        await asyncio.sleep(2)
    
    # 네트워크 인터페이스 비활성화
    try:
        if wlan:
            wlan.disconnect()
            wlan.active(False)
    except:
        pass
    
    force_screen_update = True
    return False

def get_wifi_connection_stats():
    """WiFi 연결 통계 반환"""
    stats = wifi_connection_stats.copy()
    if stats.get('success', 0) > 0:
        stats['average_connection_time'] = stats.get('total_time', 0) // stats['success']
    else:
        stats['average_connection_time'] = 0
    
    if stats.get('total_attempts', 0) > 0:
        stats['success_rate'] = (stats.get('success', 0) * 100) // stats['total_attempts']
    else:
        stats['success_rate'] = 0
    
    return stats

def get_wifi_status():
    """현재 WiFi 상태 정보 반환"""
    status = wifi_connection_state.copy()
    status['average_rssi'] = get_average_rssi()
    status['is_connected'] = wlan and wlan.isconnected()
    
    if status['is_connected']:
        try:
            status['current_ip'] = wlan.ifconfig()[0]
            measure_wifi_signal_strength()  # 최신 RSSI 업데이트
        except:
            pass
    
    return status

async def monitor_wifi_connection():
    """WiFi 연결 상태 모니터링 (백그라운드 태스크)"""
    global force_screen_update, wlan
    
    while True:
        try:
            if wlan and wlan.isconnected():
                # 신호 강도 측정
                measure_wifi_signal_strength()
                
                # WiFi 상태 상세 체크
                try:
                    status = wlan.status()
                    # 정상 상태: 5 (GOT_IP), 1010 (CONNECTED_STABLE)
                    if status not in [5, 1010]:
                        log_message(f"WiFi 상태 이상: {status}, 재연결 시도...")
                        success = await connect_wifi()
                        if success:
                            log_message("WiFi 상태 복구 성공")
                        safe_force_screen_update()
                        continue
                    elif status == 1010:
                        # 1010은 안정적 연결 상태이므로 로그만 기록 (너무 자주 나오지 않도록)
                        pass  # 로그 생략
                except Exception as e:
                    log_message(f"WiFi 상태 체크 오류: {e}")
                
                # 연결 품질 체크
                if should_attempt_wifi_reconnect():
                    log_message("WiFi 연결 품질 저하 감지, 재연결 시도...")
                    success = await connect_wifi()
                    if success:
                        log_message("WiFi 재연결 성공")
                    else:
                        log_message("WiFi 재연결 실패")
                    safe_force_screen_update()
            else:
                # 연결이 끊어진 경우 자동 재연결 시도
                if wifi_connection_state['status'] != 'connecting':
                    log_message("WiFi 연결 끊김 감지, 자동 재연결 시도...")
                    
                    # WiFi 하드웨어 리셋 시도
                    try:
                        if wlan:
                            wlan.active(False)
                            await asyncio.sleep_ms(1000)
                            wlan.active(True)
                            await asyncio.sleep_ms(1000)
                    except Exception as e:
                        log_message(f"WiFi 하드웨어 리셋 오류: {e}")
                    
                    success = await connect_wifi()
                    if success:
                        log_message("WiFi 자동 재연결 성공")
                        # MQTT 재연결도 시도
                        if not mqtt_connected:
                            connect_mqtt()
                    safe_force_screen_update()
            
            # 모니터링 간격 대기
            await asyncio.sleep(WIFI_MONITOR_INTERVAL)
            
        except Exception as e:
            log_message(f"WiFi 모니터링 오류: {e}")
            # 심각한 오류 시 WiFi 완전 재초기화
            try:
                wlan = None
                await asyncio.sleep(5)
                wlan = network.WLAN(network.STA_IF)
                log_message("WiFi 완전 재초기화 완료")
            except Exception as reset_error:
                log_message(f"WiFi 재초기화 실패: {reset_error}")
            
            await asyncio.sleep(30)  # 오류 시 30초 대기

def force_wifi_reconnect():
    """강제 WiFi 재연결 (완전 리셋)"""
    global wifi_connection_attempts, wlan
    log_message("강제 WiFi 재연결 요청 (완전 리셋)")
    wifi_connection_attempts = 0
    wifi_connection_state['status'] = 'disconnected'
    
    try:
        if wlan:
            wlan.disconnect()
            wlan.active(False)
            wlan = None  # 객체 완전 제거
    except Exception as e:
        log_message(f"WiFi 해제 오류: {e}")
    
    # 새로운 WLAN 객체 생성 및 재연결
    try:
        wlan = network.WLAN(network.STA_IF)
        log_message("새로운 WiFi 객체 생성 완료")
    except Exception as e:
        log_message(f"WiFi 객체 생성 오류: {e}")
    
    # 비동기 태스크로 재연결 시도
    asyncio.create_task(connect_wifi())





def adjust_wifi_tx_power(power_dbm):
    """WiFi TX 파워 동적 조정"""
    global WIFI_TX_POWER
    
    # 유효 범위 체크 (ESP32-S2: 0-20dBm)
    if power_dbm < 0:
        power_dbm = 0
    elif power_dbm > 20:
        power_dbm = 20
    
    WIFI_TX_POWER = power_dbm
    
    try:
        if wlan and wlan.active():
            wlan.config(txpower=power_dbm)
            log_message(f"WiFi TX Power 변경됨: {power_dbm}dBm")
            return True
    except Exception as e:
        log_message(f"TX Power 변경 실패: {e}")
        return False
    
    return False

def get_wifi_detailed_status():
    """WiFi 상세 상태 정보 반환 (디버깅용)"""
    if not wlan:
        return "WiFi object not initialized"
    
    try:
        status_codes = {
            0: "IDLE",
            1: "CONNECTING", 
            2: "WRONG_PASSWORD",
            3: "NO_AP_FOUND",
            4: "CONNECT_FAIL",
            5: "GOT_IP",
            15: "TIMEOUT",
            201: "BEACON_TIMEOUT", 
            202: "NO_AP_FOUND_W",
            203: "AUTH_FAIL",
            204: "ASSOC_FAIL",
            205: "HANDSHAKE_TIMEOUT",
            1001: "CONNECTING_INTERNAL",
            1010: "CONNECTED_STABLE"
        }
        
        status = wlan.status()
        is_active = wlan.active()
        is_connected = wlan.isconnected()
        
        info = f"Active: {is_active}, Connected: {is_connected}, Status: {status_codes.get(status, status)}"
        
        if is_connected:
            try:
                config = wlan.ifconfig()
                rssi = wlan.status('rssi')
                info += f", IP: {config[0]}, RSSI: {rssi}dBm"
            except:
                pass
        
        return info
        
    except Exception as e:
        return f"Error getting WiFi status: {e}"

async def sync_time_ntp():
    """NTP 서버와 시간을 동기화합니다."""
    global force_screen_update
    if not wlan or not wlan.isconnected():
        log_message("NTP 동기화 실패: Wi-Fi 없음")
        return False
    log_message("NTP 시간 동기화 시도...")
    if oled: 
        oled.fill(0)
        oled.text("Syncing Time...", 0, 20)
        oled.show()

    # 여러 NTP 서버 시도
    ntp_servers = ["time.bora.net", "pool.ntp.org", "time.google.com", "1.pool.ntp.org"]
    ntptime.timeout = 10
    synced = False
    
    for server in ntp_servers:
        if synced:
            break
            
        ntptime.host = server
        log_message(f"NTP 서버 시도: {server}")
        
        for i in range(2):  # 각 서버당 2회 시도
            try:
                ntptime.settime()
                log_message(f"NTP 시간 동기화 완료 (서버: {server})")
                
                try:
                    current_utc_secs_after_sync = time.time()
                    log_message(f"DEBUG: time.time() after sync = {current_utc_secs_after_sync}")
                    log_message(f"DEBUG: time.localtime() after sync = {time.localtime(current_utc_secs_after_sync)}")
                except Exception as log_err:
                    log_message(f"DEBUG: Error logging time after sync: {log_err}")
                
                if oled: 
                    oled.text("Time OK!", 0, 30)
                    oled.show()
                    await asyncio.sleep(1)
                synced = True
                break
            except OSError as e:
                log_message(f"NTP 실패 {server} (시도 {i+1}): OSError {e}")
                if i == 0:  # 첫 번째 시도 실패 시만 대기
                    await asyncio.sleep(2)
            except Exception as e:
                log_message(f"NTP 오류 {server} (시도 {i+1}): {e}")
                if i == 0:
                    await asyncio.sleep(2)
    
    if not synced:
        log_message("NTP 최종 실패.")
        if oled: 
            oled.text("Time Sync Fail!", 0, 30)
            oled.show()
            await asyncio.sleep(1.5)
    
    force_screen_update = True
    gc.collect()
    return synced

async def run_pump_for_duration(pump_id, duration_ms):
    """지정된 시간(ms) 동안 펌프를 PWM으로 동작"""
    global pump_tasks, force_screen_update, manual_pump_states
    if pump_id not in [1, 2]: 
        return
    if pump_tasks.get(pump_id) is not None:
        log_message(f"P{pump_id} run request ignored, already running.", False)
        return

    if manual_pump_states.get(pump_id, False):
        log_message(f"P{pump_id}: Scheduled run starting, clearing manual ON state.", False)
        manual_pump_states[pump_id] = False

    task = asyncio.current_task()
    pump_tasks[pump_id] = task
    # 수동 제어 모드에서는 화면 업데이트, 캘리브레이션 모드에서는 보호
    if current_screen == "MANUAL_CONTROL":
        force_screen_update = True
    else:
        safe_force_screen_update()
    log_message(f"P{pump_id} ON for {duration_ms}ms")
    publish_pump_status(pump_id)

    try:
        pump_on(pump_id)
        await asyncio.sleep_ms(duration_ms)
        log_message(f"P{pump_id} OFF after {duration_ms}ms schedule")
    except asyncio.CancelledError:
        log_message(f"P{pump_id} scheduled run cancelled.")
    except Exception as e:
        log_message(f"P{pump_id} error during scheduled run: {e}")
    finally:
        pump_off(pump_id)
        if pump_tasks.get(pump_id) == task:
            pump_tasks[pump_id] = None
        # 수동 제어 모드에서는 화면 업데이트, 캘리브레이션 모드에서는 보호
        if current_screen == "MANUAL_CONTROL":
            force_screen_update = True
        else:
            safe_force_screen_update()
        publish_pump_status(pump_id)
        gc.collect()

def get_local_time():
    """현재 로컬 시간 튜플 반환 (시간 동기화 안됐으면 2000년 반환)"""
    SECONDS_SINCE_2000_TO_2024 = 757382400
    
    try:
        current_utc_secs = time.time()
        log_message(f"DEBUG: get_local_time() read time.time() = {current_utc_secs}", False)
        
        if current_utc_secs < SECONDS_SINCE_2000_TO_2024:
            log_message(f"DEBUG: current_utc_secs ({current_utc_secs}) is < {SECONDS_SINCE_2000_TO_2024}. Returning default time.", False)
            return (2000, 1, 1, 0, 0, 0, 0, 1)
        
        log_message(f"DEBUG: current_utc_secs ({current_utc_secs}) is >= {SECONDS_SINCE_2000_TO_2024}. Calculating local time.", False)
        local_secs = current_utc_secs + TIMEZONE_OFFSET
        return time.localtime(local_secs)
        
    except Exception as e:
        log_message(f"로컬 시간 변환 오류: {e}", False)
        return (2000, 1, 1, 0, 0, 0, 0, 1)

# --- UI 디스플레이 함수들 ---
def display_main_screen():
    global last_displayed_date, last_displayed_time, last_pump1_status, \
           last_pump2_status, last_next_schedule, force_screen_update, last_wifi_status_str, \
           manual_pump_states
    if not oled: return
    now = get_local_time()
    needs_show = False

    if force_screen_update:
        oled.fill(0)
        last_displayed_date = ""
        last_displayed_time = ""
        last_pump1_status = None
        last_pump2_status = None
        last_next_schedule = ""
        last_wifi_status_str = ""

    # Date
    current_date_str = "{:04d}-{:02d}-{:02d}".format(now[0], now[1], now[2])
    if current_date_str != last_displayed_date or force_screen_update:
        oled.fill_rect(0, 0, 80, 8, 0)
        oled.text(current_date_str, 0, 0, 1)
        last_displayed_date = current_date_str
        needs_show = True

    # Wi-Fi/MQTT Status (신호 강도 포함)
    if wlan and wlan.isconnected():
        rssi = wifi_connection_state.get('rssi', 0)
        if rssi != 0:
            wifi_status = f"W:{rssi}"
        else:
            wifi_status = "W:On"
    else:
        wifi_status = "W:Off"
    
    mqtt_status = "M:On" if mqtt_connected else "M:Off"
    current_wifi_status_str = f"{wifi_status} {mqtt_status}"
    if current_wifi_status_str != last_wifi_status_str or force_screen_update:
        status_x = SCREEN_WIDTH - len(current_wifi_status_str) * 8
        oled.fill_rect(status_x - 1, 0, SCREEN_WIDTH - status_x + 1, 8, 0)
        oled.text(current_wifi_status_str, status_x, 0, 1)
        last_wifi_status_str = current_wifi_status_str
        needs_show = True

    # Time
    current_time_str = "{:02d}:{:02d}:{:02d}".format(now[3], now[4], now[5])
    if current_time_str != last_displayed_time or force_screen_update:
        time_x = (SCREEN_WIDTH - len(current_time_str) * 8) // 2
        time_y = 10
        oled.fill_rect(0, time_y, SCREEN_WIDTH, 8, 0)
        oled.text(current_time_str, time_x, time_y, 1)
        last_displayed_time = current_time_str
        needs_show = True

    # Pump Status
    current_pump1_on = (pump_tasks.get(1) is not None) or manual_pump_states.get(1, False)
    if current_pump1_on != last_pump1_status or force_screen_update:
        oled.fill_rect(0, 30, 60, 8, 0)
        oled.text("P1:" + ("On " if current_pump1_on else "Off"), 0, 30, 1)
        last_pump1_status = current_pump1_on
        needs_show = True

    current_pump2_on = (pump_tasks.get(2) is not None) or manual_pump_states.get(2, False)
    if current_pump2_on != last_pump2_status or force_screen_update:
        oled.fill_rect(64, 30, 60, 8, 0)
        oled.text("P2:" + ("On " if current_pump2_on else "Off"), 64, 30, 1)
        last_pump2_status = current_pump2_on
        needs_show = True

    # Next Schedule
    next_sched_str = "Next: --:--"
    if now[0] > 2000:
        try:
            now_minutes_day = now[3] * 60 + now[4]
            next_sched_info = None
            min_diff_future = float('inf')
            first_sched_tomorrow_info = None
            first_sched_tomorrow_minutes = float('inf')

            all_schedules_flat = []
            for p, sl in schedules.items():
                for schedule_item in sl:
                    # 새로운 4개 요소 형식과 기존 3개 요소 형식 모두 지원
                    if len(schedule_item) >= 2:
                        h, m = schedule_item[0], schedule_item[1]
                        sched_minutes = h * 60 + m
                        info = f"P{p} {h:02d}:{m:02d}"
                        all_schedules_flat.append((sched_minutes, info))

            if all_schedules_flat:
                all_schedules_flat.sort(key=lambda x: x[0])
                for sched_minutes, info in all_schedules_flat:
                    if sched_minutes > now_minutes_day:
                        diff = sched_minutes - now_minutes_day
                        if diff < min_diff_future:
                            min_diff_future = diff
                            next_sched_info = info
                    if sched_minutes < first_sched_tomorrow_minutes:
                        first_sched_tomorrow_minutes = sched_minutes
                        first_sched_tomorrow_info = info

                if next_sched_info is None and first_sched_tomorrow_info is not None:
                    next_sched_info = first_sched_tomorrow_info

            if next_sched_info:
                next_sched_str = f"Next: {next_sched_info}"
        except Exception as e:
            log_message(f"다음 스케줄 계산 오류: {e}")

    if next_sched_str != last_next_schedule or force_screen_update:
        oled.fill_rect(0, 42, SCREEN_WIDTH, 8, 0)
        oled.text(next_sched_str[:SCREEN_WIDTH//8], 0, 42, 1)
        last_next_schedule = next_sched_str
        needs_show = True

    # Hint
    if force_screen_update:
        oled.fill_rect(0, 55, SCREEN_WIDTH, 8, 0)
        oled.text("SEL->Menu R->Manual", 0, 55, 1)

    if needs_show or force_screen_update:
        oled.show()
        force_screen_update = False

def display_select_pump_screen():
    global force_screen_update
    if not oled: 
        log_message("DEBUG: OLED not available in display_select_pump_screen", False)
        return
    
    log_message("DEBUG: Displaying SELECT_PUMP screen", False)
    oled.fill(0)
    oled.text("Select Pump", (SCREEN_WIDTH - 11*8)//2, 0)

    if selected_pump == 1:
        oled.fill_rect(5, 18, SCREEN_WIDTH - 10, 12, 1)
        oled.text("* Pump 1", 10, 20, 0)
        oled.text("  Pump 2", 10, 35, 1)
    else:
        oled.text("  Pump 1", 10, 20, 1)
        oled.fill_rect(5, 33, SCREEN_WIDTH - 10, 12, 1)
        oled.text("* Pump 2", 10, 35, 0)

    oled.text("UP/DN, SEL, BCK", 0, 55)
    oled.show()
    force_screen_update = False
    log_message("DEBUG: SELECT_PUMP screen displayed and oled.show() called", False)

def display_view_schedule_screen():
    global force_screen_update, schedule_cursor
    if not oled: return

    oled.fill(0)
    oled.text(f"Pump {selected_pump} Schedule", 0, 0)

    pump_schedules = schedules.get(selected_pump, [])
    num_schedules = len(pump_schedules)

    if num_schedules == 0:
        schedule_cursor = 0
    else:
        schedule_cursor = max(0, min(schedule_cursor, num_schedules - 1))

    if not pump_schedules:
        oled.text("No schedules.", 5, 20)
        oled.text("RIGHT -> Add New", 0, 50)
        oled.text("L<- Back", 0, 58)
    else:
        items_per_page = 4
        current_page = schedule_cursor // items_per_page
        start_index = current_page * items_per_page

        for i in range(items_per_page):
            display_idx = start_index + i
            if display_idx < num_schedules:
                schedule_item = pump_schedules[display_idx]
                # 새로운 4개 요소 형식과 기존 3개 요소 형식 모두 지원
                if len(schedule_item) == 4:
                    h, m, dur_ms, interval_days = schedule_item
                else:  # len == 3 (기존 형식)
                    h, m, dur_ms = schedule_item
                    interval_days = 1  # 기본값: 매일
                
                dur_s = dur_ms // 1000
                if interval_days == 1:
                    schedule_str = "{:02d}:{:02d} ({}s)".format(h, m, dur_s)
                else:
                    schedule_str = "{:02d}:{:02d} ({}s/{}d)".format(h, m, dur_s, interval_days)
                prefix = ">" if display_idx == schedule_cursor else " "
                oled.text(prefix + schedule_str, 5, 15 + i * 10)

        total_pages = (num_schedules + items_per_page - 1) // items_per_page or 1
        oled.text(f"{current_page+1}/{total_pages}", SCREEN_WIDTH - 8*4, 0)

        oled.text("U/D Nav, R->Add", 0, 50)
        oled.text("SEL->Edit, L->Back", 0, 58)

    oled.show()
    force_screen_update = True

def display_add_edit_schedule_screen():
    log_message("DEBUG: display_add_edit_schedule_screen() called", False)
    log_message(f"DEBUG: Current values - hour:{edit_hour}, minute:{edit_minute}, duration:{edit_duration_sec}, interval:{edit_interval_days}, cursor_pos:{edit_cursor_pos}", False)
    if not oled: return

    oled.fill(0)
    screen_title = f"Edit P{selected_pump} Sched" if editing_schedule_original is not None else f"Add P{selected_pump} Sched"
    oled.text(screen_title, 0, 0)

    time_str = "{:02d}:{:02d}".format(edit_hour, edit_minute)
    duration_str = f"Dur:{edit_duration_sec: >3}s"
    interval_str = f"Int:{edit_interval_days: >3}d"
    log_message(f"DEBUG: Display strings - time:{time_str}, duration:{duration_str}, interval:{interval_str}", False)
    oled.text(time_str, 20, 15)
    oled.text(duration_str, 20, 25)
    oled.text(interval_str, 20, 35)

    cursor_char = "^"
    cursor_y_offset = 10
    cursor_x = 0
    cursor_y = 0
    char_width = 8
    
    if edit_cursor_pos == 0:
        cursor_x = 20 + (char_width // 2)
        cursor_y = 15 + cursor_y_offset
    elif edit_cursor_pos == 1:
        cursor_x = 20 + 3 * char_width + (char_width // 2)
        cursor_y = 15 + cursor_y_offset
    elif edit_cursor_pos == 2:
        num_str = f"{edit_duration_sec: >3}"
        num_start_x = 20 + len("Dur:") * char_width
        cursor_x = num_start_x + (len(num_str) * char_width // 2)
        cursor_y = 25 + cursor_y_offset
    elif edit_cursor_pos == 3:
        num_str = f"{edit_interval_days: >3}"
        num_start_x = 20 + len("Int:") * char_width
        cursor_x = num_start_x + (len(num_str) * char_width // 2)
        cursor_y = 35 + cursor_y_offset
        log_message(f"DEBUG: Cursor position 3 - cursor_x:{cursor_x}, cursor_y:{cursor_y}, num_str:{num_str}", False)
    
    oled.text(cursor_char, cursor_x - (len(cursor_char)*char_width//2), cursor_y)

    oled.text("U/D Val(+/-1s), L/R", 0, 50)
    oled.text("SEL Save, BCK Cancel", 0, 58)

    oled.show()
    log_message("DEBUG: oled.show() called - screen should be updated now", False)
    force_screen_update = True

def display_manual_control_screen():
    global force_screen_update, manual_selected_pump, manual_pump_states, pump_tasks
    if not oled: 
        log_message("DEBUG: OLED not available in display_manual_control_screen", False)
        return

    log_message("DEBUG: Displaying MANUAL_CONTROL screen", False)
    oled.fill(0)
    oled.text("Manual Control", (SCREEN_WIDTH - 14*8)//2, 0)

    p1_is_on = (pump_tasks.get(1) is not None) or manual_pump_states.get(1, False)
    p2_is_on = (pump_tasks.get(2) is not None) or manual_pump_states.get(2, False)

    prefix1 = ">" if manual_selected_pump == 1 else " "
    prefix2 = ">" if manual_selected_pump == 2 else " "

    p1_text = f"{prefix1}Pump 1: {'ON' if p1_is_on else 'OFF'}"
    p2_text = f"{prefix2}Pump 2: {'ON' if p2_is_on else 'OFF'}"

    if manual_selected_pump == 1:
        oled.fill_rect(5, 18, SCREEN_WIDTH - 10, 12, 1)
        oled.text(p1_text, 10, 20, 0)
        oled.text(p2_text, 10, 35, 1)
    else:
        oled.text(p1_text, 10, 20, 1)
        oled.fill_rect(5, 33, SCREEN_WIDTH - 10, 12, 1)
        oled.text(p2_text, 10, 35, 0)

    if pump_tasks.get(1) is not None and not manual_pump_states.get(1, False):
        oled.text("(Sched)", SCREEN_WIDTH - 8*7, 20, 1 if manual_selected_pump == 2 else 0)
    if pump_tasks.get(2) is not None and not manual_pump_states.get(2, False):
        oled.text("(Sched)", SCREEN_WIDTH - 8*7, 35, 1 if manual_selected_pump == 1 else 0)

    oled.text("U/D Sel, SEL Tog, L Exit", 0, 55)
    oled.show()
    force_screen_update = False
    log_message("DEBUG: MANUAL_CONTROL screen displayed and oled.show() called", False)

def display_pump_menu_screen():
    """펌프 메뉴 화면 (Schedule/Calibration 선택)"""
    global force_screen_update, pump_menu_cursor, selected_pump
    if not oled: 
        log_message("DEBUG: OLED not available in display_pump_menu_screen", False)
        return

    log_message("DEBUG: Displaying PUMP_MENU screen", False)
    oled.fill(0)
    oled.text(f"Pump {selected_pump} Menu", (SCREEN_WIDTH - 12*8)//2, 0)
    
    # 메뉴 옵션들
    options = ["Schedule", "Calibration"]
    
    for i, option in enumerate(options):
        y_pos = 20 + i * 15
        if i == pump_menu_cursor:
            oled.fill_rect(0, y_pos - 2, SCREEN_WIDTH, 12, 1)
            oled.text(f">{option}", 10, y_pos, 0)
        else:
            oled.text(f" {option}", 10, y_pos, 1)
    
    oled.text("U/D Sel, SEL OK, L Back", 0, 55)
    oled.show()
    force_screen_update = False
    log_message("DEBUG: PUMP_MENU screen displayed and oled.show() called", False)

def display_calibrate_pump_screen():
    """펌프 캘리브레이션 화면"""
    global force_screen_update, calibrating_pump, calibration_stage, calibration_start_time, pump_pwm_duty
    global calibration_elapsed_sec, calibration_remaining_sec
    if not oled: return

    oled.fill(0)
    oled.text(f"Calibrate Pump {calibrating_pump}", 0, 0)
    
    if calibration_stage == 0:  # 준비
        oled.text("Ready to calibrate", 0, 15)
        oled.text("Will run 50ml for 50s", 0, 25)
        oled.text(f"Current PWM: {pump_pwm_duty[calibrating_pump]}", 0, 35)
        oled.text("SEL Start, L Back", 0, 55)
    elif calibration_stage == 1:  # 실행 중
        # 스레드에서 업데이트되는 시간 정보 사용
        oled.text("Calibrating...", 0, 15)
        oled.text(f"Time: {calibration_elapsed_sec}s / 50s", 0, 25)
        oled.text(f"Remaining: {calibration_remaining_sec}s", 0, 35)
        oled.text("SEL Stop Early", 0, 55)
    elif calibration_stage == 2:  # 완료, 입력 대기
        oled.text("Calibration done!", 0, 15)
        oled.text("Ready to input", 0, 25)
        oled.text("actual ml amount", 0, 35)
        oled.text("SEL Continue", 0, 55)
    
    oled.show()
    # 캘리브레이션 모드에서는 force_screen_update를 False로 설정하여 자동 화면 업데이트 방지
    force_screen_update = False

def display_calibrate_input_screen():
    """캘리브레이션 결과 입력 화면"""
    global force_screen_update, calibration_input_ml, calibration_input_cursor
    if not oled: return

    oled.fill(0)
    oled.text("Enter actual ml:", 0, 0)
    
    # 숫자 입력 표시 (3자리)
    ml_str = f"{calibration_input_ml:3d}"
    
    for i, digit in enumerate(ml_str):
        x_pos = 30 + i * 16
        if i == calibration_input_cursor:
            oled.fill_rect(x_pos - 2, 18, 12, 12, 1)
            oled.text(digit, x_pos, 20, 0)
        else:
            oled.text(digit, x_pos, 20, 1)
    
    oled.text("ml", 30 + 3 * 16, 20, 1)
    
    oled.text("U/D Change Digit", 0, 35)
    oled.text("L/R Move Cursor", 0, 45)
    oled.text("SEL Save, BCK Cancel", 0, 55)
    
    oled.show()
    force_screen_update = True

# --- 버튼 처리 함수들 ---
def button_thread_func():
    global button_states, button_events, button_lock, buttons
    log_message("버튼 폴링 스레드 시작됨.", False)
    
    # 추가 안정화 시간
    time.sleep_ms(500)
    
    # 버튼 상태 초기화 - 더 안정적인 방법
    for name in BUTTON_PINS.keys():
        if buttons.get(name) is not None:
            pin = buttons[name]
            
            # 여러 번 읽어서 안정된 초기 상태 결정
            readings = []
            for _ in range(10):
                readings.append(pin.value())
                time.sleep_ms(5)
            
            # 가장 많이 나온 값을 초기 상태로 설정
            stable_state = max(set(readings), key=readings.count)
            initial_pressed = (stable_state == 0)
            
            button_states[name] = {
                'pressed': False, 
                'last_change_time': 0, 
                '_confirmed_state': initial_pressed,
                '_debounce_start_time': 0
            }
            
            log_message(f"DEBUG: Button {name} thread init - readings={readings}, stable_state={stable_state}, pressed={initial_pressed}", False)
    
    # 메인 폴링 루프
    consecutive_errors = 0
    while True:
        try:
            current_time = time.ticks_ms()
            
            for name, pin in buttons.items():
                if pin is None: 
                    continue

                try:
                    is_physically_pressed = (pin.value() == 0)
                    state_info = button_states[name]
                    confirmed_state = state_info['_confirmed_state']

                    # SELECT 버튼 특별 디버깅
                    if name == 'SELECT' and is_physically_pressed != confirmed_state:
                        log_message(f"DEBUG: SELECT button state change detected - Physical: {is_physically_pressed}, Confirmed: {confirmed_state}", False)

                    if is_physically_pressed != confirmed_state:
                        if state_info['_debounce_start_time'] == 0:
                            state_info['_debounce_start_time'] = current_time

                        if time.ticks_diff(current_time, state_info['_debounce_start_time']) > BUTTON_DEBOUNCE_MS:
                            # 디바운스 시간 경과 후 재확인
                            recheck_value = pin.value()
                            recheck_pressed = (recheck_value == 0)
                            
                            if recheck_pressed == is_physically_pressed and recheck_pressed != confirmed_state:
                                state_info['_confirmed_state'] = recheck_pressed
                                state_info['pressed'] = recheck_pressed
                                state_info['last_change_time'] = current_time

                                # 버튼이 눌렸을 때만 이벤트 발생 (릴리즈는 무시)
                                if recheck_pressed:
                                    log_message(f"DEBUG: Button {name} PRESS confirmed (pin={recheck_value})", False)
                                    with button_lock:
                                        button_events[name] = True
                                        if name == 'SELECT':
                                            log_message(f"DEBUG: SELECT button event set to True - current button_events: {button_events}", False)
                                else:
                                    log_message(f"DEBUG: Button {name} RELEASE (pin={recheck_value})", False)

                            state_info['_debounce_start_time'] = 0
                    else:
                        # 상태가 안정적이면 디바운스 타이머 리셋
                        state_info['_debounce_start_time'] = 0
                        
                except Exception as pin_error:
                    log_message(f"Pin {name} read error: {pin_error}", False)
                    continue

            consecutive_errors = 0  # 성공적으로 완료되면 에러 카운터 리셋
            time.sleep_ms(BUTTON_POLL_INTERVAL_MS)

        except Exception as e:
            consecutive_errors += 1
            log_message(f"버튼 스레드 오류 #{consecutive_errors}: {e}", False)
            
            if consecutive_errors > 10:
                log_message("버튼 스레드 오류가 너무 많아 긴 대기합니다.", False)
                time.sleep_ms(5000)
                consecutive_errors = 0
            else:
                time.sleep_ms(500)

def check_button_event(name):
    global button_events, button_lock
    if name not in button_events or buttons.get(name) is None:
        return False

    pressed = False
    with button_lock:
        if button_events[name]:
            pressed = True
            button_events[name] = False
            # SELECT 버튼 특별 디버깅
            if name == 'SELECT':
                log_message(f"DEBUG: SELECT button event consumed - returning True", False)
            else:
                log_message(f"DEBUG: Button event consumed - {name}", False)
    
    return pressed

# --- 비동기 작업 함수들 ---
async def handle_buttons_async():
    global current_screen, selected_pump, schedule_cursor, edit_hour, \
           edit_minute, edit_duration_sec, edit_interval_days, edit_cursor_pos, force_screen_update, \
           schedules, editing_schedule_original, \
           manual_selected_pump, manual_pump_states, pump_tasks, \
           pump_menu_cursor, calibrating_pump, calibration_stage, calibration_start_time, \
           calibration_input_ml, calibration_input_cursor

    last_action_time = time.ticks_ms()
    TIMEOUT_MS = 120000  # 2분
    last_debug_time = 0  # 디버깅용 시간 추적

    while True:
        current_time = time.ticks_ms()
        
        # 5초마다 버튼 상태 디버깅 출력
        if time.ticks_diff(current_time, last_debug_time) > 5000:
            with button_lock:
                button_status = {name: button_events[name] for name in button_events}
            log_message(f"DEBUG: Periodic check - Screen: {current_screen}, Button events: {button_status}", False)
            last_debug_time = current_time
        
        # 캘리브레이션 모드에서는 자동 메인화면 전환 방지
        calibration_screens = ["CALIBRATE_PUMP", "CALIBRATE_INPUT"]
        if current_screen not in calibration_screens and current_screen != "MAIN" and time.ticks_diff(current_time, last_action_time) > TIMEOUT_MS:
            log_message("UI: 시간 초과로 메인 화면으로 복귀", False)
            if current_screen == "MANUAL_CONTROL":
                for pump_id, is_manually_on in manual_pump_states.items():
                    if is_manually_on:
                        pump_off(pump_id)
                        manual_pump_states[pump_id] = False
                        publish_pump_status(pump_id)
            
            current_screen = "MAIN"
            force_screen_update = True
            last_action_time = current_time
            await asyncio.sleep_ms(1)
            continue

        up = check_button_event('UP')
        down = check_button_event('DOWN')
        left = check_button_event('LEFT')
        right = check_button_event('RIGHT')
        select = check_button_event('SELECT')
        back = check_button_event('BACK')

        action_taken = False

        # 디버깅: 버튼 이벤트 발생 시에만 로그 출력
        if up or down or left or right or select or back:
            log_message(f"DEBUG: Button events detected - UP:{up} DOWN:{down} LEFT:{left} RIGHT:{right} SEL:{select} BACK:{back}", False)
            log_message(f"DEBUG: Current screen: {current_screen}", False)

        if current_screen == "MAIN":
            if select:
                log_message("UI: SELECT pressed - Entering SELECT_PUMP screen", False)
                current_screen = "SELECT_PUMP"
                selected_pump = 1
                force_screen_update = True
                action_taken = True
                log_message(f"DEBUG: Screen changed to {current_screen}, force_update={force_screen_update}", False)
                # 즉시 화면 업데이트
                if oled:
                    display_select_pump_screen()
                    log_message("DEBUG: Immediate screen update called", False)
            elif right:
                log_message("UI: RIGHT pressed - Entering MANUAL_CONTROL screen", False)
                current_screen = "MANUAL_CONTROL"
                manual_selected_pump = 1
                force_screen_update = True
                action_taken = True
                log_message(f"DEBUG: Screen changed to {current_screen}", False)
                # 즉시 화면 업데이트
                if oled:
                    display_manual_control_screen()
                    log_message("DEBUG: Immediate screen update called", False)

        elif current_screen == "SELECT_PUMP":
            if up or down:
                selected_pump = 1 if selected_pump == 2 else 2
                log_message(f"UI: Selected Pump {selected_pump}", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_select_pump_screen()
            elif select:
                log_message(f"UI: Entering PUMP_MENU for P{selected_pump}", False)
                current_screen = "PUMP_MENU"
                pump_menu_cursor = 0
                force_screen_update = True
                action_taken = True
                log_message(f"DEBUG: Screen changed to {current_screen}", False)
                # 즉시 화면 업데이트
                if oled:
                    display_pump_menu_screen()
                    log_message("DEBUG: Immediate PUMP_MENU screen update called", False)
            elif back or left:
                log_message("UI: Returning to MAIN screen from SELECT_PUMP", False)
                current_screen = "MAIN"
                force_screen_update = True
                action_taken = True
                log_message(f"DEBUG: Screen changed to {current_screen}", False)
                # 즉시 화면 업데이트
                if oled:
                    display_main_screen()
                    log_message("DEBUG: Immediate MAIN screen update called", False)

        elif current_screen == "VIEW_SCHEDULE":
            pump_schedules = schedules.get(selected_pump, [])
            num_schedules = len(pump_schedules)
            
            if up:
                if num_schedules > 0:
                    schedule_cursor = max(0, schedule_cursor - 1)
                    log_message(f"UI: Schedule cursor moved up to {schedule_cursor}", False)
                    force_screen_update = True
                    action_taken = True
            elif down:
                if num_schedules > 0:
                    schedule_cursor = min(num_schedules - 1, schedule_cursor + 1)
                    log_message(f"UI: Schedule cursor moved down to {schedule_cursor}", False)
                    force_screen_update = True
                    action_taken = True
            elif right:
                log_message("UI: RIGHT pressed - Entering ADD_SCHEDULE screen", False)
                current_screen = "ADD_SCHEDULE"
                # 현재 시각을 초기값으로 설정 (시간 동기화 안된 경우 기본값 사용)
                now = get_local_time()
                if now[0] > 2000:  # 시간이 제대로 동기화된 경우만
                    edit_hour = now[3]  # 현재 시
                    edit_minute = now[4]  # 현재 분
                else:  # 시간 동기화 안된 경우 기본값
                    edit_hour = 12  # 12시
                    edit_minute = 0   # 0분
                edit_duration_sec = 5
                edit_interval_days = 1  # 기본값: 매일
                edit_cursor_pos = 0
                editing_schedule_original = None  # 새 스케줄 추가 모드
                force_screen_update = True
                action_taken = True
            elif select:  # SELECT 버튼으로 편집 모드
                if back:  # SELECT + BACK = 삭제
                    if num_schedules > 0 and 0 <= schedule_cursor < num_schedules:
                        schedule_to_delete = pump_schedules[schedule_cursor]
                        pump_schedules.remove(schedule_to_delete)
                        log_message(f"UI: 스케줄 삭제됨 - P{selected_pump}: {schedule_to_delete}")
                        save_schedules()
                        schedule_cursor = max(0, min(schedule_cursor, len(pump_schedules) - 1))
                        force_screen_update = True
                        action_taken = True
                else:  # SELECT만 누르면 편집 모드
                    if num_schedules > 0 and 0 <= schedule_cursor < num_schedules:
                        schedule_to_edit = pump_schedules[schedule_cursor]
                        # 새로운 4개 요소 형식과 기존 3개 요소 형식 모두 지원
                        if len(schedule_to_edit) == 4:
                            edit_hour, edit_minute, dur_ms, edit_interval_days = schedule_to_edit
                        else:  # len == 3 (기존 형식)
                            edit_hour, edit_minute, dur_ms = schedule_to_edit
                            edit_interval_days = 1  # 기본값: 매일
                        edit_duration_sec = dur_ms // 1000
                        edit_cursor_pos = 0
                        editing_schedule_original = schedule_to_edit
                        log_message(f"UI: Editing schedule - P{selected_pump}: {schedule_to_edit}")
                        current_screen = "ADD_SCHEDULE"
                        force_screen_update = True
                        action_taken = True
            elif back or left:
                log_message("UI: Returning to PUMP_MENU screen from VIEW_SCHEDULE", False)
                current_screen = "PUMP_MENU"
                force_screen_update = True
                action_taken = True

        elif current_screen == "ADD_SCHEDULE":
            if up:
                log_message(f"DEBUG: UP button in ADD_SCHEDULE, edit_cursor_pos={edit_cursor_pos}", False)
                if edit_cursor_pos == 0:  # hour
                    edit_hour = (edit_hour + 1) % 24
                elif edit_cursor_pos == 1:  # minute
                    edit_minute = (edit_minute + 1) % 60
                elif edit_cursor_pos == 2:  # duration
                    edit_duration_sec = min(MAX_PUMP_DURATION_SEC, edit_duration_sec + 1)
                elif edit_cursor_pos == 3:  # interval_days
                    old_value = edit_interval_days
                    edit_interval_days = min(30, edit_interval_days + 1)  # 최대 30일
                    log_message(f"DEBUG: Interval days UP: {old_value} -> {edit_interval_days}", False)
                log_message(f"UI: Edit value increased - {edit_hour:02d}:{edit_minute:02d} {edit_duration_sec}s {edit_interval_days}d", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_add_edit_schedule_screen()
                    log_message("DEBUG: Immediate ADD_SCHEDULE screen update (UP)", False)
            elif down:
                log_message(f"DEBUG: DOWN button in ADD_SCHEDULE, edit_cursor_pos={edit_cursor_pos}", False)
                if edit_cursor_pos == 0:  # hour
                    edit_hour = (edit_hour - 1) % 24
                elif edit_cursor_pos == 1:  # minute
                    edit_minute = (edit_minute - 1) % 60
                elif edit_cursor_pos == 2:  # duration
                    edit_duration_sec = max(MIN_PUMP_DURATION_SEC, edit_duration_sec - 1)
                elif edit_cursor_pos == 3:  # interval_days
                    old_value = edit_interval_days
                    edit_interval_days = max(1, edit_interval_days - 1)  # 최소 1일
                    log_message(f"DEBUG: Interval days DOWN: {old_value} -> {edit_interval_days}", False)
                log_message(f"UI: Edit value decreased - {edit_hour:02d}:{edit_minute:02d} {edit_duration_sec}s {edit_interval_days}d", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_add_edit_schedule_screen()
                    log_message("DEBUG: Immediate ADD_SCHEDULE screen update (DOWN)", False)
            elif left:
                edit_cursor_pos = (edit_cursor_pos - 1) % 4  # 4개 필드로 변경
                log_message(f"UI: Edit cursor moved left to position {edit_cursor_pos}", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_add_edit_schedule_screen()
                    log_message("DEBUG: Immediate ADD_SCHEDULE screen update (LEFT)", False)
            elif right:
                edit_cursor_pos = (edit_cursor_pos + 1) % 4  # 4개 필드로 변경
                log_message(f"UI: Edit cursor moved right to position {edit_cursor_pos}", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_add_edit_schedule_screen()
                    log_message("DEBUG: Immediate ADD_SCHEDULE screen update (RIGHT)", False)
            elif select:  # 저장
                new_schedule = (edit_hour, edit_minute, edit_duration_sec * 1000, edit_interval_days)
                pump_schedules = schedules.setdefault(selected_pump, [])
                
                # 중복 체크 (시간만 체크, 기존 스케줄의 형식에 관계없이)
                is_duplicate = False
                for existing_schedule in pump_schedules:
                    # 기존 스케줄이 3개 요소든 4개 요소든 처음 2개(시간, 분)만 비교
                    if existing_schedule[0] == edit_hour and existing_schedule[1] == edit_minute:
                        is_duplicate = True
                        break
                if not is_duplicate:
                    if editing_schedule_original is not None:
                        # 수정 모드: 기존 스케줄 제거
                        try:
                            pump_schedules.remove(editing_schedule_original)
                            log_message(f"UI: Original schedule removed: {editing_schedule_original}")
                        except ValueError:
                            pass
                    
                    pump_schedules.append(new_schedule)
                    log_message(f"UI: Schedule saved - P{selected_pump}: {new_schedule}")
                    save_schedules()
                    current_screen = "VIEW_SCHEDULE"
                    force_screen_update = True
                    action_taken = True
                else:
                    log_message(f"UI: Duplicate schedule time - P{selected_pump} {edit_hour:02d}:{edit_minute:02d}")
            elif back:  # 취소
                log_message("UI: ADD_SCHEDULE cancelled", False)
                current_screen = "VIEW_SCHEDULE"
                force_screen_update = True
                action_taken = True

        elif current_screen == "MANUAL_CONTROL":
            if up or down:
                manual_selected_pump = 1 if manual_selected_pump == 2 else 2
                log_message(f"UI: Manual control selection changed to P{manual_selected_pump}", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_manual_control_screen()
                    log_message("DEBUG: Immediate MANUAL_CONTROL screen update (UP/DOWN)", False)
            elif select:
                pump_id_to_toggle = manual_selected_pump
                log_message(f"UI: SELECT pressed - Toggling P{pump_id_to_toggle} manually", False)

                task = pump_tasks.get(pump_id_to_toggle)
                if task is not None:
                    try:
                        task.cancel()
                        log_message(f"UI: Cancelled running scheduled task for P{pump_id_to_toggle}")
                    except Exception as e:
                        log_message(f"UI: Error cancelling task for P{pump_id_to_toggle}: {e}")

                if manual_pump_states.get(pump_id_to_toggle, False):
                    pump_off(pump_id_to_toggle)
                    manual_pump_states[pump_id_to_toggle] = False
                    log_message(f"UI: P{pump_id_to_toggle} turned OFF manually.")
                else:
                    pump_on(pump_id_to_toggle)
                    manual_pump_states[pump_id_to_toggle] = True
                    log_message(f"UI: P{pump_id_to_toggle} turned ON manually.")

                publish_pump_status(pump_id_to_toggle)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_manual_control_screen()
                    log_message("DEBUG: Immediate MANUAL_CONTROL screen update (SELECT)", False)

            elif back or left:
                log_message("UI: Exiting MANUAL_CONTROL screen", False)
                pumps_turned_off_on_exit = []
                for pump_id, is_manually_on in manual_pump_states.items():
                    if is_manually_on:
                        pump_off(pump_id)
                        manual_pump_states[pump_id] = False
                        pumps_turned_off_on_exit.append(f"P{pump_id}")
                if pumps_turned_off_on_exit:
                    log_message(f"UI: Turned off manually activated pumps on exit: {', '.join(pumps_turned_off_on_exit)}")
                    for pid_str in pumps_turned_off_on_exit:
                        try:
                            publish_pump_status(int(pid_str[1:]))
                        except:
                            pass

                current_screen = "MAIN"
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_main_screen()
                    log_message("DEBUG: Immediate MAIN screen update (EXIT MANUAL)", False)

        elif current_screen == "PUMP_MENU":
            if up:
                pump_menu_cursor = max(0, pump_menu_cursor - 1)
                log_message(f"UI: Pump menu cursor moved up to {pump_menu_cursor}", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_pump_menu_screen()
                    log_message("DEBUG: Immediate PUMP_MENU screen update (UP)", False)
            elif down:
                pump_menu_cursor = min(1, pump_menu_cursor + 1)  # 0: Schedule, 1: Calibration
                log_message(f"UI: Pump menu cursor moved down to {pump_menu_cursor}", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_pump_menu_screen()
                    log_message("DEBUG: Immediate PUMP_MENU screen update (DOWN)", False)
            elif select:
                if pump_menu_cursor == 0:  # Schedule
                    log_message(f"UI: Entering VIEW_SCHEDULE for P{selected_pump}", False)
                    current_screen = "VIEW_SCHEDULE"
                    schedule_cursor = 0
                    force_screen_update = True
                    action_taken = True
                    # 즉시 화면 업데이트
                    if oled:
                        display_view_schedule_screen()
                        log_message("DEBUG: Immediate VIEW_SCHEDULE screen update", False)
                elif pump_menu_cursor == 1:  # Calibration
                    log_message(f"UI: Entering CALIBRATE_PUMP for P{selected_pump}", False)
                    current_screen = "CALIBRATE_PUMP"
                    calibrating_pump = selected_pump
                    calibration_stage = 0
                    calibration_input_ml = 50  # 기본값
                    calibration_input_cursor = 0
                    force_screen_update = True
                    action_taken = True
                    # 즉시 화면 업데이트
                    if oled:
                        display_calibrate_pump_screen()
                        log_message("DEBUG: Immediate CALIBRATE_PUMP screen update", False)
            elif back or left:
                log_message("UI: Returning to SELECT_PUMP screen from PUMP_MENU", False)
                current_screen = "SELECT_PUMP"
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_select_pump_screen()
                    log_message("DEBUG: Immediate SELECT_PUMP screen update", False)

        elif current_screen == "CALIBRATE_PUMP":
            # SELECT 버튼 디버깅 강화
            if select:
                log_message(f"DEBUG: SELECT button pressed in CALIBRATE_PUMP screen, calibration_stage={calibration_stage}", False)
                if calibration_stage == 0:  # 준비 → 시작 (펌프 즉시 작동!)
                    log_message(f"UI: Starting calibration for P{calibrating_pump} - PUMP STARTS NOW!", False)
                    calibration_stage = 1
                    calibration_start_time = time.ticks_ms()
                    # 50초간 펌프 실행 - 스레드로 실행
                    log_message(f"DEBUG: About to start calibration thread for pump {calibrating_pump}", False)
                    try:
                        _thread.start_new_thread(calibration_pump_thread, (calibrating_pump, 50000))
                        log_message(f"DEBUG: Calibration thread started successfully for pump {calibrating_pump}", False)
                    except Exception as e:
                        log_message(f"ERROR: Failed to start calibration thread: {e}", False)
                        calibration_stage = 0  # 실패 시 다시 준비 상태로
                    force_screen_update = True
                    action_taken = True
                    # 즉시 화면 업데이트
                    if oled:
                        display_calibrate_pump_screen()
                        log_message("DEBUG: Calibration STARTED - pump is now running", False)
                elif calibration_stage == 1:  # 실행 중 → 중단
                    log_message(f"UI: Stopping calibration early for P{calibrating_pump}", False)
                    # 스레드 중단 플래그 설정
                    calibration_thread_stop_flag = True
                    # 중단 후 바로 입력 화면으로 이동
                    current_screen = "CALIBRATE_INPUT"
                    calibration_stage = 2
                    force_screen_update = True
                    action_taken = True
                    # 즉시 화면 업데이트
                    if oled:
                        display_calibrate_input_screen()
                        log_message("DEBUG: Immediate CALIBRATE_INPUT screen update (STOP)", False)
                elif calibration_stage == 2:  # 완료, 입력 대기
                    log_message(f"UI: Moving to input screen for P{calibrating_pump}", False)
                    current_screen = "CALIBRATE_INPUT"
                    force_screen_update = True
                    action_taken = True
                    # 즉시 화면 업데이트
                    if oled:
                        display_calibrate_input_screen()
                        log_message("DEBUG: Immediate CALIBRATE_INPUT screen update (COMPLETED)", False)
            elif back or left:
                log_message(f"DEBUG: BACK/LEFT button pressed in CALIBRATE_PUMP screen, calibration_stage={calibration_stage}", False)
                if calibration_stage == 1:  # 실행 중인 경우 중단
                    calibration_thread_stop_flag = True
                log_message("UI: Returning to PUMP_MENU from CALIBRATE_PUMP", False)
                current_screen = "PUMP_MENU"
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_pump_menu_screen()
                    log_message("DEBUG: Immediate PUMP_MENU screen update (BACK)", False)

        elif current_screen == "CALIBRATE_INPUT":
            if up:
                if calibration_input_cursor == 0:  # 백의 자리
                    calibration_input_ml = min(999, calibration_input_ml + 100)
                elif calibration_input_cursor == 1:  # 십의 자리
                    calibration_input_ml = min(999, calibration_input_ml + 10)
                elif calibration_input_cursor == 2:  # 일의 자리
                    calibration_input_ml = min(999, calibration_input_ml + 1)
                log_message(f"UI: Calibration input increased to {calibration_input_ml}ml", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_calibrate_input_screen()
                    log_message("DEBUG: Immediate CALIBRATE_INPUT screen update (UP)", False)
            elif down:
                if calibration_input_cursor == 0:  # 백의 자리
                    calibration_input_ml = max(0, calibration_input_ml - 100)
                elif calibration_input_cursor == 1:  # 십의 자리
                    calibration_input_ml = max(0, calibration_input_ml - 10)
                elif calibration_input_cursor == 2:  # 일의 자리
                    calibration_input_ml = max(0, calibration_input_ml - 1)
                log_message(f"UI: Calibration input decreased to {calibration_input_ml}ml", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_calibrate_input_screen()
                    log_message("DEBUG: Immediate CALIBRATE_INPUT screen update (DOWN)", False)
            elif left:
                calibration_input_cursor = max(0, calibration_input_cursor - 1)
                log_message(f"UI: Calibration input cursor moved left to {calibration_input_cursor}", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_calibrate_input_screen()
                    log_message("DEBUG: Immediate CALIBRATE_INPUT screen update (LEFT)", False)
            elif right:
                calibration_input_cursor = min(2, calibration_input_cursor + 1)
                log_message(f"UI: Calibration input cursor moved right to {calibration_input_cursor}", False)
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_calibrate_input_screen()
                    log_message("DEBUG: Immediate CALIBRATE_INPUT screen update (RIGHT)", False)
            elif select:  # 캘리브레이션 저장
                if calibration_input_ml > 0:
                    # 예상: 50ml, 실제: calibration_input_ml
                    expected_ml = 50.0
                    actual_ml = float(calibration_input_ml)
                    
                    # PWM 듀티 사이클 조정 (비례 관계)
                    current_duty = pump_pwm_duty[calibrating_pump]
                    new_duty = int(current_duty * (expected_ml / actual_ml))
                    new_duty = max(100, min(1023, new_duty))  # 100-1023 범위로 제한
                    
                    pump_pwm_duty[calibrating_pump] = new_duty
                    save_calibration()
                    
                    log_message(f"UI: Calibration saved - P{calibrating_pump}: {current_duty} -> {new_duty} (Expected: {expected_ml}ml, Actual: {actual_ml}ml)")
                    
                    current_screen = "PUMP_MENU"
                    force_screen_update = True
                    action_taken = True
                    # 즉시 화면 업데이트
                    if oled:
                        display_pump_menu_screen()
                        log_message("DEBUG: Immediate PUMP_MENU screen update (SAVE)", False)
                else:
                    log_message("UI: Invalid calibration input (0ml)", False)
            elif back:
                log_message("UI: Calibration input cancelled", False)
                current_screen = "CALIBRATE_PUMP"
                calibration_stage = 2
                force_screen_update = True
                action_taken = True
                # 즉시 화면 업데이트
                if oled:
                    display_calibrate_pump_screen()
                    log_message("DEBUG: Immediate CALIBRATE_PUMP screen update (CANCEL)", False)

        # 액션이 수행되었을 때만 타임아웃 리셋
        if action_taken:
            last_action_time = current_time
            await asyncio.sleep_ms(1)
        else:
            await asyncio.sleep_ms(20)  # 50ms에서 20ms로 단축

async def update_display_task():
    global current_screen, oled 
    
    while True:
        try:
            if oled:
                # MAIN 화면이나 캘리브레이션 화면이 아닐 때만 디버깅 로그 출력
                if current_screen not in ["MAIN", "CALIBRATE_PUMP", "CALIBRATE_INPUT"]:
                    log_message(f"DEBUG: update_display_task - current_screen: {current_screen}", False)
                    
                if current_screen == "MAIN":
                    display_main_screen()
                elif current_screen == "SELECT_PUMP":
                    log_message("DEBUG: Calling display_select_pump_screen from update_display_task", False)
                    display_select_pump_screen()
                elif current_screen == "VIEW_SCHEDULE":
                    display_view_schedule_screen()
                elif current_screen == "ADD_SCHEDULE":
                    display_add_edit_schedule_screen()
                elif current_screen == "MANUAL_CONTROL":
                    display_manual_control_screen()
                elif current_screen == "PUMP_MENU":
                    display_pump_menu_screen()
                elif current_screen == "CALIBRATE_PUMP":
                    display_calibrate_pump_screen()
                elif current_screen == "CALIBRATE_INPUT":
                    display_calibrate_input_screen()
                else:
                    log_message(f"Warning: Unknown screen state '{current_screen}' in display task", False)
                    oled.fill(0)
                    oled.text("Unknown Screen!", 0, 0)
                    oled.text(f"State: {current_screen}", 0, 10)
                    oled.show()
                    await asyncio.sleep(1)
                    current_screen = "MAIN"
                    force_screen_update = True
            else:
                log_message("DEBUG: OLED not available in update_display_task", False)

            # 캘리브레이션 모드와 수동 제어 모드에서는 더 빠른 업데이트
            if current_screen in ["CALIBRATE_PUMP", "CALIBRATE_INPUT"]:
                delay_ms = 50  # 캘리브레이션 모드에서는 50ms마다 업데이트
            elif current_screen == "MANUAL_CONTROL":
                delay_ms = 100  # 수동 제어 모드에서는 100ms마다 업데이트 (펌프 상태 실시간 반영)
            elif current_screen == "MAIN":
                delay_ms = 200
            else:
                delay_ms = 150
            await asyncio.sleep_ms(delay_ms)

        except Exception as e:
            log_message(f"Display Task Error: {e}")
            await asyncio.sleep_ms(1000)

async def check_schedules_task():
    global schedules, pump_tasks, force_screen_update
    last_check_minute = -1
    
    while True:
        try:
            now = get_local_time()
            current_year = now[0]
            current_minute_of_day = now[3] * 60 + now[4]

            if current_year > 2000 and current_minute_of_day != last_check_minute:
                last_check_minute = current_minute_of_day

                for pump_id, pump_schedule_list in schedules.items():
                    for schedule_item in pump_schedule_list:
                        # 새로운 4개 요소 형식과 기존 3개 요소 형식 모두 지원
                        if len(schedule_item) == 4:
                            h, m, duration_ms, interval_days = schedule_item
                        else:  # len == 3 (기존 형식)
                            h, m, duration_ms = schedule_item
                            interval_days = 1  # 기본값: 매일
                        
                        if h == now[3] and m == now[4]:
                            # 날짜 간격 체크
                            if should_run_schedule(pump_id, h, m, interval_days):
                                if pump_tasks.get(pump_id) is None:
                                    log_message(f"SCHED: P{pump_id} START at {h:02d}:{m:02d} for {duration_ms}ms (every {interval_days} day(s))")
                                    asyncio.create_task(run_pump_for_duration(pump_id, duration_ms))
                                    # 실행 기록
                                    record_schedule_run(pump_id, h, m)
                                else:
                                    log_message(f"SCHED: P{pump_id} SKIPPED at {h:02d}:{m:02d} (already running)")
                            else:
                                log_message(f"SCHED: P{pump_id} SKIPPED at {h:02d}:{m:02d} (interval {interval_days} days not met)")
                            break

                gc.collect()

            await asyncio.sleep(10)

        except Exception as e:
            log_message(f"Schedule Check Task Error: {e}")
            await asyncio.sleep(60)

async def mqtt_handler_task():
    global mqtt_client, mqtt_connected, mqtt_connection_attempt_time, force_screen_update
    
    while True:
        try:
            if wlan and wlan.isconnected():
                if not mqtt_connected:
                    current_time = time.ticks_ms()
                    if time.ticks_diff(current_time, mqtt_connection_attempt_time) > MQTT_RECONNECT_DELAY_S * 1000:
                        log_message("Attempting MQTT reconnection...")
                        mqtt_connection_attempt_time = current_time
                        connect_mqtt()
                        safe_force_screen_update()
                        gc.collect()
                else:
                    try:
                        if mqtt_client:
                            mqtt_client.check_msg()
                            # Heartbeat 발행
                            publish_heartbeat()
                    except OSError as e:
                        log_message(f"MQTT check_msg OSError: {e}. Disconnecting.")
                        mqtt_connected = False
                        safe_force_screen_update()
                        mqtt_connection_attempt_time = time.ticks_ms()
                        gc.collect()
                    except Exception as e:
                        log_message(f"MQTT check_msg Error: {e}")
            else:
                if mqtt_connected:
                    log_message("Wi-Fi disconnected, marking MQTT as disconnected.", False)
                    mqtt_connected = False
                    safe_force_screen_update()
                    try:
                        if mqtt_client:
                            mqtt_client.disconnect()
                    except:
                        pass
                    mqtt_client = None

            await asyncio.sleep_ms(500)

        except Exception as e:
            log_message(f"MQTT Handler Task Error: {e}")
            mqtt_connected = False
            safe_force_screen_update()
            await asyncio.sleep(5)

# --- 전역 상태 점검 및 복구 ---
async def check_global_state():
    """전역 상태 점검 및 복구 (주기적 호출 필요)"""
    global wlan, mqtt_connected, force_screen_update, mqtt_client, last_mqtt_publish_time

    # Wi-Fi 연결 점검 및 재연결 시도 (개선된 버전)
    if should_attempt_wifi_reconnect():
        log_message("Wi-Fi 연결 상태 점검 중...", False)
        connected = await connect_wifi()
        if connected:
            log_message("Wi-Fi 상태 점검 완료 - 연결됨")
            # 연결 성공 시 MQTT도 확인
            if not mqtt_connected:
                log_message("MQTT 재연결 시도...")
                connect_mqtt()
        else:
            log_message("Wi-Fi 상태 점검 완료 - 연결 실패")

    # MQTT 연결 점검 및 재연결 시도
    if mqtt_client is None or not mqtt_connected:
        log_message("MQTT 연결 상태 불량, 재연결 시도...", False)
        try:
            if mqtt_client is not None:
                mqtt_client.disconnect()
        except:
            pass
        mqtt_client = None
        await asyncio.sleep(1)
        connect_mqtt()

    # 주기적으로 상태 발행 (예: 60초마다)
    current_time = time.ticks_ms()
    if mqtt_connected and (time.ticks_diff(current_time, last_mqtt_publish_time) > 60000):
        publish_all_status()
        last_mqtt_publish_time = current_time

    # 메모리 정리
    gc.collect()

# --- 주기적 작업 ---
async def periodic_tasks():
    """주기적으로 실행되는 작업들 (예: 상태 점검, MQTT 핑 등)"""
    while True:
        try:
            await check_global_state()
            # WDT 피드
            try:
                wdt.feed()
            except Exception as e:
                log_message(f"WDT 피드 오류 (periodic_tasks): {e}")
        except Exception as e:
            log_message(f"주기적 작업 중 오류: {e}")
        await asyncio.sleep(10) # 10초 간격

# --- 메인 루프 ---
async def main():
    global force_screen_update

    # 하드웨어 초기화
    init_hardware()
    force_screen_update = True

    # 스케줄 로드
    load_schedules()
    
    # 캘리브레이션 데이터 로드
    load_calibration()

    # 버튼 폴링 스레드 시작
    if '_thread' in globals() and hasattr(_thread, 'allocate_lock'):
        try:
            _thread.start_new_thread(button_thread_func, ())
        except Exception as e:
            log_message(f"버튼 스레드 시작 실패: {e}", False)
            # 폴백 호출 추가
            button_thread_func()
    else:
        log_message("스레딩 미지원 또는 실패, 버튼 입력 비활성화.", False)

    # Wi-Fi 연결
    wifi_ok = await connect_wifi()

    # NTP를 통한 시간 동기화 (Wi-Fi 연결 시에만)
    if wifi_ok:
        await sync_time_ntp()
    else:
        log_message("NTP 동기화 건너뜀, Wi-Fi 미연결.")

    # 비동기 작업 생성 및 실행
    log_message("비동기 작업 시작...")
    asyncio.create_task(update_display_task())
    asyncio.create_task(handle_buttons_async())
    asyncio.create_task(check_schedules_task())
    asyncio.create_task(mqtt_handler_task())
    asyncio.create_task(periodic_tasks()) # 주기적 작업 추가
    asyncio.create_task(monitor_wifi_connection()) # WiFi 모니터링 태스크 추가

    log_message("메인 루프 실행 중...")
    # 메인 스레드를 살아있게 유지 (이벤트 루프가 작업들을 실행함)
    while True:
        # WDT 피드 (20초마다 리셋되므로 10초마다 피드)
        try:
            wdt.feed()
        except Exception as e:
            log_message(f"WDT 피드 오류: {e}")
            
        await asyncio.sleep(10)  # 10초마다 WDT 피드
        gc.collect()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log_message("KeyboardInterrupt, stopping...")
    except Exception as e:
        log_message(f"FATAL ERROR in main: {e}")
    finally:
        # 자원 정리
        if wlan and wlan.isconnected():
            wlan.disconnect()
            wlan.active(False)
            log_message("Wi-Fi disconnected.")
        if mqtt_client and mqtt_connected:
            try: 
                mqtt_client.disconnect()
                log_message("MQTT disconnected.")
            except: 
                pass
        log_message("Program stopped.")








