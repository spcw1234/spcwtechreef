import 'package:json_annotation/json_annotation.dart';

part 'tank.g.dart';

/**
 * Tank 클래스
 * 수조 정보를 담는 모델 클래스
 */
@JsonSerializable()
class Tank {
  String id;                    // 수조 고유 ID
  String name;                  // 수조 이름
  String description;           // 수조 설명
  List<String> deviceIds;       // 이 수조에 속한 장치 ID 목록
  DateTime createdAt;           // 생성일시
  DateTime updatedAt;           // 수정일시

  Tank({
    required this.id,
    required this.name,
    this.description = '',
    List<String>? deviceIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : 
    deviceIds = deviceIds ?? [],
    createdAt = createdAt ?? DateTime.now(),
    updatedAt = updatedAt ?? DateTime.now();

  /// JSON 직렬화
  factory Tank.fromJson(Map<String, dynamic> json) => _$TankFromJson(json);
  Map<String, dynamic> toJson() => _$TankToJson(this);

  /// 수조에 장치 추가
  void addDevice(String deviceId) {
    if (!deviceIds.contains(deviceId)) {
      deviceIds.add(deviceId);
      updatedAt = DateTime.now();
    }
  }

  /// 수조에서 장치 제거
  void removeDevice(String deviceId) {
    if (deviceIds.contains(deviceId)) {
      deviceIds.remove(deviceId);
      updatedAt = DateTime.now();
    }
  }

  /// 수조 정보 업데이트
  void updateInfo({String? name, String? description}) {
    if (name != null) this.name = name;
    if (description != null) this.description = description;
    updatedAt = DateTime.now();
  }

  /// 수조의 장치 개수
  int get deviceCount => deviceIds.length;

  /// 복사본 생성
  Tank copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? deviceIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Tank(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      deviceIds: deviceIds ?? List<String>.from(this.deviceIds),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
