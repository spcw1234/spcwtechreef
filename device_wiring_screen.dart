import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'device_provider.dart';
import 'device.dart';
import 'tank_provider.dart';

/// 장치 간 배선(와이어링) 설정 화면
/// TEMP/ORP 등 컨트롤러 장치의 상태 토픽을 다른 장치(예: 쿨러)에 연결
class DeviceWiringScreen extends StatefulWidget {
  final Device? device; // 특정 장치에 대한 와이어링 설정인 경우
  
  const DeviceWiringScreen({super.key, this.device});

  @override
  State<DeviceWiringScreen> createState() => _DeviceWiringScreenState();
}

class _DeviceWiringScreenState extends State<DeviceWiringScreen> {
  Device? _selectedSource;
  Device? _selectedTarget;

  @override
  void initState() {
    super.initState();
    // 특정 장치가 전달된 경우 target으로 설정
    if (widget.device != null) {
      _selectedTarget = widget.device;
    }
  }

  @override
  Widget build(BuildContext context) {
  final deviceProvider = context.watch<DeviceProvider>();
  final tankProvider = context.watch<TankProvider>();
  final devices = deviceProvider.devices;

    // 간단한 필터: 소스는 TEMP/ORP, 타겟은 TEMP/ORP/CHIL
    final sourceCandidates = devices.where((d) => d.deviceType == 'TEMP' || d.deviceType == 'ORP').toList();
    final targetCandidates = devices.where((d) => d.deviceType == 'TEMP' || d.deviceType == 'ORP' || d.deviceType == 'CHIL').toList();

    String _labelWithTank(Device d) {
      final tank = tankProvider.findTankByDevice(d.id);
      if (tank == null) return '${d.customName} (${d.deviceType})';
      return '${d.customName} (${d.deviceType}) - ${tank.name}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('장치 배선 설정'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '소스 장치 (상태 제공자)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButton<Device>(
              isExpanded: true,
              hint: const Text('소스 장치를 선택'),
              value: _selectedSource,
              onChanged: (val) => setState(() => _selectedSource = val),
              items: sourceCandidates.map((d) => DropdownMenuItem(value: d, child: Text(_labelWithTank(d)))).toList(),
            ),
            const SizedBox(height: 24),
            const Text(
              '타겟 장치 (소스를 구독할 장치)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButton<Device>(
              isExpanded: true,
              hint: const Text('타겟 장치를 선택'),
              value: _selectedTarget,
              onChanged: (val) => setState(() => _selectedTarget = val),
              items: targetCandidates.map((d) => DropdownMenuItem(value: d, child: Text(_labelWithTank(d)))).toList(),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_selectedSource != null && _selectedTarget != null && _selectedSource != _selectedTarget)
                        ? () {
                            deviceProvider.wireDevices(source: _selectedSource!, target: _selectedTarget!);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('배선 설정 완료')));
                          }
                        : null,
                    icon: const Icon(Icons.cable),
                    label: const Text('배선 연결'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_selectedTarget != null && deviceProvider.deviceWiringMap.containsKey(_selectedTarget!.id))
                        ? () {
                            deviceProvider.unwireDevice(_selectedTarget!);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('배선 해제 완료')));
                          }
                        : null,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                    icon: const Icon(Icons.link_off),
                    label: const Text('배선 해제'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 8),
            const Text('현재 배선 목록', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: deviceProvider.deviceWiringMap.isEmpty
                  ? const Center(child: Text('설정된 배선이 없습니다.'))
                  : ListView(
                      children: deviceProvider.deviceWiringMap.entries.map((e) {
                        final target = devices.firstWhere(
                          (d) => d.id == e.key,
                          orElse: () => Device(id: e.key, customName: e.key, deviceType: 'UNKNOWN'),
                        );
                        final tank = tankProvider.findTankByDevice(target.id);
                        return ListTile(
                          leading: const Icon(Icons.cable),
                          title: Text(target.customName + (tank != null ? ' (${tank.name})' : '')),
                          subtitle: Text('소스: ${e.value}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => deviceProvider.unwireDevice(target),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
