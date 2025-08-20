import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'device.dart';
import 'temperature_history_service.dart';

/**
 * 온도/ORP 히스토리 그래프 화면 (24시간 보기)
 */
class TemperatureGraphScreen extends StatefulWidget {
  final Device device;

  const TemperatureGraphScreen({
    Key? key,
    required this.device,
  }) : super(key: key);

  @override
  State<TemperatureGraphScreen> createState() => _TemperatureGraphScreenState();
}

class _TemperatureGraphScreenState extends State<TemperatureGraphScreen> {
  final TemperatureHistoryService _historyService = TemperatureHistoryService();
  List<TemperatureRecord> _data = [];
  bool _isLoading = true;

  /// 현재 장치가 온도 장치인지 확인
  bool get _isTemperatureDevice => widget.device.deviceType == 'TEMP';
  
  /// 현재 장치가 ORP 장치인지 확인
  bool get _isOrpDevice => widget.device.deviceType == 'ORP';

  @override
  void initState() {
    super.initState();
    _loadData();
  }
  /**
   * 24시간 데이터 로드
   */
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final data = await _historyService.getTodayTemperatureData(widget.device.id);

      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      print('데이터 로드 오류: $e');
      setState(() => _isLoading = false);
    }
  }  @override
  Widget build(BuildContext context) {
    final String title = _isOrpDevice 
        ? '${widget.device.customName} 24시간 ORP 변화'
        : '${widget.device.customName} 24시간 온도 변화';
        
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: '새로고침',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isOrpDevice 
              ? _buildOrpView()
              : _buildTemperatureView(),
    );
  }
  /**
   * 24시간 온도 그래프 빌드
   */
  Widget _buildTemperatureView() {
    if (_data.isEmpty) {
      return const Center(
        child: Text(
          '최근 24시간 온도 데이터가 없습니다.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return Column(
      children: [
        // 헤더 정보
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Column(
            children: [
              Text(
                '최근 24시간 온도 변화',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '데이터 포인트: ${_data.length}개',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        
        // 그래프
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LineChart(
              _buildTemperatureLineChartData(),
            ),
          ),
        ),
        
        // 범례
        _buildTemperatureLegend(),
      ],
    );
  }
  /**
   * 24시간 ORP 그래프 빌드 (온도 + ORP 통합)
   */
  Widget _buildOrpView() {
    if (_data.isEmpty) {
      return const Center(
        child: Text(
          '최근 24시간 ORP 데이터가 없습니다.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return Column(
      children: [
        // 헤더 정보
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: Column(
            children: [
              Text(
                '최근 24시간 온도 & ORP 변화',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '데이터 포인트: ${_data.length}개',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        
        // 그래프
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LineChart(
              _buildOrpCombinedLineChartData(),
            ),
          ),
        ),
        
        // 범례
        _buildOrpCombinedLegend(),
      ],
    );
  }
  /**
   * 24시간 온도 데이터를 위한 LineChart 데이터 생성
   */
  LineChartData _buildTemperatureLineChartData() {
    final now = DateTime.now();
    final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));
    
    // 현재 온도 데이터 포인트
    List<FlSpot> currentTempSpots = [];
    // 쿨러 ON 구간 (빨간색으로 표시할 부분)
    List<FlSpot> coolerOnSpots = [];
    
    // 설정 온도는 전체 24시간에 걸쳐 표시 (첫 번째와 마지막 설정온도 사용)
    List<FlSpot> setTempSpots = [];
    double? setTempValue;

    for (int i = 0; i < _data.length; i++) {
      final record = _data[i];
      final minutesSinceStart = record.timestamp.difference(twentyFourHoursAgo).inMinutes.toDouble();
      final hoursSinceStart = minutesSinceStart / 60.0; // 분을 시간으로 변환하여 소수점 유지
      
      currentTempSpots.add(FlSpot(hoursSinceStart, record.currentTemp));
      
      // 설정온도 값 저장 (가장 최근 값 사용)
      setTempValue = record.setTemp;
      
      // 쿨러가 켜져있을 때의 온도 포인트
      if (record.coolerState) {
        coolerOnSpots.add(FlSpot(hoursSinceStart, record.currentTemp));
      }
    }
    
    // 설정온도 라인을 전체 24시간에 걸쳐 표시
    if (setTempValue != null) {
      setTempSpots = [
        FlSpot(0, setTempValue),  // 시작점 (0시간)
        FlSpot(24, setTempValue), // 끝점 (24시간)
      ];
    }

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 2, // 2도 간격으로 격자선
        verticalInterval: 4, // 4시간 간격
      ),
      titlesData: FlTitlesData(
        show: true,
  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 4, // 4시간 간격
            getTitlesWidget: (value, meta) {
              final hour = value.toInt();
              if (hour >= 0 && hour <= 24) {
        return Text('${hour}h',
          style: const TextStyle(fontSize: 10));
              }
              return Text('');
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 2, // 2도 간격으로 Y축 라벨 표시
            getTitlesWidget: (value, meta) {
        return Text('${value.toInt()}°C',
          style: const TextStyle(fontSize: 10));
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: true),
      minX: 0,
      maxX: 24, // 24시간
      minY: 20, // 최소 온도 20°C
      maxY: 30, // 최대 온도 30°C
      lineBarsData: [        // 현재 온도 라인 (파란색)
        LineChartBarData(
          spots: currentTempSpots,
          isCurved: true,
          color: Colors.blue,
          barWidth: 1,
          isStrokeCapRound: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),
        // 설정 온도 라인 (회색 점선) - 전체 24시간에 걸쳐 표시
        if (setTempSpots.isNotEmpty)
          LineChartBarData(
            spots: setTempSpots,
            isCurved: false,
            color: Colors.grey,
            barWidth: 0.5,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
            dashArray: [5, 5], // 점선
          ),
        // 쿨러 ON 포인트 (빨간색)
        if (coolerOnSpots.isNotEmpty)
          LineChartBarData(
            spots: coolerOnSpots,
            isCurved: false,
            color: Colors.red,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 3,
                color: Colors.red,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(show: false),
            showingIndicators: [],
          ),
      ],
    );
  }
  /**
   * 24시간 ORP+온도 통합 데이터를 위한 LineChart 데이터 생성
   */  LineChartData _buildOrpCombinedLineChartData() {
    final now = DateTime.now();
    final twentyFourHoursAgo = now.subtract(const Duration(hours: 24));
    
    // 온도 관련 데이터 포인트
    List<FlSpot> currentTempSpots = [];
    List<FlSpot> coolerOnSpots = [];
    
    // ORP 데이터 포인트 (Corrected만 사용)
    List<FlSpot> orpCorrectedSpots = [];
    
    // 설정온도는 전체 24시간에 걸쳐 표시 (첫 번째와 마지막 설정온도 사용)
    List<FlSpot> setTempSpots = [];
    double? setTempValue;

    for (int i = 0; i < _data.length; i++) {
      final record = _data[i];
      final minutesSinceStart = record.timestamp.difference(twentyFourHoursAgo).inMinutes.toDouble();
      final hoursSinceStart = minutesSinceStart / 60.0;
      
      // 온도 데이터 추가
      currentTempSpots.add(FlSpot(hoursSinceStart, record.currentTemp));
      
      // 설정온도 값 저장 (가장 최근 값 사용)
      setTempValue = record.setTemp;
      
      // 쿨러가 켜져있을 때의 온도 포인트
      if (record.coolerState) {
        coolerOnSpots.add(FlSpot(hoursSinceStart, record.currentTemp));
      }
      
      // ORP Corrected 데이터 추가 (값이 있는 경우만)
      if (record.orpCorrected != null) {
        // ORP 값을 온도 범위에 맞게 스케일링 (예: 600mV -> 26도 정도로)
        double scaledOrp = _scaleOrpToTemperatureRange(record.orpCorrected!);
        orpCorrectedSpots.add(FlSpot(hoursSinceStart, scaledOrp));
      }
    }
    
    // 설정온도 라인을 전체 24시간에 걸쳐 표시
    if (setTempValue != null) {
      setTempSpots = [
        FlSpot(0, setTempValue),  // 시작점 (0시간)
        FlSpot(24, setTempValue), // 끝점 (24시간)
      ];
    }

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: 2, // 2도 간격으로 격자선
        verticalInterval: 4, // 4시간 간격
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 50,
            interval: 2,
            getTitlesWidget: (value, meta) {
              // 오른쪽 축에 ORP 값 표시
              double orpValue = _scaleTemperatureToOrpRange(value);
              return Text('${orpValue.toInt()}mV',
                  style: const TextStyle(fontSize: 10, color: Colors.green));
            },
          ),
        ),
  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: 4, // 4시간 간격
            getTitlesWidget: (value, meta) {
              final hour = value.toInt();
              if (hour >= 0 && hour <= 24) {
        return Text('${hour}h',
          style: const TextStyle(fontSize: 10));
              }
              return Text('');
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: 2, // 2도 간격으로 Y축 라벨 표시
            getTitlesWidget: (value, meta) {
        return Text('${value.toInt()}°C',
          style: const TextStyle(fontSize: 10, color: Colors.blue));
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: true),
      minX: 0,
      maxX: 24, // 24시간
      minY: 20, // 최소 온도 20°C
      maxY: 30, // 최대 온도 30°C
      lineBarsData: [        // 현재 온도 라인 (파란색)
        LineChartBarData(
          spots: currentTempSpots,
          isCurved: true,
          color: Colors.blue,
          barWidth: 1,
          isStrokeCapRound: true,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(show: false),
        ),        // 설정 온도 라인 (회색 점선) - 전체 24시간에 걸쳐 표시
        if (setTempSpots.isNotEmpty)
          LineChartBarData(
            spots: setTempSpots,
            isCurved: false,
            color: Colors.grey,
            barWidth: 0.5,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
            dashArray: [5, 5], // 점선
          ),
        // 쿨러 ON 포인트 (빨간색)
        if (coolerOnSpots.isNotEmpty)
          LineChartBarData(
            spots: coolerOnSpots,
            isCurved: false,
            color: Colors.red,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                radius: 3,
                color: Colors.red,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(show: false),
            showingIndicators: [],
          ),        // ORP Corrected 라인 (녹색)
        if (orpCorrectedSpots.isNotEmpty)
          LineChartBarData(
            spots: orpCorrectedSpots,
            isCurved: true,
            color: Colors.green,
            barWidth: 1.5,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
      ],
    );
  }

  /**
   * ORP 값을 온도 범위(20-30)에 맞게 스케일링
   * ORP 범위 0-800mV를 온도 범위 20-30°C로 변환
   */
  double _scaleOrpToTemperatureRange(double orpValue) {
    // ORP 값을 0-800 범위에서 20-30 범위로 선형 변환
    double clampedOrp = orpValue.clamp(0, 800);
    return 20 + (clampedOrp / 800) * 10;
  }

  /**
   * 온도 값을 ORP 범위로 역변환 (라벨 표시용)
   */
  double _scaleTemperatureToOrpRange(double tempValue) {
    // 온도 값 20-30을 ORP 값 0-800으로 역변환
    double clampedTemp = tempValue.clamp(20, 30);
    return (clampedTemp - 20) / 10 * 800;
  }

  /**
   * 온도 그래프 범례 빌드
   */
  Widget _buildTemperatureLegend() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLegendItem(Colors.blue, '현재 온도'),
          _buildLegendItem(Colors.grey, '설정 온도'),
          _buildLegendItem(Colors.red, '쿨러 ON'),
        ],
      ),
    );
  }
  /**
   * ORP 통합 그래프 범례 빌드
   */
  Widget _buildOrpCombinedLegend() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildLegendItem(Colors.blue, '현재 온도'),
          _buildLegendItem(Colors.grey, '설정 온도'),
          _buildLegendItem(Colors.red, '쿨러 ON'),
          _buildLegendItem(Colors.green, 'ORP'),
        ],
      ),
    );
  }

  /**
   * 범례 아이템 빌드
   */
  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 3,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
