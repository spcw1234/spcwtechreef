import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'device.dart';
import 'device_provider.dart';

class CvSettingsScreen extends StatefulWidget {
  final String deviceId;

  const CvSettingsScreen({Key? key, required this.deviceId}) : super(key: key);

  @override
  State<CvSettingsScreen> createState() => _CvSettingsScreenState();
}

class _CvSettingsScreenState extends State<CvSettingsScreen> {
  double _detectionThreshold = 0.5;
  String _streamQuality = "medium";
  bool _detectionEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, deviceProvider, child) {
        // deviceId로 Device 객체 찾기
        final device = deviceProvider.devices.firstWhere(
          (d) => d.id == widget.deviceId,
          orElse: () => throw Exception('Device not found'),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text('${device.customName} 설정'),
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 장치 정보 카드
                _buildDeviceInfoCard(device),
                const SizedBox(height: 20),
                
                // 스트림 제어 섹션
                _buildStreamControlSection(device, deviceProvider),
                const SizedBox(height: 20),
                
                // 카메라 제어 섹션
                _buildCameraControlSection(device, deviceProvider),
                const SizedBox(height: 20),
                
                // 감지 설정 섹션
                _buildDetectionSettingsSection(device, deviceProvider),
                const SizedBox(height: 20),
                
                // 시스템 제어 섹션
                _buildSystemControlSection(device, deviceProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeviceInfoCard(Device device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '장치 정보',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.videocam, color: Colors.blue[600]),
                const SizedBox(width: 8),
                Text('장치 ID: ${device.id}'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  device.isConnected 
                    ? Icons.wifi 
                    : Icons.wifi_off,
                  color: device.isConnected 
                    ? Colors.green 
                    : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  '연결 상태: ${device.isConnected ? "연결됨" : "연결 끊김"}',
                  style: TextStyle(
                    color: device.isConnected 
                      ? Colors.green 
                      : Colors.red,
                  ),
                ),
              ],
            ),
            if (device.streamUrl != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.stream, color: Colors.purple[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '스트림 URL: ${device.streamUrl}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (device.streamStatus != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _getStreamStatusIcon(device.streamStatus!),
                    color: _getStreamStatusColor(device.streamStatus!),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '스트림 상태: ${_getStreamStatusText(device.streamStatus!)}',
                    style: TextStyle(
                      color: _getStreamStatusColor(device.streamStatus!),
                    ),
                  ),
                ],
              ),
            ],
            if (device.detectedObjects != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.search, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  Text('감지된 객체: ${device.detectedObjects}개'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStreamControlSection(Device device, DeviceProvider deviceProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '스트림 제어',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: device.isConnected
                    ? () => deviceProvider.startCvStreaming(device)
                    : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('시작'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: device.isConnected
                    ? () => deviceProvider.stopCvStreaming(device)
                    : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('중지'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('스트림 품질'),
            DropdownButton<String>(
              value: _streamQuality,
              isExpanded: true,
              onChanged: device.isConnected
                ? (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _streamQuality = newValue;
                      });
                      deviceProvider.setCvStreamQuality(device, newValue);
                    }
                  }
                : null,
              items: const [
                DropdownMenuItem(value: "low", child: Text("낮음")),
                DropdownMenuItem(value: "medium", child: Text("보통")),
                DropdownMenuItem(value: "high", child: Text("높음")),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraControlSection(Device device, DeviceProvider deviceProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '카메라 제어',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  // 위쪽 버튼
                  IconButton(
                    onPressed: device.isConnected
                      ? () => deviceProvider.moveCvCamera(device, "up")
                      : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    iconSize: 48,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue[100],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 왼쪽 버튼
                      IconButton(
                        onPressed: device.isConnected
                          ? () => deviceProvider.moveCvCamera(device, "left")
                          : null,
                        icon: const Icon(Icons.keyboard_arrow_left),
                        iconSize: 48,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.blue[100],
                        ),
                      ),
                      const SizedBox(width: 20),
                      // 정지 버튼
                      IconButton(
                        onPressed: device.isConnected
                          ? () => deviceProvider.moveCvCamera(device, "stop")
                          : null,
                        icon: const Icon(Icons.stop),
                        iconSize: 48,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red[100],
                        ),
                      ),
                      const SizedBox(width: 20),
                      // 오른쪽 버튼
                      IconButton(
                        onPressed: device.isConnected
                          ? () => deviceProvider.moveCvCamera(device, "right")
                          : null,
                        icon: const Icon(Icons.keyboard_arrow_right),
                        iconSize: 48,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.blue[100],
                        ),
                      ),
                    ],
                  ),
                  // 아래쪽 버튼
                  IconButton(
                    onPressed: device.isConnected
                      ? () => deviceProvider.moveCvCamera(device, "down")
                      : null,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    iconSize: 48,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue[100],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionSettingsSection(Device device, DeviceProvider deviceProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '객체 감지 설정',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('객체 감지 활성화'),
              value: _detectionEnabled,
              onChanged: device.isConnected
                ? (bool value) {
                    setState(() {
                      _detectionEnabled = value;
                    });
                    deviceProvider.setCvDetectionEnabled(device, value);
                  }
                : null,
            ),
            const SizedBox(height: 16),
            Text('감지 신뢰도 임계값: ${(_detectionThreshold * 100).toInt()}%'),
            Slider(
              value: _detectionThreshold,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              onChanged: device.isConnected
                ? (double value) {
                    setState(() {
                      _detectionThreshold = value;
                    });
                  }
                : null,
              onChangeEnd: device.isConnected
                ? (double value) {
                    deviceProvider.setCvDetectionThreshold(device, value);
                  }
                : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemControlSection(Device device, DeviceProvider deviceProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '시스템 제어',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: device.isConnected
                    ? () => deviceProvider.requestCvStatus(device)
                    : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('상태 갱신'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: device.isConnected
                    ? () => _showRestartDialog(context, device, deviceProvider)
                    : null,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('재시작'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRestartDialog(BuildContext context, Device device, DeviceProvider deviceProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('장치 재시작'),
          content: Text('${device.customName} 장치를 재시작하시겠습니까?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                deviceProvider.restartCvDevice(device);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${device.customName} 재시작 명령을 전송했습니다.'),
                  ),
                );
              },
              child: const Text('확인'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          ],
        );
      },
    );
  }

  IconData _getStreamStatusIcon(String status) {
    switch (status) {
      case "streaming":
        return Icons.videocam;
      case "stopped":
        return Icons.videocam_off;
      case "offline":
        return Icons.cloud_off;
      default:
        return Icons.help;
    }
  }

  Color _getStreamStatusColor(String status) {
    switch (status) {
      case "streaming":
        return Colors.green;
      case "stopped":
        return Colors.orange;
      case "offline":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStreamStatusText(String status) {
    switch (status) {
      case "streaming":
        return "스트리밍 중";
      case "stopped":
        return "중지됨";
      case "offline":
        return "오프라인";
      default:
        return "알 수 없음";
    }
  }
}
