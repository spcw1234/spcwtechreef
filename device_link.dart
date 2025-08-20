import 'package:json_annotation/json_annotation.dart';

part 'device_link.g.dart';

/**
 * DeviceLink 클래스
 * 장비 간 연결 정보를 담는 모델 클래스
 */
@JsonSerializable()
class DeviceLink {
  final String id;                    // 연결 고유 ID
  final String sourceDeviceId;        // 소스 장비 ID
  final String sourceDeviceName;      // 소스 장비 이름
  final String sourceDeviceType;      // 소스 장비 타입
  final String sourceTankName;        // 소스 장비 수조명
  final List<String> targetDeviceIds; // 대상 장비 ID 목록
  final List<String> targetDeviceNames; // 대상 장비 이름 목록
  final List<String> targetTankNames; // 대상 장비 수조명 목록
  bool isActive;                      // 연결 활성 상태
  final DateTime createdAt;           // 생성 시간
  DateTime updatedAt;                 // 수정 시간

  DeviceLink({
    required this.id,
    required this.sourceDeviceId,
    required this.sourceDeviceName,
    required this.sourceDeviceType,
    required this.sourceTankName,
    required this.targetDeviceIds,
    required this.targetDeviceNames,
    required this.targetTankNames,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// JSON 직렬화
  factory DeviceLink.fromJson(Map<String, dynamic> json) => _$DeviceLinkFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceLinkToJson(this);

  /// 복사본 생성
  DeviceLink copyWith({
    String? id,
    String? sourceDeviceId,
    String? sourceDeviceName,
    String? sourceDeviceType,
    String? sourceTankName,
    List<String>? targetDeviceIds,
    List<String>? targetDeviceNames,
    List<String>? targetTankNames,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DeviceLink(
      id: id ?? this.id,
      sourceDeviceId: sourceDeviceId ?? this.sourceDeviceId,
      sourceDeviceName: sourceDeviceName ?? this.sourceDeviceName,
      sourceDeviceType: sourceDeviceType ?? this.sourceDeviceType,
      sourceTankName: sourceTankName ?? this.sourceTankName,
      targetDeviceIds: targetDeviceIds ?? List<String>.from(this.targetDeviceIds),
      targetDeviceNames: targetDeviceNames ?? List<String>.from(this.targetDeviceNames),
      targetTankNames: targetTankNames ?? List<String>.from(this.targetTankNames),
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}