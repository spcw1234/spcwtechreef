import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'device.dart';

class LocalStorageService {
  static const String _devicesKey = 'registered_devices';
  static const String _deviceWiringKey = 'device_wiring_map'; // targetDeviceId -> sourceTopic

  Future<void> saveDevices(List<Device> devices) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> devicesJson = devices.map((device) => jsonEncode(device.toJson())).toList();
    await prefs.setStringList(_devicesKey, devicesJson);
  }

  Future<List<Device>> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    List<String>? devicesJson = prefs.getStringList(_devicesKey);
    if (devicesJson == null) {
      return [];
    }
    return devicesJson.map((jsonString) => Device.fromJson(jsonDecode(jsonString))).toList();
  }

  // ===== Device Wiring Map (targetDeviceId -> sourceTopic) 저장/로드 =====
  Future<void> saveDeviceWiring(Map<String, String> wiringMap) async {
    final prefs = await SharedPreferences.getInstance();
    // Map 을 JSON 문자열로 직렬화
    await prefs.setString(_deviceWiringKey, jsonEncode(wiringMap));
  }

  Future<Map<String, String>> loadDeviceWiring() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_deviceWiringKey);
    if (jsonString == null || jsonString.isEmpty) return {};
    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonString);
      // dynamic -> String 변환
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      // 파싱 실패 시 빈 맵 반환
      return {};
    }
  }
}