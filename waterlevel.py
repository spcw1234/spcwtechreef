# 필요한 라이브러리 import
import machine
import time
import network
import ujson
from umqtt.simple import MQTTClient  # 사용하신 라이브러리 유지
from ssd1306 import SSD1306_I2C
from machine import WDT  # WDT 추가

# --- 간단한 칼만 필터 클래스 (마이크로파이썬용) ---
class SimpleKalmanFilter:
    def __init__(self, q=0.001, r=0.5):
        """
        간단한 칼만 필터
        q: 프로세스 노이즈 (작을수록 안정, 0.001~0.1)
        r: 측정 노이즈 (작을수록 측정값 신뢰, 0.01~1.0)
        """
        self.q = q  # 프로세스 노이즈
        self.r = r  # 측정 노이즈  
        self.x = 0.0  # 추정값
        self.p = 1.0  # 오차 공분산
        self.first = True
        
    def update(self, measurement):
        """새 측정값으로 필터 업데이트"""
        if self.first:
            self.x = measurement
            self.first = False
            return self.x
            
        # 예측
        self.p = self.p + self.q
        
        # 업데이트  
        k = self.p / (self.p + self.r)  # 칼만 게인
        self.x = self.x + k * (measurement - self.x)
        self.p = (1 - k) * self.p
        
        return self.x

# --- WiFi 설정 ---
WIFI_SSID = "SK_4974_2.4G"
WIFI_PASSWORD = "BQP06@0276"

# --- MQTT 설정 ---
MQTT_BROKER = "spcwtech.mooo.com"  # 또는 호스트 이름
MQTT_PORT = 1883  # 기본 MQTT 포트
MQTT_CLIENT_ID = machine.unique_id().hex()  # ESP32-C3 고유 ID를 클라이언트 ID로 사용
MQTT_PUB_TOPIC = f"{MQTT_CLIENT_ID}/Wlv"
MQTT_SUB_TOPIC = f"{MQTT_CLIENT_ID}/cmd"  # 예시 구독 토픽

# --- AJ-SR04M 초음파 센서 핀 설정 ---
TRIGGER_PIN = machine.Pin(2, machine.Pin.OUT)  # 예시 핀 번호 (사용 가능한 GPIO 핀으로 변경)
ECHO_PIN = machine.Pin(3, machine.Pin.IN, machine.Pin.PULL_DOWN)  # 예시 핀 번호 (사용 가능한 GPIO 핀으로 변경)

# --- SSD1306 OLED 디스플레이 설정 ---
I2C_SCL_PIN = machine.Pin(7)  # 예시 SCL 핀 번호 (ESP32-C3 I2C 핀에 맞게 변경)
I2C_SDA_PIN = machine.Pin(6)  # 예시 SDA 핀 번호 (ESP32-C3 I2C 핀에 맞게 변경)
OLED_WIDTH = 128
OLED_HEIGHT = 64
i2c = machine.I2C(0, sda=I2C_SDA_PIN, scl=I2C_SCL_PIN, freq=400000)
oled = SSD1306_I2C(OLED_WIDTH, OLED_HEIGHT, i2c)

# --- 연결 및 WDT 설정 상수 ---
MAX_CONN_RETRIES = 5   # 최대 연결 재시도 횟수
RETRY_DELAY_S = 5      # 재시도 간격 (초)
WDT_TIMEOUT_MS = 15000 # WDT 타임아웃 (15초, 밀리초 단위)

# --- 전역 변수 ---
mqtt_client = None
wlan = None # wlan 객체를 전역으로 선언
wdt = None  # WDT 객체를 전역으로 선언

# --- WiFi 연결 함수 (재시도 및 리셋 로직 추가) ---
def connect_wifi():
    global wlan
    wlan = network.WLAN(network.STA_IF)
    wlan.active(True)
    wlan.config(txpower=8) # 필요 시 txpower 설정

    fail_count = 0
    while not wlan.isconnected() and fail_count < MAX_CONN_RETRIES:
        print(f"WiFi 연결 시도 ({fail_count + 1}/{MAX_CONN_RETRIES})...")
        oled.fill(0)
        oled.text("WiFi Connecting...", 0, 0)
        oled.text(f"Attempt: {fail_count + 1}", 0, 10)
        oled.show()

        wlan.connect(WIFI_SSID, WIFI_PASSWORD)

        # 연결 대기 (타임아웃 추가 - 예: 15초)
        connect_start_time = time.ticks_ms()
        while not wlan.isconnected():
            if time.ticks_diff(time.ticks_ms(), connect_start_time) > 15000: # 15초 타임아웃
                print("\nWiFi 연결 시도 타임아웃.")
                break # 내부 루프 탈출, 재시도 로직으로 넘어감
            time.sleep_ms(500)
            print(".", end="")

        if not wlan.isconnected():
            fail_count += 1
            wlan.disconnect() # 실패 시 확실히 연결 해제 시도
            time.sleep(RETRY_DELAY_S) # 다음 시도 전 대기
        else:
            print("\nWiFi 연결 성공!")
            ip = wlan.ifconfig()[0]
            print(f"IP 주소: {ip}")
            oled.fill(0)
            oled.text("WiFi Connected!", 0, 0)
            oled.text(f"IP: {ip}", 0, 10)
            oled.show()
            time.sleep(1) # 메시지 표시 시간
            return True # 성공 시 True 반환

    # 모든 재시도 실패 시
    if not wlan.isconnected():
        print(f"\nWiFi 연결 {MAX_CONN_RETRIES}회 연속 실패. 시스템을 재부팅합니다.")
        oled.fill(0)
        oled.text("WiFi Conn Fail!", 0, 0)
        oled.text("Rebooting...", 0, 10)
        oled.show()
        time.sleep(5)
        machine.reset()
        # return False # 리셋되므로 이 라인은 실행되지 않음

    # 이미 연결된 경우 (함수 초입에서 확인 가능하지만, 로직 흐름상 여기에 둠)
    elif wlan.isconnected():
         print("이미 WiFi에 연결됨")
         ip = wlan.ifconfig()[0]
         oled.fill(0)
         oled.text("WiFi Connected!", 0, 0)
         oled.text(f"IP: {ip}", 0, 10)
         oled.show()
         time.sleep(1)
         return True

    return False # 예외적인 경우 (실행되지 않아야 함)


# --- MQTT 연결 함수 (재시도 및 리셋 로직 추가) ---
def connect_mqtt():
    global mqtt_client
    fail_count = 0
    while fail_count < MAX_CONN_RETRIES:
        try:
            print(f"MQTT 브로커 연결 시도 ({fail_count + 1}/{MAX_CONN_RETRIES})...")
            oled.text("MQTT Connecting...", 0, 20)
            oled.show()

            # 이전 클라이언트 객체가 있으면 연결 해제 시도 (리소스 정리)
            if mqtt_client:
                try:
                    mqtt_client.disconnect()
                except Exception:
                    pass # 이미 끊어져 있거나 오류 발생해도 무시

            mqtt_client = MQTTClient(MQTT_CLIENT_ID, MQTT_BROKER, MQTT_PORT)
            mqtt_client.set_callback(mqtt_callback)
            mqtt_client.connect() # connect()는 블로킹될 수 있음
            mqtt_client.subscribe(MQTT_SUB_TOPIC)

            print(f"MQTT 브로커 ({MQTT_BROKER}) 연결 성공 및 토픽 ({MQTT_SUB_TOPIC}) 구독 완료!")
            oled.text("MQTT Connected! ", 0, 20) # 이전 텍스트 덮어쓰기 위해 공백 추가
            oled.show()
            return True # 성공 시 True 반환

        except Exception as e:
            print(f"MQTT 연결 실패: {e}")
            fail_count += 1
            oled.text(f"MQTT Fail {fail_count}", 0, 20)
            oled.show()
            time.sleep(RETRY_DELAY_S) # 다음 시도 전 대기

    # 모든 재시도 실패 시
    print(f"\nMQTT 연결 {MAX_CONN_RETRIES}회 연속 실패. 시스템을 재부팅합니다.")
    oled.fill(0)
    oled.text("MQTT Conn Fail!", 0, 0)
    oled.text("Rebooting...", 0, 10)
    oled.show()
    time.sleep(5)
    machine.reset()
    # return False # 리셋되므로 이 라인은 실행되지 않음

# --- MQTT 콜백 함수 (메시지 수신 시 호출) ---
def mqtt_callback(topic, msg):
    try:
        print(f"토픽 '{topic.decode()}' 에서 메시지 수신: {msg.decode()}")
        oled.fill(0)
        oled.text("MQTT Received:", 0, 0)
        # 화면 크기 고려하여 표시 (topic이 길면 잘릴 수 있음)
        oled.text(topic.decode()[:16], 0, 10) # 최대 16자
        oled.text(msg.decode()[:16], 0, 20)  # 최대 16자
        oled.show()
        # 수신한 메시지에 대한 처리 로직 추가 (예: 특정 명령에 따라 LED 제어 등)
    except Exception as e:
        print(f"MQTT 콜백 처리 오류: {e}")

# --- 초음파 센서 거리 측정 함수 (기존과 동일) ---
def measure_distance():
    TRIGGER_PIN.value(0)
    time.sleep_us(2)
    TRIGGER_PIN.value(1)
    time.sleep_us(10)
    TRIGGER_PIN.value(0)

    # Echo 핀이 Low 상태가 될 때까지 대기 (센서 준비) - AJ-SR04M은 필요 없을 수 있음
    # while ECHO_PIN.value() == 1:
    #    pass

    # Echo 핀이 High가 될 때까지 기다리며 시작 시간 기록
    pulse_start = time.ticks_us()
    timeout_start = time.ticks_us()
    while ECHO_PIN.value() == 0:
        pulse_start = time.ticks_us()
        # 타임아웃 체크 (예: 30ms, 약 5m 이상 거리)
        if time.ticks_diff(pulse_start, timeout_start) > 30000:
            return -1 # 타임아웃 발생

    # Echo 핀이 Low가 될 때까지 기다리며 종료 시간 기록
    pulse_end = time.ticks_us()
    timeout_start_end = time.ticks_us() # 종료 타임아웃 시작 시간 분리
    while ECHO_PIN.value() == 1:
        pulse_end = time.ticks_us()
        # 펄스 지속 시간 타임아웃 체크 (비정상적으로 긴 펄스 방지)
        if time.ticks_diff(pulse_end, pulse_start) > 30000:
            return -1 # 타임아웃 발생

    pulse_duration = time.ticks_diff(pulse_end, pulse_start)

    # 거리 계산 (음속 343m/s 기준)
    # 거리(cm) = 시간(us) * 음속(cm/us) / 2
    # 음속 = 34300 cm/s = 0.0343 cm/us
    distance_cm = (pulse_duration * 0.0343) / 2

    # 비정상적인 값 필터링 (예: 2cm 미만, 400cm 초과)
    if distance_cm < 2 or distance_cm > 400:
         return -2 # 범위 벗어남

    return distance_cm

# --- 메인 루프 ---
def main():
    global wdt # 전역 wdt 객체 사용 명시

    # 초기 WiFi 연결 시도 (실패 시 함수 내에서 리셋)
    if not connect_wifi():
        # 이 부분은 connect_wifi 내부 리셋으로 인해 실제 도달하지 않음
        print("초기 WiFi 연결 실패. 프로그램 종료.")
        return

    # 초기 MQTT 연결 시도 (실패 시 함수 내에서 리셋)
    if not connect_mqtt():
        # 이 부분은 connect_mqtt 내부 리셋으로 인해 실제 도달하지 않음
        print("초기 MQTT 연결 실패. 프로그램 종료.")
        return

    # --- WDT 활성화 (WiFi 및 MQTT 초기 연결 성공 후) ---
    try:
        wdt = WDT(timeout=WDT_TIMEOUT_MS)
        print(f"Watchdog Timer 활성화: {WDT_TIMEOUT_MS / 1000} 초")
        wdt.feed() # 초기 피드
    except Exception as e:
        print(f"WDT 초기화 실패: {e}")
        wdt = None # WDT 비활성화

    last_oled_update = 0
    oled_update_interval = 1000 # OLED 업데이트 주기 (1초)

    # 칼만 필터 초기화
    kalman = SimpleKalmanFilter(q=0.001, r=0.5)

    while True:
        # --- WDT 피드 ---
        if wdt:
            wdt.feed()

        # --- WiFi 연결 확인 및 재연결 ---
        if wlan is None or not wlan.isconnected():
            print("WiFi 연결 끊김 감지. 재연결 시도...")
            oled.fill(0)
            oled.text("WiFi Lost!", 0, 0)
            oled.text("Reconnecting...", 0, 10)
            oled.show()
            connect_wifi() # 실패 시 내부에서 리셋됨
            # WiFi 재연결 후 MQTT도 재연결 시도
            if wlan and wlan.isconnected():
                print("WiFi 재연결 성공, MQTT 재연결 시도...")
                connect_mqtt() # 실패 시 내부에서 리셋됨
            continue # 연결 과정 후 루프 처음으로

        current_time_ms = time.ticks_ms()

        # --- 거리 측정 ---
        distance = measure_distance()

        # --- 칼만 필터 적용 ---
        if distance > 0: # 유효한 거리 값일 때만 필터 적용
            filtered_distance = kalman.update(distance)
            print(f"원본 거리: {distance:.2f} cm, 필터링된 거리: {filtered_distance:.2f} cm")
        else:
            filtered_distance = -1 # 측정 실패 시 필터 값 유지
            print("거리 측정 실패 또는 범위 초과, 필터 값 유지")

        # --- OLED 업데이트 (주기적으로) ---
        if time.ticks_diff(current_time_ms, last_oled_update) >= oled_update_interval:
            oled.fill(0) # 주기적으로 전체 클리어
             # WiFi 상태 표시
            oled.text("W:OK", 0, 0)
             # MQTT 상태 표시 (client 객체 존재 여부로 간략히 확인)
            oled.text(f"M:{'OK' if mqtt_client else 'ERR'}", 50, 0)

            if filtered_distance == -1:
                print("거리 측정 실패 (타임아웃 또는 범위 초과)")
                oled.text("Dist: Timeout", 0, 20)
            elif filtered_distance == -2:
                print("거리 측정 실패 (범위 초과)")
                oled.text("Dist: OutRange", 0, 20)
            else:
                print(f"측정 거리: {filtered_distance:.2f} cm")
                oled.text(f"Dist:{filtered_distance:.1f}cm", 0, 20) # 소수점 1자리

            # 마지막 업데이트 시간 기록
            last_oled_update = current_time_ms
            oled.show() # OLED 표시 내용 업데이트

        # --- MQTT 발행 (거리 측정 성공 시) ---
        if filtered_distance > 0: # 필터링된 유효한 거리 값일 때만 발행
            wlv_data = {"distance_cm": round(filtered_distance, 2)}
            json_data = ujson.dumps(wlv_data)

            try:
                if mqtt_client: # MQTT 클라이언트가 유효할 때만 시도
                    mqtt_client.publish(MQTT_PUB_TOPIC, json_data)
                    # print(f"토픽 '{MQTT_PUB_TOPIC}' 에 발행: {json_data}") # 너무 자주 출력될 수 있으므로 주석 처리
                else:
                    print("MQTT 클라이언트 없음, 발행 건너<0xEB><0x8A>.")
                    connect_mqtt() # 클라이언트 없으면 연결 시도

            except Exception as e:
                print(f"MQTT 발행 오류: {e}")
                oled.text("MQTT Pub Err", 0, 30)
                oled.show()
                # 발행 오류 시 재연결 시도
                connect_mqtt() # 실패 시 내부에서 리셋됨

        # --- MQTT 메시지 확인 ---
        try:
            if mqtt_client: # MQTT 클라이언트가 유효할 때만 시도
                mqtt_client.check_msg()  # 수신된 MQTT 메시지 처리 (논블로킹)
            else:
                # print("MQTT 클라이언트 없음, 메시지 확인 건너<0xEB><0x8A>.") # 로그 너무 많을 수 있음
                pass # 클라이언트 없으면 위에서 연결 시도했을 것임

        except Exception as e:
            print(f"MQTT 메시지 확인 오류: {e}")
            oled.text("MQTT Chk Err", 0, 40)
            oled.show()
            # 확인 오류 시 재연결 시도
            connect_mqtt() # 실패 시 내부에서 리셋됨

        # 메인 루프 지연 (CPU 부하 감소)
        time.sleep_ms(100) # 0.1초 간격으로 루프 실행

if __name__ == "__main__":
    main()