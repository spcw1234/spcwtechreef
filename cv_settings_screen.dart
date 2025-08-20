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
  bool _isStreamConnected = false;
  String? _currentStreamUrl;
  bool _isDisposing = false;

  @override
  void initState() {
    super.initState();
    _isDisposing = false;
  }

  @override
  void dispose() {
    _isDisposing = true;
    super.dispose();
  }

  void _startStream(Device device, DeviceProvider deviceProvider) {
    print('[CvSettingsScreen _startStream] Starting stream placeholder');
    setState(() {
      _isStreamConnected = true;
      _currentStreamUrl = "http://spcwtech.mooo.com:7200/stream";
    });
  }

  void _stopStream(Device device, DeviceProvider deviceProvider) {
    print('[CvSettingsScreen _stopStream] Stopping stream placeholder');
    setState(() {
      _isStreamConnected = false;
      _currentStreamUrl = null;
    });
    deviceProvider.stopCvStreaming(device);
  }

  void _reconnectStream(Device device) {
    print('[CvSettingsScreen _reconnectStream] Reconnecting stream placeholder');
    setState(() {
      _isStreamConnected = true;
      _currentStreamUrl = "http://spcwtech.mooo.com:7200/stream";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, deviceProvider, child) {
        final device = deviceProvider.devices.firstWhere(
          (d) => d.id == widget.deviceId,
          orElse: () => throw StateError('Device not found'),
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
                _buildDeviceInfoCard(device),
                const SizedBox(height: 20),
                _buildStreamControlSection(device, deviceProvider),
                const SizedBox(height: 20),
                _buildDetectionSettingsSection(device, deviceProvider),
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
            Text('장치 정보', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            Text('장치 ID: ${device.id}'),
            const SizedBox(height: 8),
            Text('연결 상태: ${device.isConnected ? "연결됨" : "연결 끊김"}'),
            if (_currentStreamUrl != null) ...[
              const SizedBox(height: 8),
              Text('스트림 URL: $_currentStreamUrl'),
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
            Text('스트림 제어', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
                color: Colors.black,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isStreamConnected ? Icons.videocam : Icons.videocam_off,
                      color: _isStreamConnected ? Colors.green : Colors.grey,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isStreamConnected ? '스트림 연결됨' : '스트림 준비됨',
                      style: TextStyle(
                        color: _isStreamConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _startStream(device, deviceProvider),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('시작'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _stopStream(device, deviceProvider),
                    icon: const Icon(Icons.stop),
                    label: const Text('중지'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _reconnectStream(device),
                    icon: const Icon(Icons.refresh),
                    label: const Text('재연결'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
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
            Text('객체 감지 설정', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('객체 감지 활성화'),
              value: _detectionEnabled,
              onChanged: (bool value) {
                setState(() {
                  _detectionEnabled = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Text('감지 신뢰도 임계값: ${(_detectionThreshold * 100).toInt()}%'),
            Slider(
              value: _detectionThreshold,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              onChanged: (double value) {
                setState(() {
                  _detectionThreshold = value;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}