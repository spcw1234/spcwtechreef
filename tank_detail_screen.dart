import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'tank_provider.dart';
import 'device_provider.dart';
import 'tank.dart';
import 'device.dart';
import 'temp_settings_screen.dart';
import 'orp_settings_screen.dart';
import 'cv_settings_screen_webview.dart';
import 'dose_settings_screen.dart';
import 'waterlevel_screen.dart';
import 'temperature_graph_screen.dart';

/**
 * TankDetailScreen 클래스
 * 특정 수조의 상세 정보 및 장치 관리 화면
 */
class TankDetailScreen extends StatelessWidget {
  final String tankId;

  const TankDetailScreen({Key? key, required this.tankId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer2<TankProvider, DeviceProvider>(
      builder: (context, tankProvider, deviceProvider, child) {
        final tank = tankProvider.getTank(tankId);
        
        if (tank == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('수조를 찾을 수 없음')),
            body: const Center(
              child: Text('요청한 수조를 찾을 수 없습니다.'),
            ),
          );
        }

        final tankDevices = tankProvider.getTankDevices(tankId, deviceProvider.devices);
        final unassignedDevices = tankProvider.getUnassignedDevices(deviceProvider.devices);

        return Scaffold(
          appBar: AppBar(
            title: Text(tank.name),
            backgroundColor: Colors.blue[700],
            foregroundColor: Colors.white,
            actions: [
              // 장치 추가 버튼
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '장치 추가',
                onPressed: unassignedDevices.isNotEmpty 
                    ? () => _showAddDeviceDialog(context, tank, unassignedDevices)
                    : null,
              ),
            ],
          ),
          body: Column(
            children: [
              // 수조 정보 헤더
              _buildTankHeader(tank),
              
              // 장치 목록
              Expanded(
                child: tankDevices.isEmpty 
                    ? _buildEmptyDeviceState(context, tank, unassignedDevices)
                    : _buildDeviceList(context, tank, tankDevices),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 수조 정보 헤더
  Widget _buildTankHeader(Tank tank) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.water,
                color: Colors.blue[600],
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tank.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (tank.description.isNotEmpty)
                      Text(
                        tank.description,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip(
                icon: Icons.devices,
                label: '장치 ${tank.deviceCount}개',
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              _buildInfoChip(
                icon: Icons.access_time,
                label: _formatDate(tank.updatedAt),
                color: Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 정보 칩 위젯
  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 장치가 없을 때의 상태
  Widget _buildEmptyDeviceState(BuildContext context, Tank tank, List<Device> unassignedDevices) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.devices_other,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text(
            '이 수조에 연결된 장치가 없습니다',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          if (unassignedDevices.isNotEmpty) ...[
            Text(
              '${unassignedDevices.length}개의 미할당 장치가 있습니다',
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddDeviceDialog(context, tank, unassignedDevices),
              icon: const Icon(Icons.add),
              label: const Text('장치 추가'),
            ),
          ] else ...[
            Text(
              '먼저 장치를 등록해주세요',
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 장치 목록
  Widget _buildDeviceList(BuildContext context, Tank tank, List<Device> devices) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        return _buildDeviceCard(context, tank, device);
      },
    );
  }

  /// 장치 카드
  Widget _buildDeviceCard(BuildContext context, Tank tank, Device device) {
    return Consumer<DeviceProvider>(
      builder: (context, provider, child) {
        // DOSE 장치의 경우 DosingPumpInfo의 online 상태를 확인
        bool isDeviceConnected = device.isConnected;
        if (device.deviceType.toUpperCase() == 'DOSE') {
          final doseInfo = provider.getDoseInfo(device.id);
          isDeviceConnected = doseInfo?.online ?? false;
        }
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isDeviceConnected ? Colors.green : Colors.red,
              child: Icon(
                _getDeviceIcon(device.deviceType),
                color: Colors.white,
              ),
            ),
        title: Text(device.customName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('타입: ${device.deviceType}'),
            if (device.currentTemp != null)
              Text('현재 온도: ${device.currentTemp!.toStringAsFixed(1)}°C'),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'settings':
                _navigateToDeviceSettings(context, device);
                break;
              case 'graph':
                _navigateToGraph(context, device);
                break;
              case 'remove':
                _showRemoveDeviceDialog(context, tank, device);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings, size: 20),
                  SizedBox(width: 8),
                  Text('설정'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'graph',
              child: Row(
                children: [
                  Icon(Icons.show_chart, size: 20),
                  SizedBox(width: 8),
                  Text('그래프'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'remove',
              child: Row(
                children: [
                  Icon(Icons.remove_circle, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('수조에서 제거', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _navigateToDeviceSettings(context, device),
      ),
    );
      },
    );
  }

  /// 장치 추가 다이얼로그
  void _showAddDeviceDialog(BuildContext context, Tank tank, List<Device> unassignedDevices) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tank.name}에 장치 추가'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('추가할 장치를 선택하세요:'),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: unassignedDevices.length,
                  itemBuilder: (context, index) {
                    final device = unassignedDevices[index];
                    return Consumer<DeviceProvider>(
                      builder: (context, provider, child) {
                        // DOSE 장치의 경우 DosingPumpInfo의 online 상태를 확인
                        bool isDeviceConnected = device.isConnected;
                        if (device.deviceType.toUpperCase() == 'DOSE') {
                          final doseInfo = provider.getDoseInfo(device.id);
                          isDeviceConnected = doseInfo?.online ?? false;
                        }
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isDeviceConnected ? Colors.green : Colors.red,
                            child: Icon(
                              _getDeviceIcon(device.deviceType),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                      title: Text(device.customName),
                      subtitle: Text('타입: ${device.deviceType}'),
                      onTap: () async {
                        final success = await context.read<TankProvider>().addDeviceToTank(
                          tank.id,
                          device.id,
                        );

                        Navigator.pop(context);

                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${device.customName}이 ${tank.name}에 추가되었습니다'),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('장치 추가에 실패했습니다'),
                            ),
                          );
                        }
                      },
                    );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }

  /// 장치 제거 확인 다이얼로그
  void _showRemoveDeviceDialog(BuildContext context, Tank tank, Device device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('장치 제거'),
        content: Text('${device.customName}을(를) ${tank.name}에서 제거하시겠습니까?\n\n장치는 삭제되지 않고 미할당 상태가 됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await context.read<TankProvider>().removeDeviceFromTank(
                tank.id,
                device.id,
              );

              Navigator.pop(context);

              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${device.customName}이 ${tank.name}에서 제거되었습니다'),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('장치 제거에 실패했습니다'),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('제거'),
          ),
        ],
      ),
    );
  }  /// 장치 설정 화면으로 이동
  void _navigateToDeviceSettings(BuildContext context, Device device) {
    if (device.deviceType == 'TEMP') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TempSettingsScreen(deviceId: device.id),
        ),
      );
    } else if (device.deviceType == 'ORP') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrpSettingsScreen(deviceId: device.id),
        ),
      );
    } else if (device.deviceType == 'CV') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CvSettingsScreenWebview(deviceId: device.id),
        ),
      );
    } else if (device.deviceType == 'DOSE') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DoseSettingsScreen(deviceId: device.id),
        ),
      );
    } else if (device.deviceType.toUpperCase() == 'WLV' || device.deviceType == 'Wlv') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => WaterLevelScreen(deviceId: device.id),
        ),
      );
    }
  }
  /// 그래프 화면으로 이동
  void _navigateToGraph(BuildContext context, Device device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TemperatureGraphScreen(device: device),
      ),
    );
  }
  /// 날짜 포맷팅
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전 수정';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전 수정';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전 수정';
    } else {
      return '방금 수정';
    }
  }
  
  /// 장치 타입에 맞는 아이콘 반환
  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toUpperCase()) {
      case 'TEMP':
        return Icons.thermostat;
      case 'WLV':
        return Icons.water;
      case 'ORP':
        return Icons.science;
      case 'CV':
        return Icons.videocam;
      default:
        return Icons.device_unknown;
    }
  }
}
