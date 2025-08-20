import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'device.dart';
import 'device_provider.dart';
import 'device_wiring_screen.dart';

class ChillerSettingsScreen extends StatefulWidget {
  final Device device;

  const ChillerSettingsScreen({super.key, required this.device});

  @override
  State<ChillerSettingsScreen> createState() => _ChillerSettingsScreenState();
}

class _ChillerSettingsScreenState extends State<ChillerSettingsScreen> {
  late TextEditingController _setTempController;
  late TextEditingController _hysteresisController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Try to obtain the latest device state from DeviceProvider so
    // the screen shows the most recent setTemp/hysteresis values.
    var initialSetTemp = widget.device.setTemp;
    var initialHysteresis = widget.device.hysteresis;

    print('ChillerSettingsScreen initState: widget.device.setTemp=${widget.device.setTemp}, hysteresis=${widget.device.hysteresis}');

    try {
      final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
      final latest = deviceProvider.devices.firstWhere((d) => d.id == widget.device.id, orElse: () => widget.device);
      print('ChillerSettingsScreen initState: latest device setTemp=${latest.setTemp}, hysteresis=${latest.hysteresis}');
      initialSetTemp = latest.setTemp ?? initialSetTemp;
      initialHysteresis = latest.hysteresis ?? initialHysteresis;
    } catch (_) {
      // ignore and fall back to widget.device values
      print('ChillerSettingsScreen initState: failed to get latest device from provider');
    }

    print('ChillerSettingsScreen initState: final initialSetTemp=$initialSetTemp, initialHysteresis=$initialHysteresis');

    _setTempController = TextEditingController(
      text: (initialSetTemp != null) ? initialSetTemp.toStringAsFixed(1) : '26.0',
    );
    _hysteresisController = TextEditingController(
      text: (initialHysteresis != null) ? initialHysteresis.toStringAsFixed(2) : '0.10',
    );
  }

  @override
  void dispose() {
    _setTempController.dispose();
    _hysteresisController.dispose();
    super.dispose();
  }

  void _saveSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final double setTemp = double.parse(_setTempController.text);
      final double hysteresis = double.parse(_hysteresisController.text);

      if (setTemp < 0.0 || setTemp > 50.0) {
        _showErrorDialog('Set temperature must be between 0.0°C and 50.0°C');
        return;
      }

      if (hysteresis < 0.05 || hysteresis > 2.0) {
        _showErrorDialog('Hysteresis must be between 0.05 and 2.0');
        return;
      }

      final deviceProvider = Provider.of<DeviceProvider>(context, listen: false);
      
      final message = {
        'settemp': setTemp,
        'hysteresis': hysteresis,
        'save': true,
      };

      await deviceProvider.publishToDevice(widget.device.id, 'CHIL', 'con', message);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings sent successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('Invalid number format: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connection Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  widget.device.isConnected ? Icons.check_circle : Icons.error,
                  color: widget.device.isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.device.isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    color: widget.device.isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStatus() {
    if (!widget.device.isConnected) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (widget.device.currentTemp != null) ...[
              Row(
                children: [
                  const Icon(Icons.thermostat, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Current Temperature: ${widget.device.currentTemp!.toStringAsFixed(2)}°C',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (widget.device.setTemp != null) ...[
              Row(
                children: [
                  const Icon(Icons.adjust, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    'Set Temperature: ${widget.device.setTemp!.toStringAsFixed(1)}°C',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (widget.device.chillerState != null) ...[
              Row(
                children: [
                  Icon(
                    widget.device.chillerState! ? Icons.ac_unit : Icons.power_off,
                    color: widget.device.chillerState! ? Colors.cyan : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Chiller: ${widget.device.chillerState! ? "ON" : "OFF"}',
                    style: TextStyle(
                      fontSize: 16,
                      color: widget.device.chillerState! ? Colors.cyan : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (widget.device.hysteresis != null) ...[
              Row(
                children: [
                  const Icon(Icons.tune, color: Colors.purple),
                  const SizedBox(width: 8),
                  Text(
                    'Hysteresis: ${widget.device.hysteresis!.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chiller Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _setTempController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Set Temperature (°C)',
                helperText: 'Range: 0.0 - 50.0°C',
                prefixIcon: Icon(Icons.thermostat),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hysteresisController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Hysteresis',
                helperText: 'Range: 0.05 - 2.0',
                prefixIcon: Icon(Icons.tune),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveSettings,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWiringSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Temperature Source',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure where this chiller gets temperature readings from.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DeviceWiringScreen(device: widget.device),
                    ),
                  );
                },
                icon: const Icon(Icons.cable),
                label: const Text('Configure Device Wiring'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.device.customName} Settings'),
        backgroundColor: Colors.cyan,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildConnectionStatus(),
            const SizedBox(height: 16),
            _buildCurrentStatus(),
            const SizedBox(height: 16),
            _buildWiringSection(),
            const SizedBox(height: 16),
            _buildSettingsForm(),
          ],
        ),
      ),
    );
  }
}
