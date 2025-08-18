#include <WiFi.h>
#include <PubSubClient.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_GFX.h>
#include <EEPROM.h>
#include <ArduinoJson.h>
#include <string.h>
#include <cmath>
#include <WiFiUdp.h>
#include <esp_wifi.h> 
// --- 설정 ---
// EEPROM 주소 정의
#define EEPROM_SIZE 128
#define SET_TEMP_ADDR 0
#define HYSTERESIS_ADDR 4
#define PWM_MIN_ADDR 8

// 온도 시리얼 출력 설정
const long SERIAL_TEMP_INTERVAL = 1000;
unsigned long last_serial_temp_time = 0;

// Wi-Fi 설정
//const char* WIFI_SSID = "SK_4974_2.4G";
const char* WIFI_SSID = "SK_4974_2.4G"; // 사용하시는 WiFi SSID로 변경하세요
const char* WIFI_PASSWORD = "BQP06@0276";       // 사용하시는 WiFi 비밀번호로 변경하세요

// MQTT 설정
const char* mqtt_server = "spcwtech.mooo.com";
const int mqtt_port = 1883;
String mqtt_client_id; // MAC 주소 기반 고유 ID (String 사용)
String topic_pub;      // 발행 토픽 (String 사용)
String topic_sub;      // 구독 토픽 (String 사용)

WiFiClient espClient;
PubSubClient client(espClient);

// UDP 브로드캐스팅 설정
WiFiUDP udp;
IPAddress broadcastIP(255, 255, 255, 255);
const int UDP_PORT = 4210; // UDP 포트 설정

// 하트비트 설정
unsigned long last_heartbeat_time = 0;
const long HEARTBEAT_INTERVAL = 10000;

// 온도 및 제어 설정
float current_set_temp = 26.0;
unsigned long last_publish_time = 0;
const long PUBLISH_INTERVAL = 5000;
const float KP = 30000.0;
const int PWM_MIN_RAW = 40000;
const int PWM_MAX_RAW = 65535;
int PWM_MIN = 180; // 이 값은 EEPROM에서 읽어옵니다.
const int PWM_MAX = 255;
const long CONTROL_INTERVAL = 1000;
float HYSTERESIS = 0.1; // 이 값은 EEPROM에서 읽어옵니다.
unsigned long last_control_time = 0;
bool cooler_state = false;
int current_pwm_value = 0;

// --- LEDC PWM 설정 (고주파 소음 및 주파수 제어를 위함) ---
const int PWM_FREQUENCY = 25000;     // 목표 PWM 주파수 (25kHz)
const int LEDC_CHANNEL_COOLER = 0;   // LEDC 채널 (ESP32-C3는 0-5 사용 가능)
const int LEDC_RESOLUTION = 8;       // PWM 해상도 (8비트: 0-255 범위)

// --- 하드웨어 핀 정의 (ESP32-C3) ---
const int I2C_SCL_PIN = 9;    // ESP32-C3 GPIO9
const int I2C_SDA_PIN = 8;    // ESP32-C3 GPIO8
#define OLED_WIDTH 128
#define OLED_HEIGHT 64
Adafruit_SSD1306 display(OLED_WIDTH, OLED_HEIGHT, &Wire, -1); // RST 핀 미사용 시 -1
const int COOLER_PWM_PIN = 0; // ESP32-C3 GPIO0 (LEDC 제어)
const int ONEWIRE_PIN = 2;    // ESP32-C3 GPIO2

// Serial1 TX pin for temperature data (ESP32-C3)
const int SERIAL1_TX_PIN = 21; // ESP32-C3 GPIO21
const int SERIAL1_RX_PIN = -1; // RX 핀 미사용

OneWire oneWire(ONEWIRE_PIN);
DallasTemperature sensors(&oneWire);
DeviceAddress insideThermometer;

// --- 함수 정의 ---
void send_temperature_via_serial1(float temperature) {
  unsigned long current_time = millis();
  if (current_time - last_serial_temp_time >= SERIAL_TEMP_INTERVAL) {
    Serial1.print(temperature);
    Serial1.print("\n");
    last_serial_temp_time = current_time;
  }
}

// 기존 코드의 broadcast_via_udp 함수를 아래와 같이 변경합니다:
void broadcast_via_udp(const char* topic, const char* message) {
  // ESP8266에서 작동하는 방식 그대로 구현
  IPAddress broadcastAddress(255, 255, 255, 255);
  
  Serial.println("UDP 브로드캐스트 시작...");
  if (udp.beginPacket(broadcastAddress, UDP_PORT)) {
    // 토픽만 보내거나 (하트비트) 또는 토픽:메시지 형태로 보내기
    String udpMessage;
    if (strcmp(message, "a") == 0) {
      // 하트비트인 경우 - ESP8266 코드와 동일하게 토픽만 전송
      udpMessage = String(topic);
    } else {
      // 일반 데이터인 경우 - 토픽:메시지 형태로 전송
      udpMessage = String(topic) + ":" + String(message);
    }
    
    // 메시지 쓰기
    udp.write((const uint8_t*)udpMessage.c_str(), udpMessage.length());
    
    // 패킷 전송 마무리
    if (udp.endPacket()) {
      Serial.printf("UDP 패킷 전송 성공: %s\n", udpMessage.c_str());
    } else {
      Serial.println("UDP 패킷 전송 실패!");
    }
  } else {
    Serial.println("UDP 패킷 시작 실패!");
  }
}

void send_heartbeat() {
  unsigned long current_time = millis();
  if (current_time - last_heartbeat_time >= HEARTBEAT_INTERVAL) {
    if (client.connected()) {
      client.publish(topic_pub.c_str(), "a", false);
      Serial.printf("Heartbeat sent (MQTT): %s -> a\n", topic_pub.c_str());
    } else {
      Serial.println("Heartbeat: MQTT not connected, skipping MQTT send.");
    }
    broadcast_via_udp(topic_pub.c_str(), "a");
    last_heartbeat_time = current_time;
  }
}

void display_message(String line1 = "", String line2 = "", String line3 = "", String line4 = "") {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  if (line1 != "") display.println(line1);
  if (line2 != "") display.println(line2);
  if (line3 != "") display.println(line3);
  if (line4 != "") display.println(line4);
  display.display();
}

void save_all_settings() {
  EEPROM.put(SET_TEMP_ADDR, current_set_temp);
  EEPROM.put(HYSTERESIS_ADDR, HYSTERESIS);
  EEPROM.put(PWM_MIN_ADDR, PWM_MIN);
  if (EEPROM.commit()) {
    Serial.println("모든 설정이 EEPROM에 저장됨");
    display_message("Settings Saved:",
                    "Temp: " + String(current_set_temp, 1) + " C",
                    "Hys : " + String(HYSTERESIS, 2),
                    "PWMm: " + String(PWM_MIN));
  } else {
    Serial.println("EEPROM commit failed");
    display_message("EEPROM Save", "Failed!");
  }
  delay(1000);
}

float read_set_temp() {
  float temp;
  EEPROM.get(SET_TEMP_ADDR, temp);
  Serial.printf("EEPROM에서 설정 온도 읽기: %.1f C\n", temp);
  if (isnan(temp) || temp < 0.0 || temp > 50.0) {
    Serial.println("EEPROM 설정 온도 값이 유효하지 않거나 범위를 벗어나므로 기본값(25.0C)을 사용하고 저장합니다.");
    temp = 25.0;
    EEPROM.put(SET_TEMP_ADDR, temp);
    EEPROM.commit();
  }
  return temp;
}

void control_temperature(float current_temp) {
  unsigned long current_time = millis();
  if (current_time - last_control_time >= CONTROL_INTERVAL) {
    float error = current_temp - current_set_temp;

    if (!cooler_state && error > HYSTERESIS) {
      cooler_state = true;
      Serial.println("쿨러 켜짐");
    } else if (cooler_state && error < -HYSTERESIS) {
      cooler_state = false;
      Serial.println("쿨러 꺼짐");
    }

    int pwm_value_output = 0; // LEDC에 쓸 최종 값 (0-255 for 8-bit)
    if (cooler_state) {
      float pwm_value_calc_float = max(0.0f, error) * KP;
      int pwm_value_raw = min((int)PWM_MAX_RAW, max((int)PWM_MIN_RAW, (int)pwm_value_calc_float));
      pwm_value_output = map(pwm_value_raw, PWM_MIN_RAW, PWM_MAX_RAW, PWM_MIN, PWM_MAX);
      pwm_value_output = constrain(pwm_value_output, 0, 255); // 8비트 LEDC 해상도에 맞게 0-255 범위 유지

      ledcWrite(LEDC_CHANNEL_COOLER, pwm_value_output); // LEDC로 PWM 출력
      current_pwm_value = pwm_value_output; // 현재 PWM 값을 저장 (표시용)
    } else {
      ledcWrite(LEDC_CHANNEL_COOLER, 0); // LEDC로 PWM 출력 중지
      current_pwm_value = 0;
    }
    last_control_time = current_time;
  }
}

void process_sensors_and_update() {
  sensors.requestTemperatures();
  float temperature = sensors.getTempCByIndex(0);

  if (temperature != DEVICE_DISCONNECTED_C && temperature != 85.0 && temperature != -127.0) {
    send_temperature_via_serial1(temperature);
    control_temperature(temperature);

    unsigned long current_time = millis();
    if (current_time - last_publish_time >= PUBLISH_INTERVAL) {
      StaticJsonDocument<192> jsonDoc;
      jsonDoc["temp"] = round(temperature * 100) / 100.0;
      jsonDoc["set_temp"] = round(current_set_temp * 10) / 10.0;
      jsonDoc["pwm_value"] = current_pwm_value;
      jsonDoc["cooler_state"] = cooler_state;
      jsonDoc["hysteresis"] = HYSTERESIS;
      jsonDoc["pwm_min"] = PWM_MIN;

      char jsonBuffer[192];
      serializeJson(jsonDoc, jsonBuffer);

      if (client.connected()){
        client.publish(topic_pub.c_str(), jsonBuffer, true);
        Serial.printf("Published (MQTT): %s\n", jsonBuffer);
      } else {
        Serial.println("Publish: MQTT not connected, skipping MQTT publish.");
      }
      broadcast_via_udp(topic_pub.c_str(), jsonBuffer);
      last_publish_time = current_time;
    }

    display.clearDisplay();
    display.setCursor(0, 0);
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);

    char buffer[30]; // 버퍼 크기 약간 늘림
    sprintf(buffer, "Temp: %.2f C", temperature);
    display.println(buffer);
    sprintf(buffer, "Set : %.1f C", current_set_temp);
    display.println(buffer);
    float fan_percent = (current_pwm_value > 0) ? ((float)current_pwm_value / 255.0 * 100.0) : 0.0; // 255 기준 백분율
    sprintf(buffer, "Fan : %.1f %%", fan_percent);
    display.println(buffer);
    sprintf(buffer, "Hys : %.2f", HYSTERESIS);
    display.println(buffer);
    sprintf(buffer, "PWMm: %d", PWM_MIN);
    display.println(buffer);

    if (WiFi.status() != WL_CONNECTED) {
        display.println("WiFi: Disconn");
    } else if (!client.connected()) {
        display.println("MQTT: Disconn");
    } else {
        display.println("NET : OK");
    }
    display.display();
  } else {
    Serial.println("Error reading temperature");
    display_message("Temp Reading", "Error!");
    delay(1000);
  }
}

void reconnect() {
  int retries = 0;
  while (!client.connected() && retries < 5) {
    Serial.print("MQTT 연결 시도 중...");
    display_message("MQTT Connecting", mqtt_server);

    if (client.connect(mqtt_client_id.c_str())) {
      Serial.println("연결됨");
      client.subscribe(topic_sub.c_str());
      display_message("MQTT Connected", mqtt_server, topic_sub.c_str());
      delay(1000);
    } else {
      Serial.print("실패, rc=");
      Serial.print(client.state());
      Serial.println(" 5초 후 다시 시도");
      display_message("MQTT Failed", "RC: " + String(client.state()), "Retrying...");
      delay(5000);
    }
    retries++;
  }
  if (!client.connected()) {
    Serial.println("MQTT 연결 실패 후 재시도 제한 도달.");
  }
}

void callback(char* topic, byte* payload, unsigned int length) {
  Serial.print("메시지 수신 [");
  Serial.print(topic);
  Serial.print("] ");
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  Serial.println(message);

  if (message == "save") {
    Serial.println("명시적 저장 명령 수신됨 ('save' 문자열)");
    save_all_settings();
    return;
  }

  StaticJsonDocument<128> jsonDoc;
  DeserializationError error = deserializeJson(jsonDoc, payload, length);

  if (!error) {
    if (jsonDoc.containsKey("settemp")) {
      float new_temp = jsonDoc["settemp"].as<float>();
      if (new_temp >= 0.0 && new_temp <= 50.0) {
        current_set_temp = new_temp;
        Serial.printf("MQTT를 통해 설정 온도 업데이트됨: %.1f C\n", current_set_temp);
      } else {
        Serial.println("MQTT를 통해 유효하지 않은 온도 범위를 수신함");
      }
    }
    if (jsonDoc.containsKey("hysteresis")) {
      float new_hysteresis = jsonDoc["hysteresis"].as<float>();
      if (new_hysteresis >= 0.05 && new_hysteresis <= 2.0) {
        HYSTERESIS = new_hysteresis;
        Serial.printf("MQTT를 통해 히스테리시스 업데이트됨: %.2f\n", HYSTERESIS);
      } else {
        Serial.println("MQTT를 통해 유효하지 않은 히스테리시스 범위를 수신함");
      }
    }
    if (jsonDoc.containsKey("pwm_min")) {
      int new_pwm_min = jsonDoc["pwm_min"].as<int>();
      if (new_pwm_min >= 0 && new_pwm_min <= 255) { // 0-255 범위 확인
        PWM_MIN = new_pwm_min;
        Serial.printf("MQTT를 통해 PWM_MIN 업데이트됨: %d\n", PWM_MIN);
      } else {
        Serial.println("MQTT를 통해 유효하지 않은 PWM_MIN 범위를 수신함");
      }
    }
    if (jsonDoc.containsKey("save") && jsonDoc["save"].as<bool>()) {
      Serial.println("JSON을 통한 저장 명령 수신됨 (save: true)");
      save_all_settings();
    }
  } else {
    Serial.print("MQTT 페이로드 JSON 파싱 오류: ");
    Serial.println(error.c_str());
  }
}

void setup_wifi() {
  delay(10);
  Serial.println();
  Serial.printf("%s에 연결 중\n", WIFI_SSID);
  display_message("WiFi Connecting", WIFI_SSID);
  esp_wifi_set_max_tx_power(20);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long wifi_connect_start = millis();
  while (WiFi.status() != WL_CONNECTED && (millis() - wifi_connect_start < 20000)) { // 20초 타임아웃
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi 연결됨");
    Serial.print("IP 주소: ");
    Serial.println(WiFi.localIP());
    display_message("WiFi connected!", WiFi.localIP().toString());
  } else {
    Serial.println("\nWiFi 연결 실패");
    display_message("WiFi Failed!", "Check SSID/Pass");
  }
  delay(1000);
}

void setup_mqtt() {
  String macAddress = WiFi.macAddress();
  macAddress.replace(":", "");
  mqtt_client_id = macAddress;
  topic_pub = mqtt_client_id + "/TEMP"+"/sta";
  topic_sub = mqtt_client_id + "/TEMP"+"/com";

  Serial.printf("MQTT 클라이언트 ID: %s\n", mqtt_client_id.c_str());
  Serial.printf("MQTT 발행 토픽: %s\n", topic_pub.c_str());
  Serial.printf("MQTT 구독 토픽: %s\n", topic_sub.c_str());

  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);
}

void setup_temp_sensor() {
  sensors.begin();
  Serial.print("발견된 ");
  Serial.print(sensors.getDeviceCount(), DEC);
  Serial.println(" Dallas 온도 센서");
  if (!sensors.getAddress(insideThermometer, 0)) {
    Serial.println("장치 0의 주소를 찾을 수 없음");
    display_message("Temp Sensor", "Not Found!");
    delay(2000);
  } else {
    Serial.print("장치 0의 주소: ");
    for (uint8_t i = 0; i < 8; i++) {
      if (insideThermometer[i] < 16) Serial.print("0"); // HEX 출력 시 자리수 맞춤
      Serial.print(insideThermometer[i], HEX);
      Serial.print(" ");
    }
    Serial.println();
  }
  sensors.setResolution(insideThermometer, 10); // 해상도 설정 (9, 10, 11, or 12 bits)
}

void setup_udp() {
  // ESP8266 방식처럼 단순하게 초기화
  if (udp.begin(UDP_PORT)) {
    Serial.printf("UDP 브로드캐스팅 초기화됨 (포트: %d)\n", UDP_PORT);
    
    // 테스트 패킷 전송 시도
    delay(500);
    Serial.println("UDP 테스트 패킷 전송 시도...");
    IPAddress test_ip(255, 255, 255, 255);
    if (udp.beginPacket(test_ip, UDP_PORT)) {
      String test_msg = topic_pub + "/TEST";
      udp.write((const uint8_t*)test_msg.c_str(), test_msg.length());
      if (udp.endPacket()) {
        Serial.println("UDP 테스트 패킷 전송 성공!");
      } else {
        Serial.println("UDP 테스트 패킷 전송 실패!");
      }
    } else {
      Serial.println("UDP 테스트 패킷 시작 실패!");
    }
  } else {
    Serial.println("UDP 초기화 실패");
  }
}

void setup() {
  Serial.begin(115200);
  while (!Serial && millis() < 2000); // 네이티브 USB C3의 경우 시리얼 포트 연결 대기
  Serial.println("\n부팅 중 (ESP32-C3 온도 조절기)");

  Serial1.begin(115200, SERIAL_8N1, SERIAL1_RX_PIN, SERIAL1_TX_PIN);
  Serial.printf("Serial1 (TX on GPIO%d) 초기화됨 - 115200 baud\n", SERIAL1_TX_PIN);

  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN); // ESP32 I2C0용 SDA, SCL 지정

  // --- LEDC PWM 설정 ---
  // ledcSetup 함수는 설정된 실제 주파수를 반환합니다.
  double actualFrequency = ledcSetup(LEDC_CHANNEL_COOLER, PWM_FREQUENCY, LEDC_RESOLUTION);
  Serial.printf("LEDC 채널 %d 설정: 요청 주파수 %dHz, 실제 주파수 %.2fHz, 해상도 %d-bit\n",
                LEDC_CHANNEL_COOLER, PWM_FREQUENCY, actualFrequency, LEDC_RESOLUTION);

  // PWM 핀(COOLER_PWM_PIN)을 설정된 LEDC 채널에 연결합니다.
  ledcAttachPin(COOLER_PWM_PIN, LEDC_CHANNEL_COOLER);
  Serial.printf("쿨러 PWM 핀 %d번이 LEDC 채널 %d번에 연결됨\n", COOLER_PWM_PIN, LEDC_CHANNEL_COOLER);
  // --- LEDC PWM 설정 완료 ---

  if (!EEPROM.begin(EEPROM_SIZE)) {
    Serial.println("EEPROM 시작 실패!");
    display_message("EEPROM Error", "Init Failed!");
    delay(2000);
    // ESP.restart(); // EEPROM이 매우 중요하다면 재시작 고려
  }

  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) { // 사용 중인 OLED의 I2C 주소 확인
    Serial.println(F("SSD1306 할당 실패"));
    while (true); // 여기서 멈춤
  }
  display_message("Initializing...");
  delay(500);

  EEPROM.get(HYSTERESIS_ADDR, HYSTERESIS);
  if (isnan(HYSTERESIS) || HYSTERESIS < 0.05 || HYSTERESIS > 2.0) {
    HYSTERESIS = 0.1; // 기본값
    EEPROM.put(HYSTERESIS_ADDR, HYSTERESIS);
    EEPROM.commit();
    Serial.println("EEPROM 히스테리시스 값이 유효하지 않아 기본값(0.1)으로 설정 및 저장됨.");
  }
  Serial.printf("EEPROM에서 히스테리시스 읽기: %.2f\n", HYSTERESIS);

  EEPROM.get(PWM_MIN_ADDR, PWM_MIN);
  if (PWM_MIN < 0 || PWM_MIN > 255) { // int형에는 isnan() 불필요
    PWM_MIN = 180; // 기본값
    EEPROM.put(PWM_MIN_ADDR, PWM_MIN);
    EEPROM.commit();
    Serial.println("EEPROM PWM_MIN 값이 유효하지 않아 기본값(180)으로 설정 및 저장됨.");
  }
  Serial.printf("EEPROM에서 PWM_MIN 읽기: %d\n", PWM_MIN);

  setup_wifi();
  if (WiFi.status() == WL_CONNECTED) {
    setup_mqtt();
    setup_udp();
  }

  setup_temp_sensor();
  current_set_temp = read_set_temp(); // NaN 처리 및 기본값 저장 로직 포함
  display_message("Set Temp Read:", String(current_set_temp, 1) + " C");
  delay(1000);

  // LEDC를 사용하므로 pinMode(COOLER_PWM_PIN, OUTPUT)는 필요 없습니다.
  // 초기 쿨러 상태는 OFF로 설정 (LEDC 사용)
  ledcWrite(LEDC_CHANNEL_COOLER, 0); // 쿨러 PWM 출력을 0으로 시작
  Serial.println("초기 쿨러 PWM 상태: OFF (LEDC 값 0)");
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi 연결 끊김. 재연결 시도 중...");
    display_message("WiFi Lost", "Reconnecting...");
    setup_wifi();
    if (WiFi.status() == WL_CONNECTED) {
      setup_mqtt(); // WiFi 재연결 시 MQTT도 재설정
    }
  } else {
    if (!client.connected()) {
      reconnect();
    }
    if (client.connected()){
      client.loop();
    }
  }

  process_sensors_and_update();
  send_heartbeat();

  delay(200); // 메인 루프 지연
}
