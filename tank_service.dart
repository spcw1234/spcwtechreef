import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'tank.dart';

/**
 * TankService 클래스
 * 수조 데이터의 로컬 저장 및 관리
 */
class TankService {
  static const String _tanksKey = 'tanks';
  
  /// 모든 수조 목록 로드
  Future<List<Tank>> loadTanks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tanksJson = prefs.getString(_tanksKey);
      
      if (tanksJson == null || tanksJson.isEmpty) {
        print('TankService: 저장된 수조 데이터가 없습니다.');
        return [];
      }
      
      final List<dynamic> tanksList = jsonDecode(tanksJson);
      final tanks = tanksList.map((json) => Tank.fromJson(json)).toList();
      
      print('TankService: ${tanks.length}개 수조 로드 완료');
      return tanks;
    } catch (e) {
      print('TankService: 수조 로드 중 오류 발생 - $e');
      return [];
    }
  }
  
  /// 수조 목록 저장
  Future<void> saveTanks(List<Tank> tanks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tanksJson = jsonEncode(tanks.map((tank) => tank.toJson()).toList());
      await prefs.setString(_tanksKey, tanksJson);
      print('TankService: ${tanks.length}개 수조 저장 완료');
    } catch (e) {
      print('TankService: 수조 저장 중 오류 발생 - $e');
      throw e;
    }
  }
  
  /// 특정 수조 로드
  Future<Tank?> loadTank(String tankId) async {
    final tanks = await loadTanks();
    try {
      return tanks.firstWhere((tank) => tank.id == tankId);
    } catch (e) {
      print('TankService: 수조 ID $tankId를 찾을 수 없습니다.');
      return null;
    }
  }
  
  /// 수조 추가
  Future<void> addTank(Tank tank) async {
    final tanks = await loadTanks();
    
    // 중복 ID 체크
    if (tanks.any((t) => t.id == tank.id)) {
      throw Exception('이미 존재하는 수조 ID입니다: ${tank.id}');
    }
    
    tanks.add(tank);
    await saveTanks(tanks);
    print('TankService: 수조 "${tank.name}" 추가 완료');
  }
  
  /// 수조 업데이트
  Future<void> updateTank(Tank updatedTank) async {
    final tanks = await loadTanks();
    final index = tanks.indexWhere((tank) => tank.id == updatedTank.id);
    
    if (index == -1) {
      throw Exception('수조 ID ${updatedTank.id}를 찾을 수 없습니다.');
    }
    
    tanks[index] = updatedTank;
    await saveTanks(tanks);
    print('TankService: 수조 "${updatedTank.name}" 업데이트 완료');
  }
  
  /// 수조 삭제
  Future<void> deleteTank(String tankId) async {
    final tanks = await loadTanks();
    final index = tanks.indexWhere((tank) => tank.id == tankId);
    
    if (index == -1) {
      throw Exception('수조 ID $tankId를 찾을 수 없습니다.');
    }
    
    final deletedTank = tanks.removeAt(index);
    await saveTanks(tanks);
    print('TankService: 수조 "${deletedTank.name}" 삭제 완료');
  }
  
  /// 수조에 장치 추가
  Future<void> addDeviceToTank(String tankId, String deviceId) async {
    final tanks = await loadTanks();
    final tank = tanks.firstWhere((t) => t.id == tankId);
    
    // 다른 수조에서 해당 장치 제거 (한 장치는 하나의 수조에만 속할 수 있음)
    for (final otherTank in tanks) {
      if (otherTank.id != tankId) {
        otherTank.removeDevice(deviceId);
      }
    }
    
    tank.addDevice(deviceId);
    await saveTanks(tanks);
    print('TankService: 수조 "${tank.name}"에 장치 $deviceId 추가 완료');
  }
  
  /// 수조에서 장치 제거
  Future<void> removeDeviceFromTank(String tankId, String deviceId) async {
    final tanks = await loadTanks();
    final tank = tanks.firstWhere((t) => t.id == tankId);
    
    tank.removeDevice(deviceId);
    await saveTanks(tanks);
    print('TankService: 수조 "${tank.name}"에서 장치 $deviceId 제거 완료');
  }
  
  /// 특정 장치가 속한 수조 찾기
  Future<Tank?> findTankByDevice(String deviceId) async {
    final tanks = await loadTanks();
    try {
      return tanks.firstWhere((tank) => tank.deviceIds.contains(deviceId));
    } catch (e) {
      return null; // 어떤 수조에도 속하지 않음
    }
  }
  
  /// 수조에 속하지 않은 장치 ID 목록 가져오기
  Future<List<String>> getUnassignedDevices(List<String> allDeviceIds) async {
    final tanks = await loadTanks();
    final assignedDeviceIds = <String>{};
    
    for (final tank in tanks) {
      assignedDeviceIds.addAll(tank.deviceIds);
    }
    
    return allDeviceIds.where((deviceId) => !assignedDeviceIds.contains(deviceId)).toList();
  }
}
