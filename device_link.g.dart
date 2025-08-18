// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_link.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceLink _$DeviceLinkFromJson(Map<String, dynamic> json) => DeviceLink(
  id: json['id'] as String,
  sourceDeviceId: json['sourceDeviceId'] as String,
  sourceDeviceName: json['sourceDeviceName'] as String,
  sourceDeviceType: json['sourceDeviceType'] as String,
  sourceTankName: json['sourceTankName'] as String,
  targetDeviceIds: (json['targetDeviceIds'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  targetDeviceNames: (json['targetDeviceNames'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  targetTankNames: (json['targetTankNames'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  isActive: json['isActive'] as bool? ?? true,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$DeviceLinkToJson(DeviceLink instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sourceDeviceId': instance.sourceDeviceId,
      'sourceDeviceName': instance.sourceDeviceName,
      'sourceDeviceType': instance.sourceDeviceType,
      'sourceTankName': instance.sourceTankName,
      'targetDeviceIds': instance.targetDeviceIds,
      'targetDeviceNames': instance.targetDeviceNames,
      'targetTankNames': instance.targetTankNames,
      'isActive': instance.isActive,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
