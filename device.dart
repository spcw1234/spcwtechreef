import 'package:json_annotation/json_annotation.dart';

part 'device.g.dart';

@JsonSerializable()
class Device {
  final String id;
  String customName;
  String deviceType;
  String mqttTopic;
  
  // Common fields
  double? currentTemp;
  double? setTemp;
  int? pwmValue;
  bool? coolerState;
  double? hysteresis;
  int? pwmMin;
  
  // CHIL specific fields
  bool? chillerState;
  String? tempSource;
  String? wiringTopic;
  
  // ORP specific fields
  double? orpRaw;
  double? orpCorrected;
  
  // CV specific fields
  String? streamUrl;
  String? streamStatus;
  int? detectedObjects;
  List<Map<String, dynamic>>? detectionData;
  
  // Connection status
  bool isConnected;

  Device({
    required this.id,
    required this.customName,
    required this.deviceType,
    this.currentTemp,
    this.setTemp,
    this.pwmValue,
    this.coolerState,
    this.hysteresis,
    this.pwmMin,
    this.chillerState,
    this.tempSource,
    this.wiringTopic,
    this.orpRaw,
    this.orpCorrected,
    this.streamUrl,
    this.streamStatus,
    this.detectedObjects,
    this.detectionData,
    this.isConnected = false,
  }) : mqttTopic = '$id/$deviceType';

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceToJson(this);
}

// ESP32 Data Payload Model (for parsing incoming MQTT messages)
@JsonSerializable()
class DeviceData {
  @JsonKey(name: 'temp')
  double? currentTemp;

  @JsonKey(name: 'setTemp')  // ESP32 sends 'setTemp', not 'settemp'
  double? setTemp;

  @JsonKey(name: 'pwm_value')
  int? pwmValue;

  @JsonKey(name: 'cooler_state')
  bool? coolerState;

  @JsonKey(name: 'hysteresis')
  double? hysteresisVal;

  @JsonKey(name: 'pwm_min')
  int? pwmMinValue;

  // CHIL specific fields
  @JsonKey(name: 'chiller_state')
  bool? chillerState;

  @JsonKey(name: 'temp_source')
  String? tempSource;

  @JsonKey(name: 'wiring_topic')
  String? wiringTopic;

  @JsonKey(name: 'orp_raw')
  double? orpRawVal;

  @JsonKey(name: 'orp_corrected')
  double? orpCorrectedVal;

  @JsonKey(name: 'stream_url')
  String? streamUrl;

  @JsonKey(name: 'stream_status')
  String? streamStatus;

  @JsonKey(name: 'detected_objects')
  int? detectedObjects;

  @JsonKey(name: 'detection_data')
  List<Map<String, dynamic>>? detectionData;

  DeviceData({
    this.currentTemp,
    this.setTemp,
    this.pwmValue,
    this.coolerState,
    this.hysteresisVal,
    this.pwmMinValue,
    this.chillerState,
    this.tempSource,
    this.wiringTopic,
    this.orpRawVal,
    this.orpCorrectedVal,
    this.streamUrl,
    this.streamStatus,
    this.detectedObjects,
    this.detectionData,
  });

  factory DeviceData.fromJson(Map<String, dynamic> json) => _$DeviceDataFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceDataToJson(this);
}