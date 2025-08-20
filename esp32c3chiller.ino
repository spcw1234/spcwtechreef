#include <WiFi.h>
#include <PubSubClient.h>
#include <Adafruit_SH110X.h>
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
#define WIRING_TOPIC_ADDR 8  // 와이어링 토픽 저장 주소

// Wi-Fi 설정
const char* WIFI_SSID = "SK_4974_2.4G";
const char* WIFI_PASSWORD = "BQP06@0276";

// MQTT 설정
const char* mqtt_server = "spcwtech.mooo.com";
const int mqtt_port = 1883;
String mqtt_client_id; // MAC 주소 기반 고유 ID
String topic_pub;      // 발행 토픽: uniqueID/CHIL/sta
String topic_sub;      // 구독 토픽: uniqueID/CHIL/con
String wiring_topic = ""; // Device wiring으로 설정된 온도 수신 토픽

WiFiClient espClient;
PubSubClient client(espClient);

// UDP 브로드캐스팅 설정
WiFiUDP udp;
IPAddress broadcastIP(255, 255, 255, 255);
const int UDP_PORT = 4210;

// 하트비트 설정
unsigned long last_heartbeat_time = 0;
const long HEARTBEAT_INTERVAL = 10000;

// Wiring 연결 확인 설정
int wiring_connected_count = 0;
unsigned long last_wiring_connected_time = 0;
const long WIRING_CONNECTED_INTERVAL = 1000; // 1초 간격으로 전송

// 온도 및 제어 설정
float current_set_temp = 26.0;
float received_temperature = 0.0; // Wiring에서 받은 온도
bool temperature_received = false; // 온도 수신 여부
unsigned long last_temp_received_time = 0; // 마지막 온도 수신 시간
const long TEMP_TIMEOUT = 30000; // 30초 타임아웃

unsigned long last_publish_time = 0;
const long PUBLISH_INTERVAL = 5000;
const long CONTROL_INTERVAL = 1000;
float HYSTERESIS = 0.1; // EEPROM에서 읽어옴
unsigned long last_control_time = 0;
bool chiller_state = false; // SSR 상태 (냉각기/펠티어)

// --- 하드웨어 핀 정의 (ESP32-C3) ---
const int I2C_SCL_PIN = 9;    // ESP32-C3 GPIO9
const int I2C_SDA_PIN = 8;    // ESP32-C3 GPIO8
#define OLED_WIDTH 128
#define OLED_HEIGHT 64
#define OLED_RESET -1  // Reset pin (or -1 if sharing Arduino reset pin)
Adafruit_SH1106G display = Adafruit_SH1106G(OLED_WIDTH, OLED_HEIGHT, &Wire, OLED_RESET);

const int SSR_PIN = 0;        // ESP32-C3 GPIO0 (SSR 제어 - 펠티어)

// --- 함수 정의 ---

void broadcast_via_udp(const char* topic, const char* message) {
  IPAddress broadcastAddress(255, 255, 255, 255);
  
  Serial.println("UDP 브로드캐스트 시작...");
  if (udp.beginPacket(broadcastAddress, UDP_PORT)) {
    String udpMessage;
    if (strcmp(message, "a") == 0) {
      udpMessage = String(topic);
    } else {
      udpMessage = String(topic) + ":" + String(message);
    }
    
    udp.write((const uint8_t*)udpMessage.c_str(), udpMessage.length());
    
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

void send_wiring_connected() {
  unsigned long current_time = millis();
  if (wiring_connected_count > 0 && current_time - last_wiring_connected_time >= WIRING_CONNECTED_INTERVAL) {
    if (client.connected()) {
      client.publish(topic_pub.c_str(), "connected", false);
      Serial.printf("Wiring connected message sent (MQTT): %s -> connected (%d/3)\n", 
                    topic_pub.c_str(), 4 - wiring_connected_count);
    } else {
      Serial.println("Wiring connected: MQTT not connected, skipping MQTT send.");
    }
    broadcast_via_udp(topic_pub.c_str(), "connected");
    
    wiring_connected_count--;
    last_wiring_connected_time = current_time;
  }
}

void display_message(String line1 = "", String line2 = "", String line3 = "", String line4 = "", String line5 = "") {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SH110X_WHITE);
  display.setCursor(0, 0);
  if (line1 != "") display.println(line1);
  if (line2 != "") display.println(line2);
  if (line3 != "") display.println(line3);
  if (line4 != "") display.println(line4);
  if (line5 != "") display.println(line5);
  display.display();
}

void save_all_settings() {
  EEPROM.put(SET_TEMP_ADDR, current_set_temp);
  EEPROM.put(HYSTERESIS_ADDR, HYSTERESIS);
  // wiring_topic도 저장
  for (int i = 0; i < 64; i++) {
    if (i < wiring_topic.length()) {
      EEPROM.write(WIRING_TOPIC_ADDR + i, wiring_topic[i]);
    } else {
      EEPROM.write(WIRING_TOPIC_ADDR + i, 0);
    }
  }
  
  if (EEPROM.commit()) {
    Serial.println("모든 설정이 EEPROM에 저장됨");
  display_message("Settings Saved:",
          String("Temp: ") + String(current_set_temp, 1) + " C",
          String("Hys : ") + String(HYSTERESIS, 2),
          String("Wiring: ") + (wiring_topic.length() > 0 ? "Set" : "None"));
  } else {
    Serial.println("EEPROM commit failed");
    display_message("EEPROM Save", "Failed!");
  }
  delay(1000);
}

void load_wiring_topic() {
  wiring_topic = "";
  for (int i = 0; i < 64; i++) {
    char c = EEPROM.read(WIRING_TOPIC_ADDR + i);
    if (c == 0) break;
    wiring_topic += c;
  }
  Serial.printf("EEPROM에서 와이어링 토픽 읽기: %s\n", wiring_topic.c_str());
}

float read_set_temp() {
  float temp;
  EEPROM.get(SET_TEMP_ADDR, temp);
  Serial.printf("EEPROM에서 설정 온도 읽기: %.1f C\n", temp);
  if (isnan(temp) || temp < 0.0 || temp > 50.0) {
    Serial.println("EEPROM 설정 온도 값이 유효하지 않거나 범위를 벗어나므로 기본값(26.0C)을 사용하고 저장합니다.");
    temp = 26.0;
    EEPROM.put(SET_TEMP_ADDR, temp);
    EEPROM.commit();
  }
  return temp;
}

float read_hysteresis() {
  float hys;
  EEPROM.get(HYSTERESIS_ADDR, hys);
  Serial.printf("EEPROM에서 히스테리시스 읽기: %.2f\n", hys);
  if (isnan(hys) || hys < 0.05 || hys > 2.0) {
    Serial.println("EEPROM 히스테리시스 값이 유효하지 않으므로 기본값(0.1)을 사용하고 저장합니다.");
    hys = 0.1;
    EEPROM.put(HYSTERESIS_ADDR, hys);
    EEPROM.commit();
  }
  return hys;
}

void control_temperature(float current_temp) {
  unsigned long current_time = millis();
  if (current_time - last_control_time >= CONTROL_INTERVAL) {
    float error = current_temp - current_set_temp;

    // SSR 제어 로직 (냉각기/펠티어) - 온도가 설정값보다 높으면 냉각 시작
    if (!chiller_state && error > HYSTERESIS) {
      chiller_state = true;
      digitalWrite(SSR_PIN, HIGH);
      Serial.println("냉각기 켜짐 (펠티어 ON)");
    } else if (chiller_state && error < -HYSTERESIS) {
      chiller_state = false;
      digitalWrite(SSR_PIN, LOW);
      Serial.println("냉각기 꺼짐 (펠티어 OFF)");
    }
    
    last_control_time = current_time;
  }
}

void process_and_update() {
  if (temperature_received) {
    // 온도 수신 타임아웃 체크
    if (millis() - last_temp_received_time > TEMP_TIMEOUT) {
      temperature_received = false;
      Serial.println("온도 수신 타임아웃");
    }
  }

  if (temperature_received) {
    control_temperature(received_temperature);

    unsigned long current_time = millis();
    if (current_time - last_publish_time >= PUBLISH_INTERVAL) {
      StaticJsonDocument<256> jsonDoc;
      jsonDoc["currentTemp"] = round(received_temperature * 100) / 100.0;
      jsonDoc["setTemp"] = round(current_set_temp * 10) / 10.0;
      jsonDoc["chiller_state"] = chiller_state;
      jsonDoc["hysteresisVal"] = HYSTERESIS;
      jsonDoc["temp_source"] = "wiring";
      jsonDoc["wiring_topic"] = wiring_topic;

      char jsonBuffer[256];
      serializeJson(jsonDoc, jsonBuffer);

      if (client.connected()) {
        client.publish(topic_pub.c_str(), jsonBuffer, true);
        Serial.printf("Published (MQTT): %s\n", jsonBuffer);
      } else {
        Serial.println("Publish: MQTT not connected, skipping MQTT publish.");
      }
      broadcast_via_udp(topic_pub.c_str(), jsonBuffer);
      last_publish_time = current_time;
    }

    // 디스플레이 업데이트
    display.clearDisplay();
  display.setCursor(0, 0);
  display.setTextSize(1);
  display.setTextColor(SH110X_WHITE);

  char buffer[64];
  snprintf(buffer, sizeof(buffer), "CHILLER");
  display.println(buffer);
  snprintf(buffer, sizeof(buffer), "Temp: %.2f C", received_temperature);
  display.println(buffer);
  snprintf(buffer, sizeof(buffer), "Set : %.1f C", current_set_temp);
  display.println(buffer);
  snprintf(buffer, sizeof(buffer), "Cool: %s", chiller_state ? "ON" : "OFF");
  display.println(buffer);
  snprintf(buffer, sizeof(buffer), "Hys : %.2f", HYSTERESIS);
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
    // 온도 데이터 없음 또는 와이어링 안됨
    display.clearDisplay();
  display.setCursor(0, 0);
  display.setTextSize(1);
  display.setTextColor(SH110X_WHITE);
    
  display.println("CHILLER");
    if (wiring_topic.length() == 0) {
      display.println("Wiring: None");
      display.println("Use device wiring");
      display.println("screen to set");
      display.println("temperature source");
    } else {
      display.println("Waiting temp...");
      display.println("Source:");
      if (wiring_topic.length() > 16) {
        display.println(wiring_topic.substring(0, 16));
        display.println(wiring_topic.substring(16));
      } else {
        display.println(wiring_topic);
      }
    }
  // reuse a temporary buffer for small formatted strings
  char buffer2[64];
  snprintf(buffer2, sizeof(buffer2), "Cool: %s", chiller_state ? "ON" : "OFF");
  display.println(buffer2);
    display.display();
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
      
      // wiring 토픽이 설정되어 있으면 구독
      if (wiring_topic.length() > 0) {
        client.subscribe(wiring_topic.c_str());
        Serial.printf("Wiring 토픽 구독: %s\n", wiring_topic.c_str());
      }
      
      // Wiring 명령 토픽도 구독 (uniqueID/CHIL/wir)
      String wiring_command_topic = mqtt_client_id + "/CHIL/wir";
      client.subscribe(wiring_command_topic.c_str());
      Serial.printf("Wiring 명령 토픽 구독: %s\n", wiring_command_topic.c_str());
      
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

  // Wiring 명령 토픽 처리 (uniqueID/CHIL/wir)
  String wiring_command_topic = mqtt_client_id + "/CHIL/wir";
  if (String(topic) == wiring_command_topic) {
    if (message == "none") {
      // 와이어링 해제
      if (wiring_topic.length() > 0) {
        client.unsubscribe(wiring_topic.c_str());
      }
      wiring_topic = "";
      temperature_received = false;
      Serial.println("Device wiring 해제됨");
    } else {
      // 새로운 와이어링 설정
      if (wiring_topic.length() > 0) {
        client.unsubscribe(wiring_topic.c_str());
      }
      wiring_topic = message;
      client.subscribe(wiring_topic.c_str());
      temperature_received = false;
      Serial.printf("Device wiring 설정됨: %s\n", wiring_topic.c_str());
      
      // 와이어링 연결 확인 메시지 3번 전송 시작
      wiring_connected_count = 3;
      last_wiring_connected_time = 0; // 즉시 전송 시작
    }
    save_all_settings();
    return;
  }

  // 와이어링 온도 토픽인지 확인
  if (wiring_topic.length() > 0 && String(topic) == wiring_topic) {
    // JSON 형태로 온도 데이터가 올 수 있음
    StaticJsonDocument<256> tempDoc;
    DeserializationError tempError = deserializeJson(tempDoc, payload, length);
    
    if (!tempError && tempDoc.containsKey("temp")) {
      // "temp" 필드에서 온도값 추출
      float temp = tempDoc["temp"].as<float>();
      if (temp > -50.0 && temp < 100.0) {
        received_temperature = temp;
        temperature_received = true;
        last_temp_received_time = millis();
        Serial.printf("Wiring에서 온도 수신 (JSON temp): %.2f C\n", received_temperature);
      }
    } else if (!tempError && tempDoc.containsKey("currentTemp")) {
      // "currentTemp" 필드 백업 (기존 호환성)
      float temp = tempDoc["currentTemp"].as<float>();
      if (temp > -50.0 && temp < 100.0) {
        received_temperature = temp;
        temperature_received = true;
        last_temp_received_time = millis();
        Serial.printf("Wiring에서 온도 수신 (JSON currentTemp): %.2f C\n", received_temperature);
      }
    } else {
      // 단순 숫자 형태
      float temp = message.toFloat();
      if (temp > -50.0 && temp < 100.0) {
        received_temperature = temp;
        temperature_received = true;
        last_temp_received_time = millis();
        Serial.printf("Wiring에서 온도 수신 (숫자): %.2f C\n", received_temperature);
      }
    }
    return;
  }

  // 일반 제어 명령 처리
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
  while (WiFi.status() != WL_CONNECTED && (millis() - wifi_connect_start < 20000)) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi 연결됨");
    Serial.print("IP 주소: ");
    Serial.println(WiFi.localIP());
    display_message("WiFi Connected", WiFi.localIP().toString());
    delay(2000);
  } else {
    Serial.println("\nWiFi 연결 실패!");
    display_message("WiFi Failed", "Check credentials");
    delay(2000);
  }
}

void setup() {
  Serial.begin(115200);
  Serial.println("ESP32-C3 Chiller Controller 시작 중...");

  // EEPROM 초기화
  if (!EEPROM.begin(EEPROM_SIZE)) {
    Serial.println("EEPROM 초기화 실패!");
    return;
  }

  // 디스플레이 초기화 (SH1106)
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  if (!display.begin(0x3C, true)) { // I2C 주소 0x3C, reset 활성화
    Serial.println("SH1106 OLED 디스플레이 초기화 실패!");
    for (;;);
  }
  display.clearDisplay();
  display.display();
  display_message("ESP32-C3", "Chiller", "Controller", "Starting...");
  delay(2000);

  // SSR 핀 초기화
  pinMode(SSR_PIN, OUTPUT);
  digitalWrite(SSR_PIN, LOW);

  // MAC 주소 기반 고유 ID 생성
  mqtt_client_id = WiFi.macAddress();
  mqtt_client_id.replace(":", "");
  Serial.printf("MQTT 클라이언트 ID: %s\n", mqtt_client_id.c_str());

  // 토픽 설정 (CHIL 타입)
  topic_pub = mqtt_client_id + "/CHIL/sta";
  topic_sub = mqtt_client_id + "/CHIL/con";

  Serial.printf("발행 토픽: %s\n", topic_pub.c_str());
  Serial.printf("구독 토픽: %s\n", topic_sub.c_str());

  // EEPROM에서 설정 읽기
  current_set_temp = read_set_temp();
  HYSTERESIS = read_hysteresis();
  load_wiring_topic();

  Serial.printf("현재 설정 온도: %.1f C\n", current_set_temp);
  Serial.printf("현재 히스테리시스: %.2f\n", HYSTERESIS);
  Serial.printf("와이어링 토픽: %s\n", wiring_topic.c_str());

  // WiFi 연결
  setup_wifi();

  // MQTT 설정
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);

  // UDP 초기화
  udp.begin(UDP_PORT);
  Serial.printf("UDP 브로드캐스트 포트 %d로 초기화됨\n", UDP_PORT);

  display_message("Setup Complete", "CHIL Controller", "Ready");
  delay(2000);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi 연결이 끊어짐. 재연결 시도 중...");
    setup_wifi();
  }

  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  send_heartbeat();
  send_wiring_connected(); // Wiring 연결 확인 메시지 전송
  process_and_update();

  delay(100);
}
