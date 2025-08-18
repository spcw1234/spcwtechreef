import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fijkplayer/fijkplayer.dart';
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
  String _streamQuality = 'medium';
  bool _detectionEnabled = true;

  FijkPlayer? _player;
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
    _disposePlayer();
    super.dispose();
  }

  void _initPlayer(String url) {
    if (!mounted || _isDisposing) return;
    _disposePlayer();
    final p = FijkPlayer();
    // 최소 옵션 (추가 최적화 필요시 확장)
    p.setOption(FijkOption.formatCategory, 'fflags', 'nobuffer');
    p.setOption(FijkOption.playerCategory, 'packet-buffering', '0');
    p.addListener(() {
      if (!mounted || _isDisposing) return;
      final state = p.value.state;
      if (state == FijkState.started) {
        setState(() {
          _isStreamConnected = true;
          _currentStreamUrl = url;
        });
      } else if (state == FijkState.error) {
        setState(() => _isStreamConnected = false);
      }
    });
    p.setDataSource(url, autoPlay: true);
    _player = p;
    Timer(const Duration(seconds: 15), () {
      if (!mounted || _isDisposing) return;
      if (_player == p && !_isStreamConnected) {
        setState(() => _isStreamConnected = false);
      }
    });
  }

  void _disposePlayer() {
    final p = _player;
    _player = null;
    if (p != null) {
      try {
        p.stop();
        p.release();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isStreamConnected = false;
        _currentStreamUrl = null;
      });
    }
  }

  void _startStream(Device device, DeviceProvider provider) {
    final url = device.streamUrl?.isNotEmpty == true
        ? device.streamUrl!
        : 'http://spcwtech.mooo.com:7200/stream';
    _initPlayer(url);
    provider.startCvStreaming(device);
  }

  void _stopStream(Device device, DeviceProvider provider) {
    _disposePlayer();
    provider.stopCvStreaming(device);
  }

  void _reconnect(Device device) {
    if (_currentStreamUrl != null) {
      _initPlayer(_currentStreamUrl!);
    } else {
      final url = device.streamUrl?.isNotEmpty == true
          ? device.streamUrl!
          : 'http://spcwtech.mooo.com:7200/stream';
      _initPlayer(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(builder: (context, provider, _) {
      final device = provider.devices.firstWhere(
        (d) => d.id == widget.deviceId,
        orElse: () => Device(id: widget.deviceId, customName: 'Unknown', deviceType: 'CV'),
      );
      return Scaffold(
        appBar: AppBar(
          title: Text('${device.customName} (FFmpeg)'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: device.isConnected ? () => _reconnect(device) : null,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDeviceInfo(device),
              const SizedBox(height: 16),
              _buildStreamControls(device, provider),
              const SizedBox(height: 16),
              _buildDetectionControls(device, provider),
              const SizedBox(height: 16),
              _buildSystemControls(device, provider),
              const SizedBox(height: 24),
              _buildPlayerArea(),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildDeviceInfo(Device device) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${device.id}'),
            if (device.streamUrl != null) Text('URL: ${device.streamUrl}'),
            Text('연결: ${device.isConnected ? 'ON' : 'OFF'}',
                style: TextStyle(color: device.isConnected ? Colors.green : Colors.red)),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamControls(Device device, DeviceProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('스트림 제어', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ElevatedButton(
                onPressed: device.isConnected ? () => _startStream(device, provider) : null,
                child: const Text('시작'),
              ),
              ElevatedButton(
                onPressed: _isStreamConnected ? () => _stopStream(device, provider) : null,
                child: const Text('중지'),
              ),
              ElevatedButton(
                onPressed: _isStreamConnected ? () => _reconnect(device) : null,
                child: const Text('재연결'),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButton<String>(
              value: _streamQuality,
              onChanged: device.isConnected
                  ? (v) {
                      if (v != null) {
                        setState(() => _streamQuality = v);
                        provider.setCvStreamQuality(device, v);
                      }
                    }
                  : null,
              items: const [
                DropdownMenuItem(value: 'low', child: Text('낮음')),
                DropdownMenuItem(value: 'medium', child: Text('보통')),
                DropdownMenuItem(value: 'high', child: Text('높음')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionControls(Device device, DeviceProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('객체 감지', style: TextStyle(fontWeight: FontWeight.bold)),
            SwitchListTile(
              title: const Text('활성화'),
              value: _detectionEnabled,
              onChanged: device.isConnected
                  ? (v) {
                      setState(() => _detectionEnabled = v);
                      provider.setCvDetectionEnabled(device, v);
                    }
                  : null,
            ),
            Text('임계값: ${(100 * _detectionThreshold).round()}%'),
            Slider(
              value: _detectionThreshold,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              onChanged: device.isConnected
                  ? (v) => setState(() => _detectionThreshold = v)
                  : null,
              onChangeEnd: device.isConnected
                  ? (v) => provider.setCvDetectionThreshold(device, v)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemControls(Device device, DeviceProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ElevatedButton.icon(
              onPressed: device.isConnected ? () => provider.requestCvStatus(device) : null,
              icon: const Icon(Icons.refresh),
              label: const Text('상태'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: device.isConnected ? () => _confirmRestart(device, provider) : null,
              icon: const Icon(Icons.restart_alt),
              label: const Text('재시작'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRestart(Device device, DeviceProvider provider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('재시작'),
        content: const Text('장치를 재시작하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('확인')),
        ],
      ),
    );
    if (ok == true) provider.restartCvDevice(device);
  }

  Widget _buildPlayerArea() {
    return Card(
      child: SizedBox(
        height: 220,
        child: Center(
          child: _player != null
              ? FijkView(player: _player!, fit: FijkFit.contain)
              : const Text('스트림 미시작'),
        ),
      ),
    );
  }
}
// 파일 끝
