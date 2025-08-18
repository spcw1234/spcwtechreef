import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'device_provider.dart';

class DoseSettingsScreen extends StatefulWidget {
  final String deviceId;

  const DoseSettingsScreen({super.key, required this.deviceId});

  @override
  State<DoseSettingsScreen> createState() => _DoseSettingsScreenState();
}

class _DoseSettingsScreenState extends State<DoseSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  int _pump = 1;
  int _hour = 8;
  int _minute = 0;
  int _durationMs = 1000;
  int _intervalDays = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('도징 펌프 제어'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, provider, child) {
          final info = provider.getDoseInfo(widget.deviceId);
          if (info == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('DOSE 정보 없음', style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildConnectionCard(info),
                const SizedBox(height: 16),
                _buildPumpControlCard(info, provider),
                const SizedBox(height: 16),
                _buildScheduleCard(info, provider),
                const SizedBox(height: 16),
                _buildLogCard(info.lastLog ?? '로그 없음'),
              ],
            ),
          );
        },
      ),
    );
  }

  // 연결 상태 카드
  Widget _buildConnectionCard(DosingPumpInfo info) {
    final isOnline = info.online;
    final lastHeartbeat = info.lastHeartbeat;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: isOnline 
                ? [Colors.green[400]!, Colors.green[600]!]
                : [Colors.red[400]!, Colors.red[600]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                isOnline ? Icons.favorite : Icons.heart_broken,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOnline ? '연결됨' : '연결 끊김',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (lastHeartbeat != null)
                      Text(
                        '마지막 연결: ${_formatTime(lastHeartbeat)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 펌프 제어 카드
  Widget _buildPumpControlCard(DosingPumpInfo info, DeviceProvider provider) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.water_drop, color: Colors.blue[700], size: 28),
                const SizedBox(width: 12),
                const Text(
                  '펌프 제어',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _buildPumpController(1, info.pump1Name, info.pump1On, provider)),
                const SizedBox(width: 16),
                Expanded(child: _buildPumpController(2, info.pump2Name, info.pump2On, provider)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 개별 펌프 컨트롤러
  Widget _buildPumpController(int pumpNumber, String pumpName, bool isOn, DeviceProvider provider) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        color: Colors.grey[50],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    pumpName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showEditPumpNameDialog(pumpNumber, pumpName, provider),
                  color: Colors.grey[600],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  isOn ? Icons.power : Icons.power_off,
                  color: isOn ? Colors.green : Colors.grey,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  isOn ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isOn ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isOn 
                        ? () => provider.dosePumpOff(widget.deviceId, pumpNumber)
                        : () => provider.dosePumpOn(widget.deviceId, pumpNumber),
                    icon: Icon(isOn ? Icons.stop : Icons.play_arrow),
                    label: Text(isOn ? 'OFF' : 'ON'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isOn ? Colors.red[400] : Colors.green[400],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showRunDialog(pumpNumber, pumpName, provider),
                icon: const Icon(Icons.timer),
                label: const Text('시간 실행'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 스케줄 카드
  Widget _buildScheduleCard(DosingPumpInfo info, DeviceProvider provider) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, color: Colors.orange[700], size: 28),
                const SizedBox(width: 12),
                const Text(
                  '스케줄 관리',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildScheduleForm(provider),
            const SizedBox(height: 20),
            _buildScheduleList(info, provider),
          ],
        ),
      ),
    );
  }

  // 스케줄 추가 폼
  Widget _buildScheduleForm(DeviceProvider provider) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.blue[50],
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '새 스케줄 추가',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _pump,
                      decoration: const InputDecoration(
                        labelText: '펌프 선택',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      items: [
                        DropdownMenuItem(value: 1, child: Text('펌프 1')),
                        DropdownMenuItem(value: 2, child: Text('펌프 2')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _pump = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: _hour.toString(),
                            decoration: const InputDecoration(
                              labelText: '시간',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final parsed = int.tryParse(value);
                              if (parsed != null && parsed >= 0 && parsed <= 23) {
                                _hour = parsed;
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: _minute.toString(),
                            decoration: const InputDecoration(
                              labelText: '분',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              final parsed = int.tryParse(value);
                              if (parsed != null && parsed >= 0 && parsed <= 59) {
                                _minute = parsed;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: (_durationMs / 1000).toString(),
                      decoration: const InputDecoration(
                        labelText: '실행 시간 (초)',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final parsed = double.tryParse(value);
                        if (parsed != null && parsed > 0) {
                          _durationMs = (parsed * 1000).round();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _intervalDays.toString(),
                      decoration: const InputDecoration(
                        labelText: '간격 (일)',
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null && parsed > 0) {
                          _intervalDays = parsed;
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    provider.addDoseSchedule(
                      widget.deviceId,
                      pump: _pump,
                      hour: _hour,
                      minute: _minute,
                      durationMs: _durationMs,
                      intervalDays: _intervalDays,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('스케줄이 추가되었습니다')),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('스케줄 추가'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 스케줄 목록
  Widget _buildScheduleList(DosingPumpInfo info, DeviceProvider provider) {
    final schedules = <Widget>[];
    
    info.schedules.forEach((pumpKey, scheduleList) {
      if (scheduleList is List) {
        for (final schedule in scheduleList) {
          if (schedule is List && schedule.length >= 4) {
            final pumpNumber = int.tryParse(pumpKey) ?? 1;
            final pumpName = pumpNumber == 1 ? info.pump1Name : info.pump2Name;
            final hour = schedule[0] as int;
            final minute = schedule[1] as int;
            final durationMs = schedule[2] as int;
            final intervalDays = schedule[3] as int;
            
            schedules.add(_buildScheduleItem(
              pumpName, pumpNumber, hour, minute, durationMs, intervalDays, provider,
            ));
          }
        }
      }
    });

    if (schedules.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[100],
        ),
        child: const Center(
          child: Text(
            '등록된 스케줄이 없습니다',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '등록된 스케줄',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ...schedules,
      ],
    );
  }

  // 개별 스케줄 아이템
  Widget _buildScheduleItem(
    String pumpName, int pumpNumber, int hour, int minute, 
    int durationMs, int intervalDays, DeviceProvider provider,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue[100],
          child: Icon(Icons.schedule, color: Colors.blue[700]),
        ),
        title: Text(
          '$pumpName - ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${(durationMs / 1000).toStringAsFixed(1)}초 실행, ${intervalDays}일 간격',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _showEditScheduleDialog(
                pumpNumber, hour, minute, durationMs, intervalDays, provider,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _showDeleteScheduleDialog(
                pumpName, pumpNumber, hour, minute, provider,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 로그 카드
  Widget _buildLogCard(String log) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.article, color: Colors.green[700], size: 28),
                const SizedBox(width: 12),
                const Text(
                  '최근 로그',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[900],
              ),
              child: Text(
                log,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.green,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 헬퍼 메서드들
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) {
      return '방금 전';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}시간 전';
    } else {
      return '${diff.inDays}일 전';
    }
  }

  // 펌프 이름 수정 다이얼로그
  void _showEditPumpNameDialog(int pumpNumber, String currentName, DeviceProvider provider) {
    final controller = TextEditingController(text: currentName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('펌프 $pumpNumber 이름 변경'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '펌프 이름',
            border: OutlineInputBorder(),
          ),
          maxLength: 20,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                provider.updatePumpName(widget.deviceId, pumpNumber, controller.text.trim());
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('펌프 이름이 "${controller.text.trim()}"로 변경되었습니다')),
                );
              }
            },
            child: const Text('변경'),
          ),
        ],
      ),
    );
  }

  // 시간 실행 다이얼로그
  void _showRunDialog(int pumpNumber, String pumpName, DeviceProvider provider) {
    int seconds = 5;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('$pumpName 시간 실행'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('실행 시간: $seconds초'),
              Slider(
                value: seconds.toDouble(),
                min: 1,
                max: 60,
                divisions: 59,
                label: '${seconds}초',
                onChanged: (value) {
                  setState(() => seconds = value.round());
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                provider.dosePumpRun(widget.deviceId, pumpNumber, seconds * 1000);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$pumpName를 ${seconds}초 동안 실행합니다')),
                );
              },
              child: const Text('실행'),
            ),
          ],
        ),
      ),
    );
  }

  // 스케줄 수정 다이얼로그
  void _showEditScheduleDialog(
    int pumpNumber, int currentHour, int currentMinute, 
    int currentDurationMs, int currentIntervalDays, DeviceProvider provider,
  ) {
    int hour = currentHour;
    int minute = currentMinute;
    int durationMs = currentDurationMs;
    int intervalDays = currentIntervalDays;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('스케줄 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: hour.toString(),
                        decoration: const InputDecoration(
                          labelText: '시간',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final parsed = int.tryParse(value);
                          if (parsed != null && parsed >= 0 && parsed <= 23) {
                            hour = parsed;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: minute.toString(),
                        decoration: const InputDecoration(
                          labelText: '분',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          final parsed = int.tryParse(value);
                          if (parsed != null && parsed >= 0 && parsed <= 59) {
                            minute = parsed;
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: (durationMs / 1000).toString(),
                  decoration: const InputDecoration(
                    labelText: '실행 시간 (초)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final parsed = double.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      durationMs = (parsed * 1000).round();
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: intervalDays.toString(),
                  decoration: const InputDecoration(
                    labelText: '간격 (일)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      intervalDays = parsed;
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                // 기존 스케줄 삭제
                provider.deleteDoseSchedule(
                  widget.deviceId,
                  pump: pumpNumber,
                  hour: currentHour,
                  minute: currentMinute,
                );
                // 새 스케줄 추가
                provider.addDoseSchedule(
                  widget.deviceId,
                  pump: pumpNumber,
                  hour: hour,
                  minute: minute,
                  durationMs: durationMs,
                  intervalDays: intervalDays,
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('스케줄이 수정되었습니다')),
                );
              },
              child: const Text('수정'),
            ),
          ],
        ),
      ),
    );
  }

  // 스케줄 삭제 확인 다이얼로그
  void _showDeleteScheduleDialog(
    String pumpName, int pumpNumber, int hour, int minute, DeviceProvider provider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('스케줄 삭제'),
        content: Text('$pumpName의 ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} 스케줄을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.deleteDoseSchedule(
                widget.deviceId,
                pump: pumpNumber,
                hour: hour,
                minute: minute,
              );
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('스케줄이 삭제되었습니다')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
