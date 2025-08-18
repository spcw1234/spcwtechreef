// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tank.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Tank _$TankFromJson(Map<String, dynamic> json) => Tank(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String? ?? '',
  deviceIds: (json['deviceIds'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$TankToJson(Tank instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'deviceIds': instance.deviceIds,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};
