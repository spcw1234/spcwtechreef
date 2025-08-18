import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'device.dart';
import 'device_provider.dart';
import 'temperature_graph_screen.dart';
import 'dart:async'; // For Timer

class OrpSettingsScreen extends StatefulWidget {
  final String deviceId;

  const OrpSettingsScreen({super.key, required this.deviceId});

  @override
  State<OrpSettingsScreen> createState() => _OrpSettingsScreenState();
}

class _OrpSettingsScreenState extends State<OrpSettingsScreen> {
  late TextEditingController _setTempController;
  late TextEditingController _hysteresisController;
  late TextEditingController _pwmMinController;

  late FocusNode _setTempFocusNode;
  late FocusNode _hysteresisFocusNode;
  late FocusNode _pwmMinFocusNode;

  Timer? _setTempDebounce;
  Timer? _hysteresisDebounce;
  Timer? _pwmMinDebounce;

  @override
  void initState() {
    super.initState();
    final device = Provider.of<DeviceProvider>(context, listen: false)
        .devices
        .firstWhere((d) => d.id == widget.deviceId, orElse: () => Device(id: "error", customName: "Error", deviceType: "ORP"));

    _setTempController = TextEditingController(text: device.setTemp?.toStringAsFixed(1) ?? '');
    _hysteresisController = TextEditingController(text: device.hysteresis?.toStringAsFixed(2) ?? '');
    _pwmMinController = TextEditingController(text: device.pwmMin?.toString() ?? '');

    _setTempFocusNode = FocusNode();
    _hysteresisFocusNode = FocusNode();
    _pwmMinFocusNode = FocusNode();

    _setTempController.addListener(_onSetTempChanged);
    _hysteresisController.addListener(_onHysteresisChanged);
    _pwmMinController.addListener(_onPwmMinChanged);
  }

  void _onSetTempChanged() {
    if (_setTempDebounce?.isActive ?? false) _setTempDebounce!.cancel();
    _setTempDebounce = Timer(const Duration(milliseconds: 1000), () {
      final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
      final device = deviceProvider.devices.firstWhere((d) => d.id == widget.deviceId);
      final value = double.tryParse(_setTempController.text);
      if (value != null && value >= 0.0 && value <= 50.0) {
        deviceProvider.updateDeviceSetTemp(device, value);
      } else if (_setTempController.text.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid Set Temp. Range: 0.0-50.0'), backgroundColor: Colors.red),
        );
      }
    });
  }

  void _onHysteresisChanged() {
    if (_hysteresisDebounce?.isActive ?? false) _hysteresisDebounce!.cancel();
    _hysteresisDebounce = Timer(const Duration(milliseconds: 1000), () {
      final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
      final device = deviceProvider.devices.firstWhere((d) => d.id == widget.deviceId);
      final value = double.tryParse(_hysteresisController.text);
      if (value != null && value >= 0.05 && value <= 2.0) {
        deviceProvider.updateDeviceHysteresis(device, value);
      } else if (_hysteresisController.text.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid Hysteresis. Range: 0.05-2.0'), backgroundColor: Colors.red),
        );
      }
    });
  }
  void _onPwmMinChanged() {
    if (_pwmMinDebounce?.isActive ?? false) _pwmMinDebounce!.cancel();
    _pwmMinDebounce = Timer(const Duration(milliseconds: 1000), () {
      final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
      final device = deviceProvider.devices.firstWhere((d) => d.id == widget.deviceId);
      final value = int.tryParse(_pwmMinController.text);
      if (value != null && value >= 0 && value <= 65535) {
        deviceProvider.updateDevicePwmMin(device, value);
      } else if (_pwmMinController.text.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid PWM Min. Range: 0-65535'), backgroundColor: Colors.red),
        );
      }
    });
  }

  @override
  void dispose() {
    _setTempController.removeListener(_onSetTempChanged);
    _hysteresisController.removeListener(_onHysteresisChanged);
    _pwmMinController.removeListener(_onPwmMinChanged);

    _setTempController.dispose();
    _hysteresisController.dispose();
    _pwmMinController.dispose();

    _setTempFocusNode.dispose();
    _hysteresisFocusNode.dispose();
    _pwmMinFocusNode.dispose();

    _setTempDebounce?.cancel();
    _hysteresisDebounce?.cancel();
    _pwmMinDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DeviceProvider>(
      builder: (context, deviceProvider, child) {
        final device = deviceProvider.devices.firstWhere(
              (d) => d.id == widget.deviceId,
          orElse: () => Device(id: widget.deviceId, customName: 'Unknown ORP Device', deviceType: 'ORP'),
        );

        if (!_setTempFocusNode.hasFocus && device.setTemp?.toStringAsFixed(1) != _setTempController.text) {
          _setTempController.text = device.setTemp?.toStringAsFixed(1) ?? '';
        }
        if (!_hysteresisFocusNode.hasFocus && device.hysteresis?.toStringAsFixed(2) != _hysteresisController.text) {
          _hysteresisController.text = device.hysteresis?.toStringAsFixed(2) ?? '';
        }
        if (!_pwmMinFocusNode.hasFocus && device.pwmMin?.toString() != _pwmMinController.text) {
          _pwmMinController.text = device.pwmMin?.toString() ?? '';
        }        return Scaffold(
          appBar: AppBar(
            title: Text('${device.customName} (ORP)'),
            backgroundColor: Colors.blue.shade600,
            actions: [
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
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Device ID: ${device.id}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                _buildOrpInfoCard(device),
                const SizedBox(height: 20),
                _buildOrpControlSection(),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save Settings to Device EEPROM'),
                  onPressed: () {
                    deviceProvider.saveSettingsOnDevice(device);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Save command sent to device.'), duration: Duration(seconds: 1)),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.wifi_tethering_error_rounded, color: Colors.white),
                  label: const Text('Reset WiFi on Device', style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("Confirm WiFi Reset"),
                        content: Text("Are you sure you want to send WiFi reset command to ${device.customName}?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
                          TextButton(
                            onPressed: () {
                              deviceProvider.resetWifiOnDevice(device);
                              Navigator.of(ctx).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('WiFi reset command sent.'), duration: Duration(seconds: 1)),
                              );
                            },
                            child: const Text("Reset WiFi", style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrpInfoCard(Device device) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Status: ${device.isConnected ? "Connected" : "Disconnected"}',
                style: TextStyle(color: device.isConnected ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            // ORP 전용 정보
            _buildInfoRow('ORP Raw:', '${device.orpRaw?.toStringAsFixed(1) ?? "N/A"} mV'),
            _buildInfoRow('ORP Corrected:', '${device.orpCorrected?.toStringAsFixed(1) ?? "N/A"} mV'),
            const Divider(),
            
            // 온도 관련 정보
            _buildInfoRow('Current Temp:', '${device.currentTemp?.toStringAsFixed(2) ?? "N/A"} °C'),
            _buildInfoRow('Set Temp:', '${device.setTemp?.toStringAsFixed(1) ?? "N/A"} °C'),
              // 팬/쿨러 관련 정보
            _buildInfoRow('PWM Value:', '${device.pwmValue ?? "N/A"} (${device.pwmValue != null ? (device.pwmValue! / 65535 * 100).toStringAsFixed(0) : "N/A"}%)'),
            _buildInfoRow('Cooler State:', device.coolerState == null ? "N/A" : (device.coolerState! ? "ON" : "OFF")),
            _buildInfoRow('Hysteresis:', '${device.hysteresis?.toStringAsFixed(2) ?? "N/A"}'),
            _buildInfoRow('PWM Min (0-65535):', '${device.pwmMin ?? "N/A"}'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  Widget _buildOrpControlSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ORP Device Controls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextField(
          controller: _setTempController,
          focusNode: _setTempFocusNode,
          decoration: const InputDecoration(
            labelText: 'Set Temperature (0.0 - 50.0 °C)',
            border: OutlineInputBorder(),
            suffixText: '°C',
            helperText: 'Target temperature for cooling system',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _hysteresisController,
          focusNode: _hysteresisFocusNode,
          decoration: const InputDecoration(
            labelText: 'Hysteresis (0.05 - 2.0)',
            border: OutlineInputBorder(),
            helperText: 'Temperature tolerance for cooler switching',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 10),        TextField(
          controller: _pwmMinController,
          focusNode: _pwmMinFocusNode,
          decoration: const InputDecoration(
            labelText: 'PWM Min (0 - 65535)',
            border: OutlineInputBorder(),
            helperText: 'Minimum PWM value for cooler operation',
          ),
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }
}
