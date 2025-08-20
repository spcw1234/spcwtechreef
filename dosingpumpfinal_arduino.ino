// ESP32-S2 Dosing Pump Controller (FreeRTOS + Arduino)
// 주요 기능: WiFi, MQTT, 펌프 제어, 스케줄, 버튼, OLED
// 원본: dosingpumpfinal.py

#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <Adafruit_SSD1306.h>
// FreeRTOS headers (needed for TaskHandle_t, vTaskDelay, xTaskCreatePinnedToCore, etc.)
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
// File system for JSON persistence
#include <FS.h>
#include <LittleFS.h>

// --- 핀 설정 ---
#define I2C_SCL_PIN 9
#define I2C_SDA_PIN 8
#define PUMP1_IN1_PIN 4
#define PUMP1_IN2_PIN 5
#define PUMP2_IN1_PIN 6
#define PUMP2_IN2_PIN 7
#define BUTTON_UP_PIN 10
#define BUTTON_DOWN_PIN 11
#define BUTTON_LEFT_PIN 12
#define BUTTON_RIGHT_PIN 13
#define BUTTON_SELECT_PIN 18
#define BUTTON_BACK_PIN 1

// --- 디스플레이 설정 ---
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// --- WiFi 설정 ---
const char* WIFI_SSID = "SK_4974_2.4G";
const char* WIFI_PASSWORD = "BQP06@0276";

// --- MQTT 설정 ---
const char* MQTT_BROKER = "spcwtech.mooo.com";
const int MQTT_PORT = 1883;
const char* MQTT_USER = nullptr;
const char* MQTT_PASSWORD = nullptr;
WiFiClient espClient;
PubSubClient mqttClient(espClient);

// --- 기타 설정 ---
#define DEFAULT_PUMP_DURATION_MS 5000
#define MQTT_HEARTBEAT_INTERVAL_MS 5000

// --- 전역 변수 ---
TaskHandle_t pumpTaskHandle = NULL;
TaskHandle_t heartbeatTaskHandle = NULL;
TaskHandle_t buttonTaskHandle = NULL;
// 핸들: 스케줄/명령으로 개별 펌프를 실행하는 Task 핸들
TaskHandle_t pumpRunHandle[2] = {NULL, NULL};

// 버튼 이벤트 플래그 (버튼 Task에서 세팅)
volatile bool buttonEvents[6] = {false, false, false, false, false, false};

// 펌프 상태
bool pump1State = false;
bool pump2State = false;

// --- 스케줄 구조체 및 변수 ---
#include <EEPROM.h>
#define MAX_SCHEDULES 20
typedef struct {
  uint8_t hour;
  uint8_t minute;
  uint32_t duration_ms;
  uint8_t interval_days;
  bool valid;
} PumpSchedule;
PumpSchedule pumpSchedules[2][MAX_SCHEDULES]; // [0]: pump1, [1]: pump2

// EEPROM 주소
#define EEPROM_SIZE 1024
#define SCHEDULE_EEPROM_ADDR 0

// --- 스케줄 저장 ---
void saveSchedulesToEEPROM() {
  int addr = SCHEDULE_EEPROM_ADDR;
  for (int p = 0; p < 2; p++) {
    for (int i = 0; i < MAX_SCHEDULES; i++) {
      EEPROM.put(addr, pumpSchedules[p][i]);
      addr += sizeof(PumpSchedule);
    }
  }
  EEPROM.commit();
}

// --- 스케줄 로드 ---
void loadSchedulesFromEEPROM() {
  int addr = SCHEDULE_EEPROM_ADDR;
  for (int p = 0; p < 2; p++) {
    for (int i = 0; i < MAX_SCHEDULES; i++) {
      EEPROM.get(addr, pumpSchedules[p][i]);
      addr += sizeof(PumpSchedule);
    }
  }
}

// --- LittleFS 기반 파일 영속성 (schedules.json) ---
bool mountFileSystem() {
  if (!LittleFS.begin(true)) {
    Serial.println("LittleFS mount failed");
    return false;
  }
  Serial.println("LittleFS mounted");
  return true;
}

bool loadSchedulesFromFile() {
  if (!LittleFS.exists("/schedules.json")) return false;
  File f = LittleFS.open("/schedules.json", "r");
  if (!f) return false;
  size_t sz = f.size();
  std::unique_ptr<char[]> buf(new char[sz + 1]);
  f.readBytes(buf.get(), sz);
  buf[sz] = '\0';
  f.close();

  DynamicJsonDocument doc(4096);
  DeserializationError err = deserializeJson(doc, buf.get());
  if (err) {
    Serial.printf("schedules.json parse error: %s\n", err.c_str());
    return false;
  }
  // Clear existing
  for (int p=0;p<2;p++) for (int i=0;i<MAX_SCHEDULES;i++) pumpSchedules[p][i].valid = false;

  for (int p=1;p<=2;p++) {
    const char* key = String(p).c_str();
    if (!doc.containsKey(String(p))) continue;
    JsonArray arr = doc[String(p)].as<JsonArray>();
    int idx = 0;
    for (JsonVariant v : arr) {
      if (idx >= MAX_SCHEDULES) break;
      if (!v.is<JsonArray>()) continue;
      JsonArray it = v.as<JsonArray>();
      pumpSchedules[p-1][idx].hour = it[0] | 0;
      pumpSchedules[p-1][idx].minute = it[1] | 0;
      pumpSchedules[p-1][idx].duration_ms = (uint32_t)(it[2] | 0UL);
      pumpSchedules[p-1][idx].interval_days = it[3] | 1;
      pumpSchedules[p-1][idx].valid = true;
      idx++;
    }
  }
  Serial.println("Loaded schedules from file");
  return true;
}

bool saveSchedulesToFile() {
  DynamicJsonDocument doc(4096);
  for (int p=0;p<2;p++) {
    JsonArray arr = doc.createNestedArray(String(p+1));
    for (int i=0;i<MAX_SCHEDULES;i++) {
      if (pumpSchedules[p][i].valid) {
        JsonArray item = arr.createNestedArray();
        item.add(pumpSchedules[p][i].hour);
        item.add(pumpSchedules[p][i].minute);
        item.add((unsigned long)pumpSchedules[p][i].duration_ms);
        item.add(pumpSchedules[p][i].interval_days);
      }
    }
  }
  File f = LittleFS.open("/schedules.json", "w");
  if (!f) return false;
  if (serializeJson(doc, f) == 0) {
    f.close();
    return false;
  }
  f.close();
  Serial.println("Saved schedules to file");
  return true;
}
// --- 함수 선언 ---
void setupWiFi();
void reconnectMQTT();
void pumpTask(void* pvParameters);
void heartbeatTask(void* pvParameters);
void buttonTask(void* pvParameters);
void mqttCallback(char* topic, byte* payload, unsigned int length);
// 추가된 Task/함수 선언
void displayTask(void* pvParameters);
void scheduleCheckerTask(void* pvParameters);
void mqttHandlerTask(void* pvParameters);
void syncTimeNTP();
void runPumpForDuration(int pumpId, uint32_t durationMs);
void publishPumpStatus(int pumpId);

void setup() {
  Serial.begin(115200);
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  display.begin(SSD1306_SWITCHCAPVCC, 0x3C);
  display.clearDisplay();
  display.display();

  pinMode(PUMP1_IN1_PIN, OUTPUT);
  pinMode(PUMP1_IN2_PIN, OUTPUT);
  pinMode(PUMP2_IN1_PIN, OUTPUT);
  pinMode(PUMP2_IN2_PIN, OUTPUT);
  pinMode(BUTTON_UP_PIN, INPUT_PULLUP);
  pinMode(BUTTON_DOWN_PIN, INPUT_PULLUP);
  pinMode(BUTTON_LEFT_PIN, INPUT_PULLUP);
  pinMode(BUTTON_RIGHT_PIN, INPUT_PULLUP);
  pinMode(BUTTON_SELECT_PIN, INPUT_PULLUP);
  pinMode(BUTTON_BACK_PIN, INPUT_PULLUP);

  setupWiFi();
  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setCallback(mqttCallback);
  // EEPROM 및 스케줄 로드
  EEPROM.begin(EEPROM_SIZE);
  loadSchedulesFromEEPROM();

  // NTP 시간 동기화 시작
  syncTimeNTP();

  // FreeRTOS Task 생성
  xTaskCreatePinnedToCore(pumpTask, "PumpTask", 4096, NULL, 1, &pumpTaskHandle, 1);
  xTaskCreatePinnedToCore(heartbeatTask, "HeartbeatTask", 2048, NULL, 1, &heartbeatTaskHandle, 1);
  xTaskCreatePinnedToCore(buttonTask, "ButtonTask", 2048, NULL, 1, &buttonTaskHandle, 1);
  xTaskCreatePinnedToCore(displayTask, "DisplayTask", 4096, NULL, 1, NULL, 1);
  xTaskCreatePinnedToCore(scheduleCheckerTask, "SchedChk", 4096, NULL, 2, NULL, 1);
  xTaskCreatePinnedToCore(mqttHandlerTask, "MQTTHnd", 4096, NULL, 2, NULL, 1);
}

void loop() {
  if (!mqttClient.connected()) {
    reconnectMQTT();
  }
  mqttClient.loop();
  delay(10);
}

// --- WiFi 연결 함수 ---
void setupWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");
}

// --- MQTT 재연결 함수 ---
void reconnectMQTT() {
  while (!mqttClient.connected()) {
    Serial.print("Attempting MQTT connection...");
    if (mqttClient.connect("ESP32S2Client", MQTT_USER, MQTT_PASSWORD)) {
      Serial.println("connected");
  // 필요한 토픽 구독
  mqttClient.subscribe("ESP32S2/DOSE/con/pump1");
  mqttClient.subscribe("ESP32S2/DOSE/con/pump2");
  mqttClient.subscribe("ESP32S2/DOSE/con/schedule/add");
  mqttClient.subscribe("ESP32S2/DOSE/con/schedule/delete");
  mqttClient.subscribe("ESP32S2/DOSE/con/request_status");
    } else {
      Serial.print("failed, rc=");
      Serial.print(mqttClient.state());
      Serial.println(" try again in 5 seconds");
      delay(5000);
    }
  }
}

// --- 펌프 제어 Task ---
void pumpTask(void* pvParameters) {
  for (;;) {
    // 펌프 제어 로직 (예시)
    if (pump1State) {
      digitalWrite(PUMP1_IN1_PIN, HIGH);
      digitalWrite(PUMP1_IN2_PIN, LOW);
    } else {
      digitalWrite(PUMP1_IN1_PIN, LOW);
      digitalWrite(PUMP1_IN2_PIN, LOW);
    }
    if (pump2State) {
      digitalWrite(PUMP2_IN1_PIN, HIGH);
      digitalWrite(PUMP2_IN2_PIN, LOW);
    } else {
      digitalWrite(PUMP2_IN1_PIN, LOW);
      digitalWrite(PUMP2_IN2_PIN, LOW);
    }
    vTaskDelay(100 / portTICK_PERIOD_MS);
  }
    EEPROM.begin(EEPROM_SIZE);
    loadSchedulesFromEEPROM();
}

// --- Heartbeat Task ---
void heartbeatTask(void* pvParameters) {
  for (;;) {
    if (mqttClient.connected()) {
      mqttClient.publish("ESP32S2/DOSE/a", "a");
    }
    vTaskDelay(MQTT_HEARTBEAT_INTERVAL_MS / portTICK_PERIOD_MS);
  }
}

// --- 버튼 Task ---
void buttonTask(void* pvParameters) {
  // 버튼 폴링 루프 (디바운스 포함)
  const uint32_t DEBOUNCE_MS = 15;
  uint32_t lastRead[6] = {0};
  bool confirmed[6] = {false,false,false,false,false,false};
  const int pins[6] = {BUTTON_UP_PIN, BUTTON_DOWN_PIN, BUTTON_LEFT_PIN, BUTTON_RIGHT_PIN, BUTTON_SELECT_PIN, BUTTON_BACK_PIN};

  for (;;) {
    uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    for (int i=0;i<6;i++) {
      int v = digitalRead(pins[i]);
      bool pressed = (v==LOW);
      if (pressed != confirmed[i]) {
        if (now - lastRead[i] > DEBOUNCE_MS) {
          confirmed[i] = pressed;
          lastRead[i] = now;
          if (pressed) {
            buttonEvents[i] = true;
          }
        }
      } else {
        lastRead[i] = now;
      }
    }
    vTaskDelay(5 / portTICK_PERIOD_MS);
  }
}

// --- 디스플레이 업데이트 Task (간단 구현) ---
void displayTask(void* pvParameters) {
  for(;;) {
    // 간단히 메인 정보 표시
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(WHITE);
    display.setCursor(0,0);
    // 시간
    time_t nowt = time(nullptr);
    struct tm tminfo;
    localtime_r(&nowt, &tminfo);
    char buf[32];
    snprintf(buf, sizeof(buf), "%04d-%02d-%02d %02d:%02d:%02d", tminfo.tm_year+1900, tminfo.tm_mon+1, tminfo.tm_mday, tminfo.tm_hour, tminfo.tm_min, tminfo.tm_sec);
    display.println(buf);

    display.print("P1:"); display.println(pump1State?"ON":"OFF");
    display.print("P2:"); display.println(pump2State?"ON":"OFF");
    display.display();
    vTaskDelay(200 / portTICK_PERIOD_MS);
  }
}

// --- 스케줄 체크 Task ---
void scheduleCheckerTask(void* pvParameters) {
  int lastMinute = -1;
  for(;;) {
    time_t nowt = time(nullptr);
    struct tm tminfo;
    localtime_r(&nowt, &tminfo);
    int minuteOfDay = tminfo.tm_hour*60 + tminfo.tm_min;
    if (minuteOfDay != lastMinute) {
      lastMinute = minuteOfDay;
      // 체크
      for (int p=0;p<2;p++) {
        for (int i=0;i<MAX_SCHEDULES;i++) {
          if (!pumpSchedules[p][i].valid) continue;
          if (pumpSchedules[p][i].hour == tminfo.tm_hour && pumpSchedules[p][i].minute == tminfo.tm_min) {
            // 실행
            Serial.printf("Schedule triggered P%d %02d:%02d\n", p+1, tminfo.tm_hour, tminfo.tm_min);
            runPumpForDuration(p+1, pumpSchedules[p][i].duration_ms);
          }
        }
      }
    }
    vTaskDelay(1000 / portTICK_PERIOD_MS);
  }
}

// --- MQTT 핸들러 Task ---
void mqttHandlerTask(void* pvParameters) {
  for(;;) {
    if (!mqttClient.connected()) reconnectMQTT();
    mqttClient.loop();
    vTaskDelay(100 / portTICK_PERIOD_MS);
  }
}

// --- NTP 동기화 간단 구현 ---
void syncTimeNTP() {
  configTime(9*3600, 0, "pool.ntp.org", "time.google.com");
}

// --- setup 변경: task 생성 및 EEPROM init ---
// ...existing code...

// --- 펌프 실행 Task ---
typedef struct {
  int pumpId;
  uint32_t durationMs;
} PumpRunParam;

void pumpRunTask(void* pvParameters) {
  PumpRunParam* p = (PumpRunParam*)pvParameters;
  int pid = p->pumpId;
  uint32_t dur = p->durationMs;
  // 펌프 ON
  if (pid == 1) pump1State = true;
  else if (pid == 2) pump2State = true;
  publishPumpStatus(pid);

  // 대기
  vTaskDelay(dur / portTICK_PERIOD_MS);

  // 펌프 OFF
  if (pid == 1) pump1State = false;
  else if (pid == 2) pump2State = false;
  publishPumpStatus(pid);

  // 핸들 초기화
  if (pid >=1 && pid <=2) {
    pumpRunHandle[pid-1] = NULL;
  }

  free(p);
  vTaskDelete(NULL);
}

void runPumpForDuration(int pumpId, uint32_t durationMs) {
  if (pumpId < 1 || pumpId > 2) return;
  // 이미 실행중이면 무시
  if (pumpRunHandle[pumpId-1] != NULL) return;

  PumpRunParam* param = (PumpRunParam*)malloc(sizeof(PumpRunParam));
  if (!param) return;
  param->pumpId = pumpId;
  param->durationMs = durationMs;
  BaseType_t res = xTaskCreatePinnedToCore(pumpRunTask, "PumpRun", 2048, param, 2, &pumpRunHandle[pumpId-1], 1);
  if (res != pdPASS) {
    free(param);
    pumpRunHandle[pumpId-1] = NULL;
  }
}

void cancelPumpTask(int pumpId) {
  if (pumpId < 1 || pumpId > 2) return;
  TaskHandle_t h = pumpRunHandle[pumpId-1];
  if (h) {
    vTaskDelete(h);
    pumpRunHandle[pumpId-1] = NULL;
  }
}

// --- 스케줄 관리 헬퍼 ---
void addSchedule(int pumpId, int hour, int minute, uint32_t durationMs, int intervalDays) {
  if (pumpId < 1 || pumpId > 2) return;
  int idxBase = pumpId - 1;
  for (int i = 0; i < MAX_SCHEDULES; i++) {
    if (!pumpSchedules[idxBase][i].valid) {
      pumpSchedules[idxBase][i].hour = hour;
      pumpSchedules[idxBase][i].minute = minute;
      pumpSchedules[idxBase][i].duration_ms = durationMs;
      pumpSchedules[idxBase][i].interval_days = intervalDays;
      pumpSchedules[idxBase][i].valid = true;
      Serial.printf("Added schedule P%d %02d:%02d dur %lu\n", pumpId, hour, minute, durationMs);
      return;
    }
  }
  Serial.println("No space to add schedule");
}

void deleteSchedule(int pumpId, int hour, int minute) {
  if (pumpId < 1 || pumpId > 2) return;
  int idxBase = pumpId - 1;
  for (int i = 0; i < MAX_SCHEDULES; i++) {
    if (pumpSchedules[idxBase][i].valid && pumpSchedules[idxBase][i].hour == hour && pumpSchedules[idxBase][i].minute == minute) {
      pumpSchedules[idxBase][i].valid = false;
      Serial.printf("Deleted schedule P%d %02d:%02d\n", pumpId, hour, minute);
      return;
    }
  }
}

// --- MQTT 상태/스케줄 발행 헬퍼 ---
void publishPumpStatus(int pumpId) {
  String topic = String("ESP32S2/DOSE/sta/pump") + String(pumpId);
  const char* payload = ( (pumpId==1?pump1State:pump2State) ? "ON" : "OFF" );
  mqttClient.publish(topic.c_str(), payload, false);
}

void publishScheduleStatus() {
  DynamicJsonDocument doc(1024);
  for (int p=0;p<2;p++) {
    JsonArray arr = doc.createNestedArray(String(p+1));
    for (int i=0;i<MAX_SCHEDULES;i++) {
      if (pumpSchedules[p][i].valid) {
        JsonArray item = arr.createNestedArray();
        item.add(pumpSchedules[p][i].hour);
        item.add(pumpSchedules[p][i].minute);
        item.add((unsigned long)pumpSchedules[p][i].duration_ms);
        item.add(pumpSchedules[p][i].interval_days);
      }
    }
  }
  String out;
  serializeJson(doc, out);
  mqttClient.publish("ESP32S2/DOSE/sta/schedules", out.c_str(), false);
}

void publishAllStatus() {
  publishPumpStatus(1);
  publishPumpStatus(2);
  publishScheduleStatus();
}

// --- MQTT 콜백 ---
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String topicStr = String(topic);
  String msgStr = "";
  for (unsigned int i = 0; i < length; i++) msgStr += (char)payload[i];

  auto endsWith = [](const String &s, const String &suffix)->bool{
    if (s.length() < suffix.length()) return false;
    return s.substring(s.length() - suffix.length()) == suffix;
  };

  int pumpId = -1;
  if (endsWith(topicStr, "/con/pump1")) pumpId = 1;
  else if (endsWith(topicStr, "/con/pump2")) pumpId = 2;

  if (pumpId != -1) {
    if (msgStr.equalsIgnoreCase("ON")) {
      runPumpForDuration(pumpId, 1000);
    } else if (msgStr.equalsIgnoreCase("OFF")) {
      cancelPumpTask(pumpId);
      if (pumpId==1) pump1State=false; else pump2State=false;
      publishPumpStatus(pumpId);
    } else if (msgStr.startsWith("RUN:")) {
      int durationMs = msgStr.substring(4).toInt();
      if (durationMs > 0) runPumpForDuration(pumpId, durationMs);
    } else {
      Serial.printf("MQTT unknown pump cmd: %s -> %s\n", topicStr.c_str(), msgStr.c_str());
    }
    return;
  }

  if (endsWith(topicStr, "/con/schedule/add")) {
    DynamicJsonDocument doc(256);
    DeserializationError err = deserializeJson(doc, msgStr);
    if (err) { Serial.printf("Schedule add JSON parse error: %s\n", err.c_str()); return; }
    int p = doc["pump"] | 0;
    int h = doc["hour"] | -1;
    int m = doc["minute"] | -1;
    long dur = doc["duration_ms"] | 0;
    int interval = doc["interval_days"] | 1;
    if ((p==1||p==2) && h>=0 && h<24 && m>=0 && m<60 && dur>0 && interval>=1) {
      addSchedule(p, h, m, (uint32_t)dur, interval);
      publishScheduleStatus();
      saveSchedulesToEEPROM();
    } else {
      Serial.println("Invalid schedule add payload");
    }
    return;
  }

  if (endsWith(topicStr, "/con/schedule/delete")) {
    DynamicJsonDocument doc(192);
    DeserializationError err = deserializeJson(doc, msgStr);
    if (err) { Serial.printf("Schedule del JSON parse error: %s\n", err.c_str()); return; }
    int p = doc["pump"] | 0;
    int h = doc["hour"] | -1;
    int m = doc["minute"] | -1;
    if ((p==1||p==2) && h>=0 && h<24 && m>=0 && m<60) {
      deleteSchedule(p, h, m);
      publishScheduleStatus();
      saveSchedulesToEEPROM();
    }
    return;
  }

  if (endsWith(topicStr, "/con/request_status")) {
    publishAllStatus();
    return;
  }
}
