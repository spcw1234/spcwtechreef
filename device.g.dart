// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Device _$DeviceFromJson(Map<String, dynamic> json) => Device(
  id: json['id'] as String,
  customName: json['customName'] as String,
  deviceType: json['deviceType'] as String,
  currentTemp: (json['currentTemp'] as num?)?.toDouble(),
  setTemp: (json['setTemp'] as num?)?.toDouble(),
  pwmValue: (json['pwmValue'] as num?)?.toInt(),
  coolerState: json['coolerState'] as bool?,
  hysteresis: (json['hysteresis'] as num?)?.toDouble(),
  pwmMin: (json['pwmMin'] as num?)?.toInt(),
  chillerState: json['chillerState'] as bool?,
  tempSource: json['tempSource'] as String?,
  wiringTopic: json['wiringTopic'] as String?,
  orpRaw: (json['orpRaw'] as num?)?.toDouble(),
  orpCorrected: (json['orpCorrected'] as num?)?.toDouble(),
  streamUrl: json['streamUrl'] as String?,
  streamStatus: json['streamStatus'] as String?,
  detectedObjects: (json['detectedObjects'] as num?)?.toInt(),
  detectionData: (json['detectionData'] as List<dynamic>?)
      ?.map((e) => e as Map<String, dynamic>)
      .toList(),
  isConnected: json['isConnected'] as bool? ?? false,
)..mqttTopic = json['mqttTopic'] as String;

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'id': instance.id,
  'customName': instance.customName,
  'deviceType': instance.deviceType,
  'mqttTopic': instance.mqttTopic,
  'currentTemp': instance.currentTemp,
  'setTemp': instance.setTemp,
  'pwmValue': instance.pwmValue,
  'coolerState': instance.coolerState,
  'hysteresis': instance.hysteresis,
  'pwmMin': instance.pwmMin,
  'chillerState': instance.chillerState,
  'tempSource': instance.tempSource,
  'wiringTopic': instance.wiringTopic,
  'orpRaw': instance.orpRaw,
  'orpCorrected': instance.orpCorrected,
  'streamUrl': instance.streamUrl,
  'streamStatus': instance.streamStatus,
  'detectedObjects': instance.detectedObjects,
  'detectionData': instance.detectionData,
  'isConnected': instance.isConnected,
};

DeviceData _$DeviceDataFromJson(Map<String, dynamic> json) => DeviceData(
  currentTemp: (json['temp'] as num?)?.toDouble(),
  setTemp: (json['setTemp'] as num?)?.toDouble(),
  pwmValue: (json['pwm_value'] as num?)?.toInt(),
  coolerState: json['cooler_state'] as bool?,
  hysteresisVal: (json['hysteresis'] as num?)?.toDouble(),
  pwmMinValue: (json['pwm_min'] as num?)?.toInt(),
  chillerState: json['chiller_state'] as bool?,
  tempSource: json['temp_source'] as String?,
  wiringTopic: json['wiring_topic'] as String?,
  orpRawVal: (json['orp_raw'] as num?)?.toDouble(),
  orpCorrectedVal: (json['orp_corrected'] as num?)?.toDouble(),
  streamUrl: json['stream_url'] as String?,
  streamStatus: json['stream_status'] as String?,
  detectedObjects: (json['detected_objects'] as num?)?.toInt(),
  detectionData: (json['detection_data'] as List<dynamic>?)
      ?.map((e) => e as Map<String, dynamic>)
      .toList(),
);

Map<String, dynamic> _$DeviceDataToJson(DeviceData instance) =>
    <String, dynamic>{
      'temp': instance.currentTemp,
      'setTemp': instance.setTemp,
      'pwm_value': instance.pwmValue,
      'cooler_state': instance.coolerState,
      'hysteresis': instance.hysteresisVal,
      'pwm_min': instance.pwmMinValue,
      'chiller_state': instance.chillerState,
      'temp_source': instance.tempSource,
      'wiring_topic': instance.wiringTopic,
      'orp_raw': instance.orpRawVal,
      'orp_corrected': instance.orpCorrectedVal,
      'stream_url': instance.streamUrl,
      'stream_status': instance.streamStatus,
      'detected_objects': instance.detectedObjects,
      'detection_data': instance.detectionData,
    };
