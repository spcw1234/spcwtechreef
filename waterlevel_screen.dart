import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'device_provider.dart';

class WaterLevelScreen extends StatefulWidget {
  final String deviceId;
  const WaterLevelScreen({Key? key, required this.deviceId}) : super(key: key);

  @override
  State<WaterLevelScreen> createState() => _WaterLevelScreenState();
}

class _WaterLevelScreenState extends State<WaterLevelScreen> {
  final TextEditingController _offsetController = TextEditingController();

  @override
  void dispose() {
    _offsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Water Level - ${widget.deviceId.substring(widget.deviceId.length - 6)}'),
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, provider, child) {
          final info = provider.getWaterLevelInfo(widget.deviceId);
          if (info == null) {
            return Center(child: Text('No data for device ${widget.deviceId}'));
          }

          // populate offset controller
          _offsetController.text = (info.offsetCm ?? 0.0).toStringAsFixed(2);

          final distance = info.distanceCm;
          final online = info.online;
          final lastUpdate = info.lastUpdate;

          final history = provider.getWaterLevelHistory(widget.deviceId);

          return Padding(
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

                // Offset control
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        const Text('Offset (cm): '),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _offsetController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final val = double.tryParse(_offsetController.text);
                            if (val != null) {
                              provider.setWaterLevelOffset(widget.deviceId, val);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offset saved')));
                            }
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Graph
                Expanded(
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
          );
        },
      ),
    );
  }
}
