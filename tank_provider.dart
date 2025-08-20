import 'package:flutter/foundation.dart';
import 'tank.dart';
import 'tank_service.dart';
import 'device.dart';

/**
 * TankProvider 클래스
 * 수조 관리를 위한 상태 관리 Provider
 */
class TankProvider with ChangeNotifier {
  final TankService _tankService = TankService();
  
  List<Tank> _tanks = [];
  bool _isLoading = false;
  String? _error;
  
  // Getter들
  List<Tank> get tanks => _tanks;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  /// Provider 초기화
  TankProvider() {
    _loadTanks();
  }
  
  /// 수조 목록 로드
  Future<void> _loadTanks() async {
    _setLoading(true);
    _setError(null);
    
    try {
      _tanks = await _tankService.loadTanks();
      print('TankProvider: ${_tanks.length}개 수조 로드 완료');
    } catch (e) {
      _setError('수조 목록을 불러오는데 실패했습니다: $e');
      print('TankProvider: 수조 로드 실패 - $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// 새 수조 생성
  Future<bool> createTank({
    required String name,
    String description = '',
  }) async {
    _setError(null);
    
    try {
      // 고유 ID 생성 (현재 시간 기반)
      final id = 'tank_${DateTime.now().millisecondsSinceEpoch}';
      
      final newTank = Tank(
        id: id,
        name: name,
        description: description,
      );
      
      await _tankService.addTank(newTank);
      _tanks.add(newTank);
      
      notifyListeners();
      print('TankProvider: 새 수조 "$name" 생성 완료');
      return true;
    } catch (e) {
      _setError('수조 생성에 실패했습니다: $e');
      print('TankProvider: 수조 생성 실패 - $e');
      return false;
    }
  }
  
  /// 수조 정보 업데이트
  Future<bool> updateTank(String tankId, {String? name, String? description}) async {
    _setError(null);
    
    try {
      final tankIndex = _tanks.indexWhere((tank) => tank.id == tankId);
      if (tankIndex == -1) {
        throw Exception('수조를 찾을 수 없습니다.');
      }
      
      final updatedTank = _tanks[tankIndex].copyWith(
        name: name,
        description: description,
        updatedAt: DateTime.now(),
      );
      
      await _tankService.updateTank(updatedTank);
      _tanks[tankIndex] = updatedTank;
      
      notifyListeners();
      print('TankProvider: 수조 "$name" 업데이트 완료');
      return true;
    } catch (e) {
      _setError('수조 업데이트에 실패했습니다: $e');
      print('TankProvider: 수조 업데이트 실패 - $e');
      return false;
    }
  }
  
  /// 수조 삭제
  Future<bool> deleteTank(String tankId) async {
    _setError(null);
    
    try {
      await _tankService.deleteTank(tankId);
      _tanks.removeWhere((tank) => tank.id == tankId);
      
      notifyListeners();
      print('TankProvider: 수조 삭제 완료');
      return true;
    } catch (e) {
      _setError('수조 삭제에 실패했습니다: $e');
      print('TankProvider: 수조 삭제 실패 - $e');
      return false;
    }
  }
  
  /// 수조에 장치 추가
  Future<bool> addDeviceToTank(String tankId, String deviceId) async {
    _setError(null);
    
    try {
      await _tankService.addDeviceToTank(tankId, deviceId);
      
      // 로컬 상태 업데이트
      final tankIndex = _tanks.indexWhere((tank) => tank.id == tankId);
      if (tankIndex != -1) {
        // 다른 수조에서 해당 장치 제거
        for (int i = 0; i < _tanks.length; i++) {
          if (i != tankIndex) {
            _tanks[i].removeDevice(deviceId);
          }
        }
        
        // 현재 수조에 장치 추가
        _tanks[tankIndex].addDevice(deviceId);
      }
      
      notifyListeners();
      print('TankProvider: 수조에 장치 추가 완료');
      return true;
    } catch (e) {
      _setError('장치를 수조에 추가하는데 실패했습니다: $e');
      print('TankProvider: 장치 추가 실패 - $e');
      return false;
    }
  }
  
  /// 수조에서 장치 제거
  Future<bool> removeDeviceFromTank(String tankId, String deviceId) async {
    _setError(null);
    
    try {
      await _tankService.removeDeviceFromTank(tankId, deviceId);
      
      // 로컬 상태 업데이트
      final tankIndex = _tanks.indexWhere((tank) => tank.id == tankId);
      if (tankIndex != -1) {
        _tanks[tankIndex].removeDevice(deviceId);
      }
      
      notifyListeners();
      print('TankProvider: 수조에서 장치 제거 완료');
      return true;
    } catch (e) {
      _setError('수조에서 장치를 제거하는데 실패했습니다: $e');
      print('TankProvider: 장치 제거 실패 - $e');
      return false;
    }
  }
  
  /// 특정 수조 정보 가져오기
  Tank? getTank(String tankId) {
    try {
      return _tanks.firstWhere((tank) => tank.id == tankId);
    } catch (e) {
      return null;
    }
  }
  
  /// 특정 장치가 속한 수조 찾기
  Tank? findTankByDevice(String deviceId) {
    try {
      return _tanks.firstWhere((tank) => tank.deviceIds.contains(deviceId));
    } catch (e) {
      return null;
    }
  }
  
  /// 수조에 속하지 않은 장치 목록 가져오기
  List<Device> getUnassignedDevices(List<Device> allDevices) {
    final assignedDeviceIds = <String>{};
    
    for (final tank in _tanks) {
      assignedDeviceIds.addAll(tank.deviceIds);
    }
    
    return allDevices.where((device) => !assignedDeviceIds.contains(device.id)).toList();
  }
  
  /// 특정 수조의 장치 목록 가져오기
  List<Device> getTankDevices(String tankId, List<Device> allDevices) {
    final tank = getTank(tankId);
    if (tank == null) return [];
    
    return allDevices.where((device) => tank.deviceIds.contains(device.id)).toList();
  }
  
  /// 수조 목록 새로고침
  Future<void> refresh() async {
    await _loadTanks();
  }
  
  // 헬퍼 메서드들
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }
}
