import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'device.dart';
import 'device_provider.dart';
import 'temp_settings_screen.dart';
import 'orp_settings_screen.dart';
import 'cv_settings_screen_webview.dart';
import 'temperature_graph_screen.dart';
import 'dose_settings_screen.dart';
import 'waterlevel_screen.dart';
import 'chiller_settings_screen.dart';

class DeviceListScreen extends StatelessWidget {
  const DeviceListScreen({super.key});

  Future<void> _showRenameDialog(BuildContext context, Device device) async {
    final TextEditingController nameController = TextEditingController(text: device.customName);
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Rename Device'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: "Enter new name"),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                Provider.of<DeviceProvider>(context, listen: false)
                    .renameDevice(device.id, nameController.text);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showDiscoveryDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // User must explicitly close
      builder: (BuildContext dialogContext) {
        // Use a StatefulWidget for the dialog content to manage its own state if needed
        // or rely on the provider to update the list of discovered IDs.
        return Consumer<DeviceProvider>(
          builder: (context, deviceProvider, child) {
            return AlertDialog(
              title: const Text('Discovering Devices...'),
              content: SizedBox(
                width: double.maxFinite,                child: deviceProvider.discoveredDevicesDuringScan.isEmpty
                    ? const Center(child: Text("No new devices found yet.\nEnsure devices are powered on and on the same network."))
                    : ListView.builder(
                  shrinkWrap: true,
                  itemCount: deviceProvider.discoveredDevicesDuringScan.length,
                  itemBuilder: (context, index) {
                    final entry = deviceProvider.discoveredDevicesDuringScan.entries.elementAt(index);
                    final deviceId = entry.key;
                    final deviceType = entry.value;
                    return ListTile(
                      title: Text(deviceId),
                      subtitle: Text('Type: ${deviceType.toUpperCase()}'),
                      trailing: ElevatedButton(
                        child: const Text('Register'),
                        onPressed: () {
                          deviceProvider.registerDevice(deviceId);
                          // Optionally close dialog after registering one, or let user register multiple
                          // if (deviceProvider.discoveredDevicesDuringScan.isEmpty) {
                          //   Navigator.of(dialogContext).pop();
                          // }
                        },
                      ),
                    );
                  },
                ),
              ),
              actions: <Widget>[
                if (!deviceProvider.isDiscovering) // Show start button if not discovering
                  TextButton(
                    child: const Text('Start Scan'),
                    onPressed: () {
                      deviceProvider.startDiscovery();
                    },
                  ),
                if (deviceProvider.isDiscovering) // Show stop button if discovering
                  TextButton(
                    child: const Text('Stop Scan'),
                    onPressed: () {
                      deviceProvider.stopDiscovery();
                    },
                  ),
                TextButton(
                  child: const Text('Close'),
                  onPressed: () {
                    deviceProvider.stopDiscovery(); // Ensure discovery stops
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      // Ensure discovery is stopped when dialog is dismissed by any means
      Provider.of<DeviceProvider>(context, listen: false).stopDiscovery();
    });
    // Start discovery immediately when dialog is opened
    Provider.of<DeviceProvider>(context, listen: false).startDiscovery();
  }


  @override
  Widget build(BuildContext context) {
    final deviceProvider = Provider.of<DeviceProvider>(context);

    return Scaffold(      appBar: AppBar(
        title: const Text('Registered Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Register New Device',
            onPressed: () {
              _showDiscoveryDialog(context);
            },
          ),
        ],
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, provider, child) {
          if (provider.devices.isEmpty) {
            return const Center(
              child: Text('No devices registered yet. Tap + to add.'),
            );
          }
          final doseDevices = provider.devices.where((d) => d.deviceType == 'DOSE').toList();
          // DOSE 장치는 자동으로 상태를 전송하므로 별도 요청 불필요
          // if (doseDevices.isNotEmpty) {
          //   WidgetsBinding.instance.addPostFrameCallback((_) {
          //     for (final d in doseDevices) {
          //       provider.requestDoseStatus(d.id);
          //     }
          //   });
          // }
          
          return ListView.builder(
            itemCount: provider.devices.length,
            itemBuilder: (context, index) {
              final device = provider.devices[index];
              // DOSE 장치의 경우 DosingPumpInfo의 online 상태를 확인
              bool isDeviceConnected = device.isConnected;
              if (device.deviceType.toUpperCase() == 'DOSE') {
                final doseInfo = provider.getDoseInfo(device.id);
                isDeviceConnected = doseInfo?.online ?? false;
              }
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  leading: device.deviceType.toUpperCase() == 'DOSE'
                      ? CircleAvatar(
                          radius: 26,
                          backgroundColor: isDeviceConnected ? Colors.green : Colors.red,
                          child: Icon(_getDeviceIcon(device.deviceType), color: Colors.white, size: 28),
                        )
                      : Icon(
                          _getDeviceIcon(device.deviceType),
                          color: isDeviceConnected ? Colors.green : Colors.red,
                        ),
                  title: Text(device.customName),
                  subtitle: device.deviceType.toUpperCase() == 'DOSE'
                      ? Text('DOSE | ID: ${device.id}', style: const TextStyle(fontSize: 13))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Type: ${device.deviceType.toUpperCase()} | ID: ${device.id}'),
                            if (isDeviceConnected && device.currentTemp != null)
                              Text('Temp: ${device.currentTemp?.toStringAsFixed(2)}°C'),
                            if (isDeviceConnected && device.setTemp != null)
                              Text('Set: ${device.setTemp?.toStringAsFixed(1)}°C'),
                            if (device.deviceType.toUpperCase() == 'ORP' && isDeviceConnected && device.orpCorrected != null)
                              Text('ORP: ${device.orpCorrected?.toStringAsFixed(1)} mV'),
                            if (device.deviceType.toUpperCase() == 'CV' && isDeviceConnected) ...[
                              if (device.streamStatus != null) Text('Stream: ${_getStreamStatusText(device.streamStatus!)}'),
                              if (device.detectedObjects != null) Text('Objects: ${device.detectedObjects}'),
                            ],
                            if (device.deviceType.toUpperCase() == 'CHIL' && isDeviceConnected) ...[
                              if (device.chillerState != null) 
                                Text('Chiller: ${device.chillerState! ? "ON" : "OFF"}', 
                                     style: TextStyle(color: device.chillerState! ? Colors.cyan : Colors.grey)),
                              if (device.tempSource != null) Text('Source: ${device.tempSource}'),
                            ],
                          ],
                        ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (device.deviceType.toUpperCase() != 'DOSE')
                        IconButton(
                          icon: const Icon(Icons.show_chart),
                          tooltip: 'Temperature Graph',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => TemperatureGraphScreen(device: device),
                              ),
                            );
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Rename',
                        onPressed: () => _showRenameDialog(context, device),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        tooltip: 'Remove',
                        onPressed: () {
                          showDialog(context: context, builder: (ctx) => AlertDialog(
                            title: const Text("Confirm Delete"),
                            content: Text("Are you sure you want to remove ${device.customName}?"),
                            actions: [
                              TextButton(onPressed: (){ Navigator.of(ctx).pop(); }, child: const Text("Cancel")),
                              TextButton(onPressed: (){ provider.removeDevice(device.id); Navigator.of(ctx).pop(); }, child: const Text("Delete", style: TextStyle(color: Colors.red))),
                            ],
                          ));
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    // 장치 타입에 따라 다른 설정 화면으로 이동
                    if (device.deviceType.toUpperCase() == 'ORP') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => OrpSettingsScreen(deviceId: device.id),
                        ),
                      );
                    } else if (device.deviceType.toUpperCase() == 'CV') {
                      _showCvPlayerSelectionDialog(context, device);
                    } else if (device.deviceType.toUpperCase() == 'DOSE') {
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
                    } else if (device.deviceType.toUpperCase() == 'CHIL') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChillerSettingsScreen(device: device),
                        ),
                      );
                    } else {
                      // TEMP 또는 기타 타입은 기본 설정 화면으로
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TempSettingsScreen(deviceId: device.id),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          );
        },      ),
    );
  }

  /// 장치 타입별 아이콘
  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toUpperCase()) {
      case 'TEMP':
        return Icons.thermostat;
      case 'ORP':
        return Icons.science;
      case 'WLV':
        return Icons.water;
      case 'CV':
        return Icons.videocam;
      case 'DOSE':
        return Icons.science;
      case 'CHIL':
        return Icons.ac_unit;
      default:
        return Icons.devices_other;
    }
  }

  /// CV 스트림 상태 텍스트 변환
  String _getStreamStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'playing':
        return '재생중';
      case 'stopped':
        return '중지';
      case 'error':
        return '에러';
      default:
        return status;
    }
  }

  /// CV 플레이어 선택 다이얼로그
  void _showCvPlayerSelectionDialog(BuildContext context, Device device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CV 플레이어 선택'),
        content: const Text('WebView 플레이어로 열겠습니까?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CvSettingsScreenWebview(deviceId: device.id),
                ),
              );
            },
            child: const Text('WebView'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('취소'),
          )
        ],
      ),
    );
  }
}