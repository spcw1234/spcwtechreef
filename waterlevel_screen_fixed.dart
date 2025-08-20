import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'device_provider.dart';
import 'package:fl_chart/fl_chart.dart';

class WaterLevelScreen extends StatefulWidget {
  final String deviceId;

  const WaterLevelScreen({Key? key, required this.deviceId}) : super(key: key);

  @override
  State<WaterLevelScreen> createState() => _WaterLevelScreenState();
}

class _WaterLevelScreenState extends State<WaterLevelScreen> {
  late TextEditingController _offsetController;
  late FocusNode _offsetFocus;
  bool _isOffsetEditing = false;

  @override
  void initState() {
    super.initState();
    _offsetController = TextEditingController();
    _offsetFocus = FocusNode();

    _offsetFocus.addListener(() {
      if (!_offsetFocus.hasFocus) {
        _isOffsetEditing = false;
      }
    });
  }

  @override
  void dispose() {
    _offsetController.dispose();
    _offsetFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Water Level Monitor'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, provider, child) {
          final info = provider.getWaterLevelInfo(widget.deviceId);
          if (info == null) {
            return const Center(child: Text('Device not found or no data available'));
          }

          // populate offset controller only when not editing and when value actually changed
          final currentOffset = info.offsetCm ?? 0.0;
          final currentText = currentOffset.toStringAsFixed(2);
          if (!_isOffsetEditing && _offsetController.text != currentText) {
            _offsetController.text = currentText;
          }

          final distance = info.distanceCm;
          final online = info.online;
          final lastUpdate = info.lastUpdate;

          final history = provider.getWaterLevelHistory(widget.deviceId);

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: online ? Colors.green : Colors.red,
                        child: Icon(Icons.water_drop, color: Colors.white),
                      ),
                      title: Text(online ? 'Online' : 'Offline'),
                      subtitle: Text(lastUpdate != null ? 'Last: ${lastUpdate.toLocal().toString()}' : 'No recent data'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Current Reading Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Current Reading', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          if (distance != null) ...[
                            Text('Raw Distance: ${distance.toStringAsFixed(2)} cm', style: const TextStyle(fontSize: 16)),
                            Text('Adjusted (with offset): ${(distance + currentOffset).toStringAsFixed(2)} cm', 
                                 style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                          ] else
                            const Text('No data available', style: TextStyle(fontSize: 16, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Offset Configuration Card
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Offset Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _offsetController,
                                  focusNode: _offsetFocus,
                                  decoration: const InputDecoration(
                                    labelText: 'Offset (cm)',
                                    helperText: 'Positive to increase, negative to decrease reading',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'^-?[0-9]*[.,]?[0-9]*')),
                                  ],
                                  onTap: () {
                                    _isOffsetEditing = true;
                                  },
                                  onChanged: (value) {
                                    _isOffsetEditing = true;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () {
                                  print('WaterLevelScreen: Save button pressed');
                                  
                                  String text = _offsetController.text.trim();
                                  if (text.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please enter an offset value')),
                                    );
                                    return;
                                  }

                                  // Replace comma with dot for parsing
                                  text = text.replaceAll(',', '.');
                                  
                                  try {
                                    final offset = double.parse(text);
                                    print('WaterLevelScreen: Saving offset $offset for deviceId ${widget.deviceId}');
                                    
                                    provider.setWaterLevelOffset(widget.deviceId, offset);
                                    _isOffsetEditing = false;
                                    
                                    // Update controller immediately to show saved value
                                    _offsetController.text = offset.toStringAsFixed(2);
                                    
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Offset saved: ${offset.toStringAsFixed(2)} cm')),
                                    );
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Invalid number format. Please enter a valid number.')),
                                    );
                                  }
                                },
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Graph
                  Container(
                    height: 300, // Fixed height to prevent overflow
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: history.isEmpty
                            ? const Center(child: Text('No history yet'))
                            : LineChart(
                                LineChartData(
                                  gridData: FlGridData(show: true),
                                  titlesData: FlTitlesData(show: false),
                                  borderData: FlBorderData(show: true),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: history
                                          .asMap()
                                          .entries
                                          .map((e) => FlSpot(e.key.toDouble(), e.value.valueCm))
                                          .toList(),
                                      isCurved: true,
                                      color: Colors.blue,
                                      barWidth: 2,
                                      dotData: FlDotData(show: false),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      provider.requestReconnect();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Requested refresh')));
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh / Reconnect'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
