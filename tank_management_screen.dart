import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'tank_provider.dart';
import 'device_provider.dart';
import 'tank.dart';
import 'tank_detail_screen.dart';
import 'device_list_screen.dart';
import 'device_wiring_screen.dart';
import 'dose_settings_screen.dart';

/**
 * TankManagementScreen 클래스
 * 수조 관리 메인 화면
 */
class TankManagementScreen extends StatelessWidget {
  const TankManagementScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SPCWTECH Control'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,        actions: [
          // 새 장치 검색 버튼
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '새 장치 검색',
            onPressed: () => _showDeviceDiscoveryDialog(context),
          ),
          // 장치 배선 설정 화면 이동
          IconButton(
            icon: const Icon(Icons.cable),
            tooltip: '장치 배선',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DeviceWiringScreen(),
                ),
              );
            },
          ),
          // 첫 번째 도징펌프 빠른 이동 (있을 경우)
          Builder(
            builder: (context) {
              final doseDevices = context.read<DeviceProvider>().devices.where((d) => d.deviceType == 'DOSE');
              if (doseDevices.isEmpty) return const SizedBox.shrink();
              final firstDose = doseDevices.first;
              return IconButton(
                icon: const Icon(Icons.science),
                tooltip: '도징펌프',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DoseSettingsScreen(deviceId: firstDose.id),
                    ),
                  );
                },
              );
            },
          ),
          // 전체 장치 리스트 보기 버튼
          IconButton(
            icon: const Icon(Icons.devices),
            tooltip: '전체 장치 목록',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DeviceListScreen(),
                ),
              );
            },
          ),
          // 새로고침 버튼
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () {
              context.read<TankProvider>().refresh();
            },
          ),
        ],
      ),
      body: Consumer<TankProvider>(
        builder: (context, tankProvider, child) {
          if (tankProvider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (tankProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '오류 발생',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.red[400],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tankProvider.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => tankProvider.refresh(),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            );
          }

          final tanks = tankProvider.tanks;

          if (tanks.isEmpty) {
            return _buildEmptyState(context);
          }

          return _buildTankList(context, tanks);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateTankDialog(context),
        tooltip: '새 수조 추가',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 수조가 없을 때의 상태
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.water,
            size: 80,
            color: Colors.blue[300],
          ),
          const SizedBox(height: 24),
          const Text(
            '등록된 수조가 없습니다',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '오른쪽 하단의 + 버튼을 눌러\n첫 번째 수조를 만들어보세요!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showCreateTankDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('수조 추가'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => _showDeviceDiscoveryDialog(context),
                icon: const Icon(Icons.search),
                label: const Text('장치 검색'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 수조 목록 위젯
  Widget _buildTankList(BuildContext context, List<Tank> tanks) {
    return RefreshIndicator(
      onRefresh: () => context.read<TankProvider>().refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: tanks.length,
        itemBuilder: (context, index) {
          final tank = tanks[index];
          return _buildTankCard(context, tank);
        },
      ),
    );
  }

  /// 수조 카드 위젯
  Widget _buildTankCard(BuildContext context, Tank tank) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TankDetailScreen(tankId: tank.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 수조 이름과 메뉴 버튼
              Row(
                children: [
                  Icon(
                    Icons.water,
                    color: Colors.blue[600],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      tank.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _showEditTankDialog(context, tank);
                          break;
                        case 'delete':
                          _showDeleteTankDialog(context, tank);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('수정'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('삭제', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              
              // 수조 설명 (있는 경우)
              if (tank.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  tank.description,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
              
              const SizedBox(height: 12),
              
              // 장치 정보
              Row(
                children: [
                  Icon(
                    Icons.devices,
                    color: Colors.grey[600],
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '장치 ${tank.deviceCount}개',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '수정: ${_formatDate(tank.updatedAt)}',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  /// 새 수조 생성 다이얼로그
  void _showCreateTankDialog(BuildContext context) {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
      showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 수조 추가'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '수조 이름',
                    hintText: '예: 메인 수조, 격리 수조 등',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: '설명 (선택사항)',
                    hintText: '수조에 대한 간단한 설명',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('수조 이름을 입력해주세요')),
                );
                return;
              }

              final success = await context.read<TankProvider>().createTank(
                name: name,
                description: descriptionController.text.trim(),
              );

              if (success) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('수조 "$name"이 생성되었습니다')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('수조 생성에 실패했습니다')),
                );
              }
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }
  /// 수조 수정 다이얼로그
  void _showEditTankDialog(BuildContext context, Tank tank) {
    final nameController = TextEditingController(text: tank.name);
    final descriptionController = TextEditingController(text: tank.description);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(        title: const Text('수조 정보 수정'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '수조 이름',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: '설명',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('수조 이름을 입력해주세요')),
                );
                return;
              }

              final success = await context.read<TankProvider>().updateTank(
                tank.id,
                name: name,
                description: descriptionController.text.trim(),
              );

              if (success) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('수조 정보가 수정되었습니다')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('수조 수정에 실패했습니다')),
                );
              }
            },
            child: const Text('수정'),
          ),
        ],
      ),    );
  }

  /// 수조 삭제 확인 다이얼로그
  void _showDeleteTankDialog(BuildContext context, Tank tank) {
    showDialog(      context: context,
      builder: (context) => AlertDialog(
        title: const Text('수조 삭제'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('정말로 "${tank.name}" 수조를 삭제하시겠습니까?'),
                const SizedBox(height: 8),
                if (tank.deviceCount > 0)
                  Text(
                    '주의: 이 수조에는 ${tank.deviceCount}개의 장치가 연결되어 있습니다. 삭제 후 장치들은 미할당 상태가 됩니다.',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final success = await context.read<TankProvider>().deleteTank(tank.id);

              if (success) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('수조 "${tank.name}"이 삭제되었습니다')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('수조 삭제에 실패했습니다')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
  /// 날짜 포맷팅
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  /// 새 장치 검색 다이얼로그
  void _showDeviceDiscoveryDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return Consumer<DeviceProvider>(
          builder: (context, deviceProvider, child) {
            return AlertDialog(
              title: const Text('새 장치 검색'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (deviceProvider.isDiscovering)
                        const Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('장치를 검색하고 있습니다...'),
                            SizedBox(height: 8),
                            Text(
                              'ESP32 장치의 전원이 켜져 있고\n같은 네트워크에 연결되어 있는지 확인하세요.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      if (deviceProvider.discoveredDevicesDuringScan.isEmpty && !deviceProvider.isDiscovering)
                        const Text(
                          '검색된 새 장치가 없습니다.\n장치의 전원과 네트워크 연결을 확인하세요.',
                          textAlign: TextAlign.center,
                        ),
                      if (deviceProvider.discoveredDevicesDuringScan.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: deviceProvider.discoveredDevicesDuringScan.length,
                            itemBuilder: (context, index) {
                              final entry = deviceProvider.discoveredDevicesDuringScan.entries.elementAt(index);
                              final deviceId = entry.key;
                              final deviceType = entry.value;
                              return Card(
                                child: ListTile(
                                  title: Text(deviceId),
                                  subtitle: Text('종류: ${deviceType.toUpperCase()}'),
                                  trailing: ElevatedButton(
                                    onPressed: () {
                                      deviceProvider.registerDevice(deviceId);
                                      // 등록 후 성공 메시지 표시
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('장치 "$deviceId"가 등록되었습니다.'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    },
                                    child: const Text('등록'),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (!deviceProvider.isDiscovering)
                  TextButton(
                    onPressed: () {
                      deviceProvider.startDiscovery();
                    },
                    child: const Text('검색 시작'),
                  ),
                if (deviceProvider.isDiscovering)
                  TextButton(
                    onPressed: () {
                      deviceProvider.stopDiscovery();
                    },
                    child: const Text('검색 중지'),
                  ),
                TextButton(
                  onPressed: () {
                    deviceProvider.stopDiscovery();
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      // 다이얼로그가 닫힐 때 검색 중지
      Provider.of<DeviceProvider>(context, listen: false).stopDiscovery();
    });
  }
}
