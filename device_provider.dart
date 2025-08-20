import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart'; // WidgetsBindingObserver를 위해 추가
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; // 백그라운드 유지
import 'package:permission_handler/permission_handler.dart'; // 권한 관리
import 'device.dart'; // Device 클래스 정의 파일
import 'local_storage_service.dart'; // LocalStorageService 클래스 정의 파일
import 'temperature_history_service.dart'; // 온도 히스토리 서비스 추가

/**
 * DeviceProvider 클래스
 *
 * MQTT를 통해 ESP32 장치들과 통신하는 메인 클래스
 * * 토픽 구조:
 * - 수신 (ESP32 → Flutter): uniqueID/장치종류/sta  (상태 데이터 + 하트비트)
 * - 송신 (Flutter → ESP32): uniqueID/장치종류/com  (명령어)
 *
 * ESP32는 다음을 보냄:
 * 1. 하트비트: uniqueID/장치종류/sta 에 "a" 메시지
 * 2. 데이터: uniqueID/장치종류/sta 에 JSON 데이터
 *
 * Flutter는 다음을 보냄:
 * 1. 명령어: uniqueID/장치종류/com 에 JSON 명령 또는 텍스트 명령
 */
class DeviceProvider with ChangeNotifier, WidgetsBindingObserver {
  final LocalStorageService _localStorageService = LocalStorageService();
  final TemperatureHistoryService _temperatureHistoryService = TemperatureHistoryService();

  List<Device> _devices = [];
  MqttServerClient? _mqttClient;
  bool _isDiscovering = false;
  Map<String, String> _discoveredDevicesDuringScan = {}; // deviceId -> deviceType
  Timer? _reconnectTimer; // 재연결 타이머 추가
  Timer? _dataLoggingTimer; // 온도 데이터 로깅 타이머 추가
  // 장치 배선(와이어링) 설정: targetDeviceId -> sourceTopic (예: sourceId/TEMP/sta)
  Map<String, String> _deviceWiringMap = {}; // 로컬 저장 및 UI 제공
  // 도징 펌프 정보 (id -> 상태)
  final Map<String, DosingPumpInfo> _dosingPumps = {}; // 펌프 상태/스케줄 관리
  // Waterlevel 정보 (id -> 상태)
  final Map<String, WaterLevelInfo> _waterLevels = {};

  // Getter들
  List<Device> get devices => _devices;
  bool get isDiscovering => _isDiscovering;
  Map<String, String> get discoveredDevicesDuringScan => _discoveredDevicesDuringScan;
  Map<String, String> get deviceWiringMap => _deviceWiringMap;
  Map<String, DosingPumpInfo> get dosingPumps => _dosingPumps;
  Map<String, WaterLevelInfo> get waterLevels => _waterLevels;
  
  DosingPumpInfo? getDoseInfo(String deviceId) => _dosingPumps[deviceId];
  WaterLevelInfo? getWaterLevelInfo(String deviceId) => _waterLevels[deviceId];

  // MQTT 브로커 설정
  final String _mqttBroker = 'spcwtech.mooo.com';
  final int _mqttPort = 1883;
  // 와일드카드 토픽: 모든 장치의 상태를 수신하기 위함
  // +/TEMP/sta 는 모든 uniqueID/TEMP/sta 토픽을 구독함
  // static const String _mqttStatusWildcardTopic = '+/TEMP/sta'; // 이전 버전
  static const String _mqttStatusWildcardTopic = '+/+/sta'; // 변경: 모든 장치 유형의 상태 구독
  static const String _mqttDoseWildcardTopic = '+/DOSE/#'; // 도징 펌프 전용 전체 구독
  static const String _mqttDoseHeartbeatTopic = '+/DOSE/a';
  static const String _mqttWlvWildcardTopic = '+/Wlv'; // waterlevel 장치 구독

  /**
   * 생성자: 앱 시작 시 자동으로 실행됨
   */
  DeviceProvider() {
    print('DeviceProvider 초기화 시작');
    WidgetsBinding.instance.addObserver(this); // 앱 라이프사이클 관찰자 등록
    _requestBackgroundPermissions(); // 백그라운드 권한 요청
    _loadDevices();    // 저장된 장치 목록 로드
    _loadDeviceWiring(); // 저장된 배선 정보 로드
    _initMqttClient(); // MQTT 클라이언트 초기화
    _connectMqtt();    // MQTT 브로커에 연결
    _startPeriodicReconnection(); // 주기적 연결 확인 시작
    _startDataLogging(); // 온도 데이터 로깅 시작
    print('DeviceProvider 초기화 완료');
  }

  /**
   * 저장된 장치 목록을 로컬 스토리지에서 불러오기
   */
  Future<void> _loadDevices() async {
    print('저장된 장치 목록 로딩 중...');
    _devices = await _localStorageService.loadDevices();
    print('로드된 장치 수: ${_devices.length}');
    notifyListeners(); // UI 업데이트
  }
  /**
   * 현재 장치 목록을 로컬 스토리지에 저장
   */
  Future<void> _saveDevices() async {
    print('장치 목록 저장 중... (총 ${_devices.length}개)');
    await _localStorageService.saveDevices(_devices);
    print('장치 목록 저장 완료');
  }
  Future<void> _saveDeviceWiring() async {
    print('배선 맵 저장 중... (${_deviceWiringMap.length}개 연결)');
    await _localStorageService.saveDeviceWiring(_deviceWiringMap);
  }

  Future<void> _loadDeviceWiring() async {
    print('배선 맵 로드 중...');
    _deviceWiringMap = await _localStorageService.loadDeviceWiring();
    print('로드된 배선 수: ${_deviceWiringMap.length}');
  }

  /**
   * 앱 라이프사이클 상태 변화 처리
   */
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('앱 라이프사이클 상태 변화: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // 앱이 다시 활성화되었을 때 MQTT 연결 확인
        print('앱 활성화됨 - MQTT 연결 상태 확인 및 재연결');
        _checkAndReconnectMqtt();
        // 주기적 재연결 타이머 재시작 (포그라운드 모드)
        _startPeriodicReconnection();
        // WakeLock 다시 활성화 (필요시)
        WakelockPlus.enable();
        break;
      case AppLifecycleState.paused:
        // 앱이 백그라운드로 이동했을 때
        print('앱 백그라운드로 이동 - MQTT 연결 유지 모드');
        // 백그라운드에서도 연결을 유지하지만 더 적극적으로 관리
        _startBackgroundMaintenance();
        break;
      case AppLifecycleState.inactive:
        // 앱이 비활성화되었을 때 (전화 수신 등)
        print('앱 비활성화됨 - 연결 유지');
        break;
      case AppLifecycleState.detached:
        // 앱이 완전히 종료되었을 때
        print('앱 종료됨');
        break;
      case AppLifecycleState.hidden:
        // 앱이 숨겨졌을 때 (최신 Flutter에서 추가됨)
        print('앱 숨겨짐 - 백그라운드 모드 유지');
        _startBackgroundMaintenance();
        break;
    }
  }

  /**
   * 백그라운드에서의 MQTT 연결 유지 관리
   */
  void _startBackgroundMaintenance() {
    // 기존 타이머가 있다면 취소
    _reconnectTimer?.cancel();

    print('백그라운드 유지 모드 시작 - 연결 상태를 더 자주 확인합니다');

    // 백그라운드에서는 더 짧은 간격으로 연결 상태 확인 (10초)
    _reconnectTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      final isConnected = _mqttClient?.connectionStatus?.state == MqttConnectionState.connected;

      if (!isConnected) {
        print('백그라운드 체크: MQTT 연결 끊어짐 감지 - 즉시 재연결 시도');
        _connectMqtt();
      } else {
        // 연결된 상태에서도 주기적으로 연결 상태 확인
        print('백그라운드 연결 확인 - 상태: ${_mqttClient?.connectionStatus?.state}');

        // 연결 상태가 불안정하면 재연결 시도
        if (_mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
          print('백그라운드 체크: 연결 상태 불안정 - 재연결 시도');
          _connectMqtt();
        }
      }
    });
  }

  /**
   * MQTT 연결 상태 확인 및 재연결
   */
  Future<void> _checkAndReconnectMqtt() async {
    if (_mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
      print('MQTT 연결이 끊어진 상태 - 재연결 시도');
      await _connectMqtt();
    } else {
      print('MQTT 연결 상태 양호');
    }
  }

  /// Public helper to request a reconnect from UI
  Future<void> requestReconnect() async {
    await _checkAndReconnectMqtt();
  }

  /**
   * 주기적 MQTT 연결 확인 시작 (포그라운드용)
   */
  void _startPeriodicReconnection() {
    // 기존 타이머가 있다면 취소
    _reconnectTimer?.cancel();

    // 포그라운드에서는 30초 간격으로 체크
    _reconnectTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
        print('주기적 체크: MQTT 연결 끊어짐 감지 - 재연결 시도');
        _connectMqtt();
      }
    });
  }
  /**
   * MQTT 클라이언트 초기화
   * 연결 설정, 콜백 함수들 등록
   */
  void _initMqttClient() {
    print('MQTT 클라이언트 초기화 중...');

    // 고유한 클라이언트 ID 생성 (현재 시간 기반)
    String clientId = 'flutter_client_${DateTime.now().millisecondsSinceEpoch}';
    _mqttClient = MqttServerClient(_mqttBroker, clientId);
    
    // MQTT 설정 (백그라운드 연결 유지를 위한 설정 강화)
    _mqttClient!.port = _mqttPort;
    _mqttClient!.logging(on: false); // 로깅 끄기 (필요시 true로 변경)
    _mqttClient!.keepAlivePeriod = 10; // 10초마다 연결 확인 (더욱 단축)
    _mqttClient!.autoReconnect = true; // 자동 재연결 활성화
    _mqttClient!.resubscribeOnAutoReconnect = true; // 재연결 시 자동 재구독
    
    // 백그라운드 연결 유지를 위한 추가 설정
    // connectionTimeout은 connect() 메서드에서 설정해야 함
    _mqttClient!.disconnectOnNoResponsePeriod = 60; // 60초 동안 응답이 없으면 재연결

    // 콜백 함수들 등록
    _mqttClient!.onDisconnected = _onMqttDisconnected; // 연결 끊김 시
    _mqttClient!.onConnected = _onMqttConnected;       // 연결 성공 시
    _mqttClient!.onSubscribed = _onMqttSubscribed;     // 구독 성공 시
    _mqttClient!.pongCallback = _pong;                 // Ping 응답 수신 시
    _mqttClient!.onAutoReconnect = _onMqttAutoReconnect; // 자동 재연결 시
    _mqttClient!.onAutoReconnected = _onMqttAutoReconnected; // 자동 재연결 완료 시
    
    // 연결 메시지 설정 (백그라운드 연결 유지 강화)
  // connection message: start clean and set will qos
  final connMess = MqttConnectMessage()
    .withClientIdentifier(_mqttClient!.clientIdentifier)
    .startClean()
    .withWillQos(MqttQos.atLeastOnce);
  // keepAlivePeriod already set on client earlier (_mqttClient!.keepAlivePeriod = 10)
    _mqttClient!.connectionMessage = connMess;

    print('MQTT 클라이언트 초기화 완료. 클라이언트 ID: $clientId');
  }
  /**
   * MQTT 브로커에 연결 시도
   */
  Future<void> _connectMqtt() async {
    // 이미 연결되어 있으면 종료
    if (_mqttClient?.connectionStatus?.state == MqttConnectionState.connected) {
      print('MQTT: 이미 연결되어 있음');
      return;
    }

    try {
      print('MQTT: $_mqttBroker:$_mqttPort 에 연결 시도 중...');
      // 연결 timeout 설정 (10초)
      await _mqttClient?.connect().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('MQTT: 연결 시간 초과 (10초)');
          _mqttClient?.disconnect();
          return null;
        },
      );
    } catch (e) {
      print('MQTT: 연결 중 예외 발생 - $e');
      _mqttClient?.disconnect();
    }
  }

  /**
   * MQTT 연결 성공 시 호출되는 콜백
   * 여기서 필요한 토픽들을 구독함
   */
  void _onMqttConnected() {
    print('MQTT: 브로커에 연결 성공!');

    // 모든 장치의 상태를 수신하기 위한 와일드카드 토픽 구독
    // +/+/sta 는 모든 uniqueID/deviceType/sta 와 매칭됨
    print('MQTT: 와일드카드 토픽 구독 시도 - $_mqttStatusWildcardTopic');
    _mqttClient?.subscribe(_mqttStatusWildcardTopic, MqttQos.atLeastOnce);
    
    // 도징 펌프 토픽 구독 (심층 구조 지원)
    _mqttClient?.subscribe(_mqttDoseWildcardTopic, MqttQos.atLeastOnce);
    _mqttClient?.subscribe(_mqttDoseHeartbeatTopic, MqttQos.atLeastOnce);
  // waterlevel 토픽 구독
  print('MQTT: WaterLevel 토픽 구독 시도 - $_mqttWlvWildcardTopic');
  _mqttClient?.subscribe(_mqttWlvWildcardTopic, MqttQos.atLeastOnce);

    // 메시지 수신 리스너 등록
    _mqttClient?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final String topic = c[0].topic;
      final String payloadText = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      // 디버깅용 로그 (필요시 주석 해제)
      // print('MQTT 수신: Topic=[$topic], Payload=[$payloadText]');

      // 수신된 메시지 처리
      _handleMqttMessage(topic, payloadText);
    });
  }

  /**
   * MQTT 연결 끊김 시 호출되는 콜백
   */
  void _onMqttDisconnected() {
    print('MQTT: 브로커와의 연결이 끊어짐');

    // 모든 장치를 연결 끊김 상태로 변경
    for (var device in _devices) {
      if (device.isConnected) {
        device.isConnected = false;
        print('장치 ${device.customName} (${device.id}) 연결 끊김으로 표시');
      }
    }
    notifyListeners(); // UI 업데이트
  }
  /**
   * MQTT Ping 응답 수신 시 호출
   */
  void _pong() {
    print('MQTT: Ping 응답 수신 (연결 상태 양호)');
  }

  /**
   * MQTT 자동 재연결 시작 시 호출
   */
  void _onMqttAutoReconnect() {
    print('MQTT: 자동 재연결 시작');
  }

  /**
   * MQTT 자동 재연결 완료 시 호출
   */
  void _onMqttAutoReconnected() {
    print('MQTT: 자동 재연결 완료');
    // 재연결 후 토픽 재구독
    _mqttClient?.subscribe(_mqttStatusWildcardTopic, MqttQos.atLeastOnce);
  }

  /**
   * MQTT 토픽 구독 성공 시 호출되는 콜백
   */
  void _onMqttSubscribed(String topic) {
    print('MQTT: 토픽 [$topic] 구독 성공');

    if (topic == _mqttStatusWildcardTopic) {
      print('MQTT: 와일드카드 토픽 구독 완료. 모든 장치의 상태 수신 준비됨');
    }
  }
  /**
   * 수신된 MQTT 메시지를 처리하는 메인 함수
   *
   * @param topic 메시지를 받은 토픽
   * @param payload 메시지 내용
   */
  void _handleMqttMessage(String topic, String payload) {
    // 도징 펌프 토픽 우선 처리 (uniqueID/DOSE/...)
    if (_isDoseTopic(topic)) {
      _handleDoseMessage(topic, payload);
      return;
    }
    // waterlevel 토픽 예: uniqueID/Wlv
    if (_isWlvTopic(topic)) {
      _handleWlvMessage(topic, payload);
      return;
    }
    // uniqueID/deviceType/sta 또는 uniqueID/CV/gst 형태의 토픽 처리
    // 예: "abcdef123456/TEMP/sta", "abcdef123456/ORP/sta", "abcdef123456/CV/gst"
    final topicParts = topic.split('/');
    if (topicParts.length != 3) {
      print('MQTT: 처리하지 않는 토픽 형식 - $topic');
      return;
    }

    String deviceId = topicParts[0];
    String deviceType = topicParts[1]; // "TEMP", "ORP", "CV" 등
    String messageType = topicParts[2]; // "sta", "gst" 등

    if (deviceId.isEmpty) {
      print('MQTT 오류: 토픽에서 장치 ID를 추출할 수 없음 - $topic');
      return;
    }

    // 지원하는 메시지 타입 확인
    if (messageType != 'sta' && messageType != 'gst') {
      print('MQTT: 처리하지 않는 메시지 타입 - $topic');
      return;
    }

    print('MQTT: 장치 $deviceId 로부터 $messageType 메시지 수신');

    // CV 장치의 GST 메시지 처리 (RTSP URL)
    if (deviceType == "CV" && messageType == "gst") {
      _handleGstMessage(deviceId, payload);
      return;
    }

    // STA 메시지만 처리 (기존 로직)
    if (messageType != 'sta') {
      return;
    }

    // 1. 하트비트 메시지 처리 (payload가 "a"인 경우)
    if (payload.toLowerCase().trim() == "a") {
      _handleHeartbeatMessage(deviceId, deviceType, topic);
      return;
    }

    // 2. CHIL 장치의 연결 확인 메시지 처리 (payload가 "connected"인 경우)
    if (payload.toLowerCase().trim() == "connected" && deviceType == "CHIL") {
      _handleChillerConnectedMessage(deviceId, deviceType, topic);
      return;
    }

    // 3. JSON 데이터 메시지 처리
    _handleDataMessage(deviceId, deviceType, payload);
  }

  bool _isDoseTopic(String topic) {
    final parts = topic.split('/');
    return parts.length >= 3 && parts[1] == 'DOSE';
  }

  bool _isWlvTopic(String topic) {
    final parts = topic.split('/');
    return parts.length >= 2 && parts[1] == 'Wlv';
  }

  void _ensureDoseDeviceRegistered(String deviceId) {
    // Ensure we have a DosingPumpInfo for runtime state, but do NOT auto-register the device.
    if (!_dosingPumps.containsKey(deviceId)) {
      _dosingPumps[deviceId] = DosingPumpInfo();
    }
  }

  void _ensureWlvDeviceRegistered(String deviceId) {
    // Keep runtime info but do NOT auto-register the device in the saved device list.
    if (!_waterLevels.containsKey(deviceId)) {
      _waterLevels[deviceId] = WaterLevelInfo();
      // Load saved offset asynchronously
      _loadWaterLevelOffset(deviceId).then((savedOffset) {
        if (savedOffset != null) {
          final info = _waterLevels[deviceId];
          if (info != null) {
            info.offsetCm = savedOffset;
            notifyListeners();
            print('Loaded water level offset for $deviceId: $savedOffset cm');
          }
        }
      });
    }
  }

  void _handleWlvMessage(String topic, String payload) {
    final parts = topic.split('/');
    if (parts.isEmpty) return;
    final deviceId = parts[0];

    // payload expected: JSON like {"distance_cm": 12.34}
    try {
      final data = jsonDecode(payload);
      if (data is Map<String, dynamic> && data['distance_cm'] != null) {
        final raw = (data['distance_cm'] as num).toDouble();
        _onNewWlvReading(deviceId, raw);
      }
    } catch (e) {
      print('Wlv JSON 파싱 오류: $e');
    }
  }

  // Handle a new water level reading: discovery, runtime info, history
  void _onNewWlvReading(String deviceId, double distanceCm) {
    final alreadyRegistered = _devices.any((d) => d.id == deviceId);

    // Debug log
    print('MQTT: Wlv reading from $deviceId raw=${distanceCm.toStringAsFixed(2)}, discovering=$_isDiscovering, alreadyRegistered=$alreadyRegistered');

    // If we're scanning and this device isn't registered, add to discovery list
    if (_isDiscovering && !alreadyRegistered && !_discoveredDevicesDuringScan.containsKey(deviceId)) {
      _discoveredDevicesDuringScan[deviceId] = 'Wlv';
      print('MQTT Discovery: Wlv added to discovery list: $deviceId');
      notifyListeners(); // notify quickly so UI shows discovered entry
    }

    // Ensure runtime info exists and update
    _ensureWlvDeviceRegistered(deviceId);
    final info = _waterLevels[deviceId]!;
    info.distanceCm = distanceCm;
    info.lastUpdate = DateTime.now();
    info.online = true;

    // Store adjusted value (apply offset) in history for plotting and change detection
    final adjusted = distanceCm + (info.offsetCm ?? 0.0);
    info.history.add(WaterLevelRecord(info.lastUpdate!, adjusted));
    // Keep history bounded
    if (info.history.length > 300) {
      info.history.removeRange(0, info.history.length - 300);
    }

    notifyListeners();
  }

  /// Set offset (cm) for a given Wlv device
  void setWaterLevelOffset(String deviceId, double offsetCm) {
    _ensureWlvDeviceRegistered(deviceId);
    final info = _waterLevels[deviceId]!;
    info.offsetCm = offsetCm;
    notifyListeners();
    // Persist offset in local storage
  print('DeviceProvider: setWaterLevelOffset called for $deviceId -> $offsetCm cm');
  _saveWaterLevelOffset(deviceId, offsetCm);
  }

  /// Save water level offset to local storage
  void _saveWaterLevelOffset(String deviceId, double offsetCm) async {
    try {
  await _localStorageService.setDouble('wlv_offset_$deviceId', offsetCm);
  print('DeviceProvider: Water level offset saved for $deviceId: $offsetCm cm');
    } catch (e) {
  print('DeviceProvider: Failed to save water level offset for $deviceId: $e');
    }
  }

  /// Load water level offset from local storage
  Future<double?> _loadWaterLevelOffset(String deviceId) async {
    try {
  final v = await _localStorageService.getDouble('wlv_offset_$deviceId');
  print('DeviceProvider: _loadWaterLevelOffset for $deviceId -> $v');
  return v;
    } catch (e) {
  print('DeviceProvider: Failed to load water level offset for $deviceId: $e');
      return null;
    }
  }

  /// Return history records for a waterlevel device
  List<WaterLevelRecord> getWaterLevelHistory(String deviceId) {
    final info = _waterLevels[deviceId];
    if (info == null) return <WaterLevelRecord>[];
    return List<WaterLevelRecord>.from(info.history);
  }

  void _handleDoseMessage(String topic, String payload) {
    final parts = topic.split('/');
    if (parts.length < 3) return;
    final deviceId = parts[0]; // uniqueID
    final second = parts[1]; // DOSE
    if (second != 'DOSE') return;
    _ensureDoseDeviceRegistered(deviceId);
    final info = _dosingPumps[deviceId]!;
    // Heartbeat (uniqueID/DOSE/a)
    if (parts.length == 3 && parts[2] == 'a') {
      info.lastHeartbeat = DateTime.now();
      info.online = true;
      if (_isDiscovering && !_discoveredDevicesDuringScan.containsKey(deviceId)) {
        _discoveredDevicesDuringScan[deviceId] = 'DOSE';
      }
      notifyListeners();
      return;
    }

    // Aggregated status (uniqueID/DOSE/sta) -> JSON 포함 가정
    if (parts.length == 3 && parts[2] == 'sta') {
      try {
        final data = jsonDecode(payload);
        // 예상 키: pump1, pump2, schedules, log, online
        if (data is Map<String, dynamic>) {
          if (data['pump1'] != null) {
            info.pump1On = data['pump1'].toString().toUpperCase() == 'ON' || data['pump1'] == true;
          }
            if (data['pump2'] != null) {
            info.pump2On = data['pump2'].toString().toUpperCase() == 'ON' || data['pump2'] == true;
          }
          if (data['schedules'] != null) {
            info.schedules = Map<String,dynamic>.from(data['schedules']);
          }
          if (data['log'] != null) info.lastLog = data['log'].toString();
          if (data['online'] != null) info.online = data['online'].toString().toLowerCase() == 'true';
          info.lastHeartbeat = DateTime.now();
          if (_isDiscovering && !_discoveredDevicesDuringScan.containsKey(deviceId)) {
            _discoveredDevicesDuringScan[deviceId] = 'DOSE';
          }
          notifyListeners();
        }
      } catch (e) {
        print('DOSE 통합 상태 JSON 파싱 오류: $e');
      }
      return;
    }

    // 세분화된 상태 (uniqueID/DOSE/sta/pump1 등) 기존 펌웨어 호환
    if (parts.length >= 4) {
      final section = parts[2]; // sta 또는 con 등
      final tail = parts.sublist(3).join('/');
      if (section == 'sta') {
        if (tail == 'pump1') {
          info.pump1On = payload.trim().toUpperCase() == 'ON';
        } else if (tail == 'pump2') {
          info.pump2On = payload.trim().toUpperCase() == 'ON';
        } else if (tail == 'schedules') {
          try {
            final data = jsonDecode(payload);
            info.schedules = data; // Map<String,dynamic>
          } catch (e) {
            print('DOSE 스케줄 파싱 오류: $e');
          }
        } else if (tail == 'online') {
          info.online = payload.trim().toLowerCase() == 'true';
        } else if (tail == 'log') {
          info.lastLog = payload;
        }
        if (_isDiscovering && !_discoveredDevicesDuringScan.containsKey(deviceId)) {
          _discoveredDevicesDuringScan[deviceId] = 'DOSE';
        }
        notifyListeners();
      }
    }
  }

  // ===== 도징 펌프 제어 메서드 =====
  String _doseBase(String id) => '$id/DOSE';
  
  // 불필요한 상태 요청 메서드 - DOSE 장치는 자동으로 상태를 전송함
  // void requestDoseStatus(String deviceId) {
  //   final topic = '${_doseBase(deviceId)}/con/request_status';
  //   sendMqttMessage(topic, 'req');
  // }
  
  void dosePumpOn(String deviceId, int pump) {
    final topic = '${_doseBase(deviceId)}/con/pump$pump';
    sendMqttMessage(topic, 'ON');
  }
  void dosePumpOff(String deviceId, int pump) {
    final topic = '${_doseBase(deviceId)}/con/pump$pump';
    sendMqttMessage(topic, 'OFF');
  }
  void dosePumpRun(String deviceId, int pump, int durationMs) {
    final topic = '${_doseBase(deviceId)}/con/pump$pump';
    sendMqttMessage(topic, 'RUN:$durationMs');
  }
  void addDoseSchedule(String deviceId, {required int pump, required int hour, required int minute, required int durationMs, int intervalDays = 1}) {
    final topic = '${_doseBase(deviceId)}/con/schedule/add';
    final payload = jsonEncode({
      'pump': pump,
      'hour': hour,
      'minute': minute,
      'duration_ms': durationMs,
      'interval_days': intervalDays,
    });
    sendMqttMessage(topic, payload);
  }
  // 보정: ml 기준 런 (앱에서 RUN:ms 대신 ml 전송 단순화 가능 – 펌웨어엔 ml 전용 별도 명령 없으므로 변환 필요)
  void deleteDoseSchedule(String deviceId, {required int pump, required int hour, required int minute}) {
    final topic = '${_doseBase(deviceId)}/con/schedule/delete';
    final payload = jsonEncode({
      'pump': pump,
      'hour': hour,
      'minute': minute,
    });
    sendMqttMessage(topic, payload);
  }

  // 펌프 이름 변경 메서드
  void updatePumpName(String deviceId, int pump, String newName) {
    final info = _dosingPumps[deviceId];
    if (info != null) {
      if (pump == 1) {
        info.pump1Name = newName;
      } else if (pump == 2) {
        info.pump2Name = newName;
      }
      notifyListeners();
      // 로컬 저장소에 저장 (필요시 추가 구현)
    }
  }

  /**
   * 하트비트 메시지 처리
   */
  void _handleHeartbeatMessage(String deviceId, String deviceType, String topic) {
    print('MQTT: 장치 $deviceId (유형: $deviceType) 하트비트 수신');

    // 이미 등록된 장치인지 확인
    final knownDeviceIndex = _devices.indexWhere((d) => d.id == deviceId);
    if (knownDeviceIndex != -1) {
      // 등록된 장치의 연결 상태 업데이트
      Device knownDevice = _devices[knownDeviceIndex];
      if (!knownDevice.isConnected) {
        knownDevice.isConnected = true;
        print('MQTT: 등록된 장치 ${knownDevice.customName} ($deviceId) 온라인 상태로 변경');
        notifyListeners(); // UI 업데이트
      }
    }

    // 장치 검색 모드일 때만 새 장치 발견 처리
    if (_isDiscovering) {
      // 이번 검색에서 처음 발견하는 경우만 추가, 단 이미 등록된 장치는 제외
      bool alreadyRegistered = _devices.any((d) => d.id == deviceId);
      bool isFirstTimeDiscovered = !_discoveredDevicesDuringScan.containsKey(deviceId);

      if (!alreadyRegistered && isFirstTimeDiscovered) {
        print('MQTT Discovery: 새로운 장치 발견! ID=$deviceId, 유형=$deviceType');
        _discoveredDevicesDuringScan[deviceId] = deviceType; // ID와 유형 함께 저장
        notifyListeners(); // UI 업데이트 (검색 목록에 표시)
      }
    }
  }

  /**
   * CHIL 장치의 연결 확인 메시지 처리
   */
  void _handleChillerConnectedMessage(String deviceId, String deviceType, String topic) {
    print('MQTT: CHIL 장치 $deviceId wiring 연결 확인 메시지 수신');

    // 등록된 장치인지 확인
    final knownDeviceIndex = _devices.indexWhere((d) => d.id == deviceId);
    if (knownDeviceIndex != -1) {
      // 연결 상태 업데이트
      Device knownDevice = _devices[knownDeviceIndex];
      if (!knownDevice.isConnected) {
        knownDevice.isConnected = true;
        print('MQTT: CHIL 장치 ${knownDevice.customName} ($deviceId) 연결 확인됨');
      }
      notifyListeners(); // UI 업데이트
    }
  }

  /**
   * 데이터 메시지 처리 (JSON 형태)
   */
  void _handleDataMessage(String deviceId, String deviceType, String payload) {
    // 등록된 장치인지 확인
    final registeredDeviceIndex = _devices.indexWhere((d) => d.id == deviceId);

    // 미등록 장치인 경우
    if (registeredDeviceIndex == -1) {
      print('MQTT: 미등록 장치 $deviceId ($deviceType) 로부터 데이터 수신');

      // 장치 검색 모드인 경우 새 장치를 발견 목록에 추가
      if (_isDiscovering) {
        print('MQTT: 장치 검색 모드 - 새 장치 $deviceId ($deviceType) 발견됨');
        _discoveredDevicesDuringScan[deviceId] = deviceType;
        notifyListeners(); // UI 업데이트하여 발견된 장치 표시
      } else {
        print('MQTT: 검색 모드가 아니므로 미등록 장치 무시');
      }
      return;
    }

    final device = _devices[registeredDeviceIndex];
    print('MQTT: 등록된 장치 ${device.customName} ($deviceId) 데이터 수신');

    try {
      // JSON 파싱
      final Map<String, dynamic> jsonPayload = jsonDecode(payload);
      print('MQTT: Raw JSON payload for ${device.customName}: $jsonPayload');
      final data = DeviceData.fromJson(jsonPayload);
      print('MQTT: Parsed DeviceData for ${device.customName}: setTemp=${data.setTemp}, hysteresisVal=${data.hysteresisVal}, chillerState=${data.chillerState}');

      // 장치 데이터 업데이트
      bool hasChanges = false;

      // 공통 데이터 업데이트
      if (data.currentTemp != null && device.currentTemp != data.currentTemp) {
        device.currentTemp = data.currentTemp!;
        hasChanges = true;
      }

      if (data.setTemp != null && device.setTemp != data.setTemp) {
        device.setTemp = data.setTemp!;
        hasChanges = true;
      }

      // deviceType에 따른 특정 데이터 업데이트
      if (deviceType == "TEMP" || deviceType == "ORP") {
        if (data.pwmValue != null && device.pwmValue != data.pwmValue) {
          device.pwmValue = data.pwmValue!;
          hasChanges = true;
        }
        if (data.coolerState != null && device.coolerState != data.coolerState) {
          device.coolerState = data.coolerState!;
          hasChanges = true;
        }
        if (data.hysteresisVal != null && device.hysteresis != data.hysteresisVal) {
          device.hysteresis = data.hysteresisVal!;
          hasChanges = true;
        }
        if (data.pwmMinValue != null && device.pwmMin != data.pwmMinValue) {
          device.pwmMin = data.pwmMinValue!;
          hasChanges = true;
        }
      }

      if (deviceType == "ORP") {
        if (data.orpRawVal != null && device.orpRaw != data.orpRawVal) {
          device.orpRaw = data.orpRawVal!;
          hasChanges = true;
        }
        if (data.orpCorrectedVal != null && device.orpCorrected != data.orpCorrectedVal) {
          device.orpCorrected = data.orpCorrectedVal!;
          hasChanges = true;
        }
      }

      if (deviceType == "CV") {
        if (data.streamUrl != null && device.streamUrl != data.streamUrl) {
          device.streamUrl = data.streamUrl;
          hasChanges = true;
        }
        if (data.streamStatus != null && device.streamStatus != data.streamStatus) {
          device.streamStatus = data.streamStatus;
          hasChanges = true;
        }
        if (data.detectedObjects != null && device.detectedObjects != data.detectedObjects) {
          device.detectedObjects = data.detectedObjects;
          hasChanges = true;
        }
        if (data.detectionData != null) {
          device.detectionData = data.detectionData;
          hasChanges = true;
        }
      }

      if (deviceType == "CHIL") {
        print('CHIL device ${device.customName}: received data.setTemp=${data.setTemp}, device.setTemp=${device.setTemp}');
        print('CHIL device ${device.customName}: received data.hysteresisVal=${data.hysteresisVal}, device.hysteresis=${device.hysteresis}');
        
        if (data.chillerState != null && device.chillerState != data.chillerState) {
          device.chillerState = data.chillerState!;
          hasChanges = true;
        }
        if (data.tempSource != null && device.tempSource != data.tempSource) {
          device.tempSource = data.tempSource;
          hasChanges = true;
        }
        if (data.wiringTopic != null && device.wiringTopic != data.wiringTopic) {
          device.wiringTopic = data.wiringTopic;
          hasChanges = true;
        }
        if (data.hysteresisVal != null && device.hysteresis != data.hysteresisVal) {
          print('CHIL device ${device.customName}: updating hysteresis from ${device.hysteresis} to ${data.hysteresisVal}');
          device.hysteresis = data.hysteresisVal!;
          hasChanges = true;
        }
        // CHIL devices also need setTemp parsing for settings screen initial values
        if (data.setTemp != null && device.setTemp != data.setTemp) {
          print('CHIL device ${device.customName}: updating setTemp from ${device.setTemp} to ${data.setTemp}');
          device.setTemp = data.setTemp!;
          hasChanges = true;
        }
      }

      // 데이터를 받았다는 것은 장치가 연결되어 있다는 뜻
      if (!device.isConnected) {
        device.isConnected = true;
        hasChanges = true;
      }

      // 변경사항이 있으면 UI 업데이트
      if (hasChanges) {
        notifyListeners();
      }

    } catch (e) {
      print('MQTT: 장치 ${device.customName} JSON 파싱 오류: $e');
    }
  }

  /**
   * GST 메시지 처리
   */
  void _handleGstMessage(String deviceId, String payload) {
    print('MQTT: CV 장치 $deviceId GST 메시지 수신: $payload');

    String streamUrl = payload;
    if (payload.startsWith("gst=")) {
      streamUrl = payload.substring(4);
    }

    // 등록된 장치 찾기
    final deviceIndex = _devices.indexWhere((d) => d.id == deviceId);
    if (deviceIndex == -1) {
      print('경고: GST 메시지를 받았지만 등록되지 않은 장치 ID: $deviceId');
      return;
    }

    final device = _devices[deviceIndex];
    
    if (device.deviceType != "CV") {
      print('경고: GST 메시지를 받았지만 CV 장치가 아님: ${device.deviceType}');
      return;
    }

    String gstUrl = 'gst=$streamUrl';
    
    if (device.streamUrl != gstUrl) {
      device.streamUrl = gstUrl;
      notifyListeners();
    }
  }

  /**
   * 장치 검색 시작
   * 새로운 ESP32 장치들이 보내는 하트비트를 감지함
   */
  Future<void> startDiscovery() async {
    if (_isDiscovering) {
      print('이미 장치 검색이 진행 중입니다.');
      return;
    }

    print('장치 검색 시작!');
    _isDiscovering = true;
  // 이전 검색 결과 초기화하되, 등록된 장치는 제외
  _discoveredDevicesDuringScan.clear();
    notifyListeners(); // UI 업데이트

    // MQTT 연결 확인
    await _connectMqtt();

    print('장치 검색 모드 활성화. 하트비트 대기 중...');
  }

  /**
   * 장치 검색 중지
   */
  void stopDiscovery() {
    if (!_isDiscovering) {
      print('장치 검색이 진행 중이 아닙니다.');
      return;
    }

    print('장치 검색 중지');
    _isDiscovering = false;
    notifyListeners(); // UI 업데이트
  }

  /**
   * 발견된 장치를 정식으로 등록
   *
   * @param deviceId 등록할 장치의 ID
   * @param deviceType 등록할 장치의 유형 (옵셔널, 검색 시 감지된 유형 사용 가능)
   */
  Future<void> registerDevice(String deviceId, {String? deviceType}) async {
    // 이미 등록된 장치인지 확인
    if (_devices.any((d) => d.id == deviceId)) {
      print('이미 등록된 장치입니다: $deviceId');
      // 필요하다면 여기서 장치 유형 업데이트 로직 추가 가능
      final existingDevice = _devices.firstWhere((d) => d.id == deviceId);
      if (deviceType != null && existingDevice.deviceType != deviceType) {
        print('기존 장치 $deviceId 의 유형을 $deviceType 으로 업데이트합니다.');
        existingDevice.deviceType = deviceType;
        existingDevice.mqttTopic = '$deviceId/$deviceType';
        await _saveDevices();
        notifyListeners();
      }
      return;
    }

    // 검색 중에 발견된 장치 정보에서 deviceType 가져오기
    String finalDeviceType = deviceType ??
        _discoveredDevicesDuringScan[deviceId] ?? // 검색에서 발견된 타입 사용
        "TEMP"; // 기본값

    print('새 장치 등록 중: $deviceId, 유형: $finalDeviceType');

    // 기본 이름 생성 (ID의 마지막 4자리 사용)
    String defaultName = '${finalDeviceType.toUpperCase()} ${deviceId.length > 4 ? deviceId.substring(deviceId.length - 4) : deviceId}';

    // 새 Device 객체 생성
    final newDevice = Device(
      id: deviceId,
      customName: defaultName,
      deviceType: finalDeviceType, // deviceType 명시
    );

    // 장치 목록에 추가
    _devices.add(newDevice);

    // 로컬 스토리지에 저장
    await _saveDevices();

    // 검색 목록에서 제거
    _discoveredDevicesDuringScan.remove(deviceId);

    notifyListeners(); // UI 업데이트

    print('장치 등록 완료: ${newDevice.customName} ($deviceId)');
    print('명령 전송 토픽: ${_getCommandTopic(newDevice)}');
  }  /**
      * 명령 토픽 생성 헬퍼 함수
      * Flutter → ESP32 명령 전송용
      *
      * @param deviceId 장치 ID
      * @return 명령 토픽 (deviceId/deviceType/com)
      */
  String _getCommandTopic(Device device) {
    // Device 객체에서 deviceType을 사용
    return '${device.id}/${device.deviceType}/com';  // com이 표준
  }

  /**
   * 장치 이름 변경
   *
   * @param deviceId 장치 ID
   * @param newName 새로운 이름
   */
  Future<void> renameDevice(String deviceId, String newName) async {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index == -1) {
      print('장치 $deviceId 를 찾을 수 없습니다.');
      return;
    }

    String oldName = _devices[index].customName;
    _devices[index].customName = newName;

    await _saveDevices(); // 변경사항 저장
    notifyListeners(); // UI 업데이트

    print('장치 이름 변경: $oldName → $newName (ID: $deviceId)');
  }

  /**
   * 등록된 장치 삭제
   *
   * @param deviceId 삭제할 장치 ID
   */
  Future<void> removeDevice(String deviceId) async {
    final deviceIndex = _devices.indexWhere((d) => d.id == deviceId);
    if (deviceIndex == -1) {
      print('삭제할 장치 $deviceId 를 찾을 수 없습니다.');
      return;
    }

    final deviceToRemove = _devices[deviceIndex];
    String deviceName = deviceToRemove.customName;

    // 장치 목록에서 제거
    _devices.removeAt(deviceIndex);

    // 변경사항 저장
    await _saveDevices();

    notifyListeners(); // UI 업데이트

    print('장치 삭제 완료: $deviceName ($deviceId)');
  }

  /**
   * MQTT 명령 발행 (Flutter → ESP32)
   *
   * @param deviceId 대상 장치 ID
   * @param message 전송할 메시지
   * @param retain 메시지 보관 여부
   */
  void _publishCommand(Device device, String message, {bool retain = false}) {
    if (_mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
      print('MQTT 클라이언트가 연결되지 않아 명령을 보낼 수 없습니다.');
      // 연결 재시도 로직 추가 가능
      _connectMqtt();
      return;
    }
    final topic = _getCommandTopic(device); // Device 객체를 전달하여 올바른 토픽 생성
    _doPublishCommand(topic, message, retain);
  }

  /**
   * 실제 MQTT 메시지 발행
   *
   * @param topic 토픽
   * @param message 메시지
   * @param retain 보관 여부
   */
  void _doPublishCommand(String topic, String message, bool retain) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    _mqttClient?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);

    print('MQTT 명령 전송: $topic ← $message');
  }

  // ===== 장치 간 배선 (와이어링) 기능 =====
  // 소스 장치(예: TEMP 컨트롤러)의 상태 토픽을 타겟 장치(예: COOLER)가 구독하도록 지시
  // 프로토콜: 타겟 장치의 /wir 토픽에 (plain text) 소스 장치의 <sourceId>/<sourceType>/sta 문자열을 3회 발행
  // 해제: /wir 토픽에 'none' 3회 발행

  String _getStatusTopicOf(Device d) => '${d.id}/${d.deviceType}/sta';
  String _getWiringTopicOf(Device d) => '${d.id}/${d.deviceType}/wir';

  /// 장치 배선 설정 (source -> target), 신뢰성 확보 위해 3회 발행
  void wireDevices({required Device source, required Device target}) {
    final statusTopicString = _getStatusTopicOf(source);
    final wiringTopic = _getWiringTopicOf(target);

    for (int i = 0; i < 3; i++) {
      _doPublishCommand(wiringTopic, statusTopicString, false);
    }

    _deviceWiringMap[target.id] = statusTopicString;
    _saveDeviceWiring();
    notifyListeners();
    print('배선 설정 (3회 발행): ${target.customName} (${target.id}) ← $statusTopicString');
  }

  /// 배선 해제: target 의 /wir 에 'none' 3회 발행
  void unwireDevice(Device target) {
    if (!_deviceWiringMap.containsKey(target.id)) return;
    final wiringTopic = _getWiringTopicOf(target);
    for (int i = 0; i < 3; i++) {
      _doPublishCommand(wiringTopic, 'none', false);
    }
    _deviceWiringMap.remove(target.id);
    _saveDeviceWiring();
    notifyListeners();
    print('배선 해제 (3회 발행): ${target.customName} (${target.id})');
  }

  /**
   * 공용 MQTT 메시지 전송 메서드
   * CV 설정 화면 등에서 직접 토픽과 메시지로 MQTT 명령을 전송할 때 사용
   *
   * @param topic 전송할 토픽
   * @param message 전송할 메시지
   * @param retain 메시지 보관 여부 (기본값: false)
   */
  void sendMqttMessage(String topic, String message, {bool retain = false}) {
    if (_mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
      print('MQTT 클라이언트가 연결되지 않아 메시지를 보낼 수 없습니다.');
      // 연결 재시도 로직
      _connectMqtt();
      return;
    }

    _doPublishCommand(topic, message, retain);
    print('공용 MQTT 메시지 전송: $topic ← $message');
  }

  /**
   * 장치 설정 온도 변경
   *
   * @param device 대상 장치
   * @param newSetTemp 새로운 설정 온도
   */
  void updateDeviceSetTemp(Device device, double newSetTemp) {
    if (device.setTemp == newSetTemp) return;
    device.setTemp = newSetTemp;
    notifyListeners();
    final command = {'settemp': newSetTemp};
    _publishCommand(device, jsonEncode(command));
    print('장치 ${device.customName} 설정 온도 변경: $newSetTemp');
  }

  /**
   * 장치의 히스테리시스 값 업데이트 및 MQTT로 전송
   *
   * @param device 대상 장치
   * @param newHysteresis 새로운 히스테리시스 값
   */
  void updateDeviceHysteresis(Device device, double newHysteresis) {
    if (device.hysteresis == newHysteresis) return;
    device.hysteresis = newHysteresis;
    notifyListeners();
    final command = {'hysteresis': newHysteresis};
    _publishCommand(device, jsonEncode(command));
    print('장치 ${device.customName} 히스테리시스 변경: $newHysteresis');
  }

  /**
   * 장치의 PWM 최소값 업데이트 및 MQTT로 전송
   *
   * @param device 대상 장치
   * @param newPwmMin 새로운 PWM 최소값
   */
  void updateDevicePwmMin(Device device, int newPwmMin) {
    if (device.pwmMin == newPwmMin) return;
    device.pwmMin = newPwmMin;
    notifyListeners();
    final command = {'pwm_min': newPwmMin};
    _publishCommand(device, jsonEncode(command));
    print('장치 ${device.customName} PWM 최소값 변경: $newPwmMin');
  }

  /**
   * 장치 설정 저장 명령
   * ESP32에게 현재 설정을 EEPROM 등에 저장하라고 지시
   *
   * @param device 대상 장치
   */
  void saveSettingsOnDevice(Device device) {
    _publishCommand(device, "save");
    print('장치 ${device.customName}에 설정 저장 명령 전송');
  }

  /**
   * 장치 WiFi 재설정 명령 전송
   *
   * @param device 대상 장치
   */
  void resetWifiOnDevice(Device device) {
    _publishCommand(device, "reset_wifi");
    print('장치 ${device.customName}에 WiFi 재설정 명령 전송');
  }

  // ===== CV (Computer Vision) 장치 전용 명령 메서드들 =====

  /**
   * CV 장치 스트리밍 시작 명령
   *
   * @param device CV 장치
   */
  void startCvStreaming(Device device) {
    if (device.deviceType != "CV") {
      print('경고: CV 장치가 아닌 장치에 스트리밍 명령을 보내려고 합니다.');
      return;
    }

    final command = {'action': 'start_stream'};
    _publishCommand(device, jsonEncode(command));
    print('CV 장치 ${device.customName}에 스트리밍 시작 명령 전송');
  }

  /**
   * CV 장치 스트리밍 중지 명령
   *
   * @param device CV 장치
   */
  void stopCvStreaming(Device device) {
    if (device.deviceType != "CV") {
      print('경고: CV 장치가 아닌 장치에 스트리밍 명령을 보내려고 합니다.');
      return;
    }

    final command = {'action': 'stop_stream'};
    _publishCommand(device, jsonEncode(command));
    print('CV 장치 ${device.customName}에 스트리밍 중지 명령 전송');
  }

  /**
   * CV 장치 카메라 이동 명령
   *
   * @param device CV 장치
   * @param direction 이동 방향 ("up", "down", "left", "right", "stop")
   */
  void moveCvCamera(Device device, String direction) {
    if (device.deviceType != "CV") {
      print('경고: CV 장치가 아닌 장치에 카메라 이동 명령을 보내려고 합니다.');
      return;
    }

    final validDirections = ["up", "down", "left", "right", "stop"];
    if (!validDirections.contains(direction)) {
      print('경고: 유효하지 않은 카메라 이동 방향: $direction');
      return;
    }

    final command = {'move': direction};
    _publishCommand(device, jsonEncode(command));
    print('CV 장치 ${device.customName}에 카메라 이동 명령 전송: $direction');
  }

  /**
   * CV 장치 객체 감지 활성화/비활성화
   *
   * @param device CV 장치
   * @param enabled 감지 활성화 여부
   */
  void setCvDetectionEnabled(Device device, bool enabled) {
    if (device.deviceType != "CV") {
      print('경고: CV 장치가 아닌 장치에 객체 감지 명령을 보내려고 합니다.');
      return;
    }

    final command = {'detection_enabled': enabled};
    _publishCommand(device, jsonEncode(command));
    print('CV 장치 ${device.customName}에 객체 감지 ${enabled ? "활성화" : "비활성화"} 명령 전송');
  }

  /**
   * CV 장치 감지 신뢰도 임계값 설정
   *
   * @param device CV 장치
   * @param threshold 신뢰도 임계값 (0.0 ~ 1.0)
   */
  void setCvDetectionThreshold(Device device, double threshold) {
    if (device.deviceType != "CV") {
      print('경고: CV 장치가 아닌 장치에 감지 임계값 명령을 보내려고 합니다.');
      return;
    }

    if (threshold < 0.0 || threshold > 1.0) {
      print('경고: 감지 임계값은 0.0 ~ 1.0 사이여야 합니다: $threshold');
      return;
    }

    final command = {'detection_threshold': threshold};
    _publishCommand(device, jsonEncode(command));
    print('CV 장치 ${device.customName}에 감지 임계값 설정: $threshold');
  }

  /**
   * CV 장치 스트림 품질 설정
   *
   * @param device CV 장치
   * @param quality 품질 설정 ("low", "medium", "high")
   */
  void setCvStreamQuality(Device device, String quality) {
    if (device.deviceType != "CV") {
      print('경고: CV 장치가 아닌 장치에 스트림 품질 명령을 보내려고 합니다.');
      return;
    }

    final validQualities = ["low", "medium", "high"];
    if (!validQualities.contains(quality)) {
      print('경고: 유효하지 않은 스트림 품질: $quality');
      return;
    }

    final command = {'stream_quality': quality};
    _publishCommand(device, jsonEncode(command));
    print('CV 장치 ${device.customName}에 스트림 품질 설정: $quality');
  }

  /**
   * CV 장치 상태 요청
   *
   * @param device CV 장치
   */
  void requestCvStatus(Device device) {
    if (device.deviceType != "CV") {
      print('경고: CV 장치가 아닌 장치에 상태 요청 명령을 보내려고 합니다.');
      return;
    }

    final command = {'action': 'get_status'};
    _publishCommand(device, jsonEncode(command));
    print('CV 장치 ${device.customName}에 상태 요청 명령 전송');
  }

  /**
   * CV 장치 재시작 명령
   *
   * @param device CV 장치
   */
  void restartCvDevice(Device device) {
    if (device.deviceType != "CV") {
      print('경고: CV 장치가 아닌 장치에 재시작 명령을 보내려고 합니다.');
      return;
    }

    final command = {'action': 'restart'};
    _publishCommand(device, jsonEncode(command));
    print('CV 장치 ${device.customName}에 재시작 명령 전송');
  }

  /**
   * CHIL 장치에 일반 명령 전송
   *
   * @param deviceId 장치 ID
   * @param deviceType 장치 타입
   * @param messageType 메시지 타입 (con, wir 등)
   * @param message 전송할 메시지 (Map 또는 String)
   */
  Future<void> publishToDevice(String deviceId, String deviceType, String messageType, dynamic message) async {
    if (_mqttClient?.connectionStatus?.state != MqttConnectionState.connected) {
      print('MQTT 클라이언트가 연결되지 않아 명령을 보낼 수 없습니다.');
      _connectMqtt();
      return;
    }

    final topic = '$deviceId/$deviceType/$messageType';
    String messageString;
    
    if (message is Map) {
      messageString = jsonEncode(message);
    } else {
      messageString = message.toString();
    }

    _doPublishCommand(topic, messageString, false);
    print('CHIL 장치 $deviceId에 명령 전송: $topic ← $messageString');
  }

  // ===== 기존 코드 =====

  /**
   * 온도 데이터 로깅 시작
   * 5분마다 연결된 모든 장치의 온도 데이터를 데이터베이스에 저장
   */
  void _startDataLogging() {
    print('온도 데이터 로깅 시작 - 10분 간격');
    // 기존 타이머가 있다면 취소
    _dataLoggingTimer?.cancel();
    // 1시간마다 연결된 모든 장치의 온도 데이터 로깅
    _dataLoggingTimer = Timer.periodic(const Duration(hours: 1), (timer) async {
      await _logTemperatureData();
    });

    // 6시간마다 24시간 이상된 오래된 데이터 정리
    Timer.periodic(const Duration(hours: 6), (timer) async {
      await _temperatureHistoryService.cleanOldData();
    });
  }
  /**
   * 현재 연결된 모든 장치의 온도/ORP 데이터를 로깅
   */
  Future<void> _logTemperatureData() async {
    for (final device in _devices) {
      // 연결된 장치이고 온도 데이터가 있는 경우만 로깅
      if (device.isConnected && device.currentTemp != null) {
        try {
          final record = TemperatureRecord(
            deviceId: device.id,
            deviceName: device.customName,
            deviceType: device.deviceType,
            currentTemp: device.currentTemp!,
            setTemp: device.setTemp ?? 20.0,
            orpRaw: device.orpRaw,
            orpCorrected: device.orpCorrected,
            coolerState: device.coolerState ?? false,
            timestamp: DateTime.now(),
          );

          await _temperatureHistoryService.saveTemperatureRecord(record);
        } catch (e) {
          print('장치 ${device.customName} 데이터 저장 오류: $e');
        }
      }
    }
  }

  /**
   * 특정 장치의 온도 히스토리 데이터 가져오기 (외부에서 호출용)
   */
  Future<List<TemperatureRecord>> getDeviceTemperatureHistory(String deviceId) async {
    return await _temperatureHistoryService.getTodayTemperatureData(deviceId);
  }

  /**
   * 장치 삭제 시 해당 장치의 온도 히스토리도 함께 삭제
   */
  Future<void> _deleteDeviceTemperatureHistory(String deviceId) async {
    await _temperatureHistoryService.deleteDeviceData(deviceId);
  }

  /**
   * DeviceProvider 해제 시 정리 작업
   */
  @override
  void dispose() {
    print("DeviceProvider 종료 중...");

    // 앱 라이프사이클 관찰자 제거
    WidgetsBinding.instance.removeObserver(this);

    // 재연결 타이머 정리
    _reconnectTimer?.cancel();

    // WakeLock 비활성화
    WakelockPlus.disable();
    print("WakeLock 비활성화 완료");

    // MQTT 연결 해제
    if (_mqttClient != null) {
      print("MQTT 클라이언트 연결 해제");
      _mqttClient!.disconnect();
    }

    // 온도 데이터 로깅 타이머 정리
    _dataLoggingTimer?.cancel();

    super.dispose();
    print("DeviceProvider 종료 완료");
  }

  /**
   * 백그라운드 MQTT 수신을 위한 권한 요청
   */
  Future<void> _requestBackgroundPermissions() async {
    try {
      print('백그라운드 권한 요청 시작');

      // 1. 네트워크 및 배터리 최적화 권한 요청
      Map<Permission, PermissionStatus> permissions = await [
        Permission.ignoreBatteryOptimizations,
        Permission.systemAlertWindow,
        Permission.notification,
      ].request();

      // 2. WakeLock 활성화 (앱이 백그라운드에서도 MQTT 연결 유지)
      await WakelockPlus.enable();
      print('WakeLock 활성화 완료 - 백그라운드 연결 유지 가능');

      // 권한 상태 로깅
      permissions.forEach((permission, status) {
        print('권한 $permission: $status');
      });

    } catch (e) {
      print('백그라운드 권한 요청 중 오류: $e');
    }
  }
}

/**
 * DeviceData 클래스
 * ESP32에서 보내는 JSON 데이터를 파싱하기 위한 클래스
 *
 * ESP32 JSON 형태 예시:
 * {
 *   "temp": 25.6,
 *   "set_temp": 20.0,
 *   "pwm_value": 128,
 *   "cooler_state": true,
 *   "hysteresis": 1.0,
 *   "pwm_min": 50
 * }
 */

/// 도징 펌프 상태/스케줄 보관용 모델
class DosingPumpInfo {
  bool pump1On;
  bool pump2On;
  bool online;
  DateTime? lastHeartbeat;
  Map<String, dynamic> schedules; // pump 번호 -> List<List<dynamic>> (hour, minute, durationMs, intervalDays)
  String? lastLog;
  String pump1Name; // 펌프 1 이름
  String pump2Name; // 펌프 2 이름

  DosingPumpInfo({
    this.pump1On = false,
    this.pump2On = false,
    this.online = false,
    this.lastHeartbeat,
    Map<String, dynamic>? schedules,
    this.lastLog,
    this.pump1Name = '펌프 1',
    this.pump2Name = '펌프 2',
  }) : schedules = schedules ?? {};
}

/// Water level device info
class WaterLevelInfo {
  double? distanceCm;
  bool online;
  DateTime? lastUpdate;

  // offset applied to raw distance (cm)
  double? offsetCm;

  // recent history of adjusted distance values
  final List<WaterLevelRecord> history = [];

  WaterLevelInfo({this.distanceCm, this.online = false, this.lastUpdate, this.offsetCm});
}

/// Single history record for water level
class WaterLevelRecord {
  final DateTime time;
  final double valueCm; // adjusted value after offset
  WaterLevelRecord(this.time, this.valueCm);
}