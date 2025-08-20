library fl_chart;

import 'package:flutter/widgets.dart';

// 최소 스텁 구현: 실제 차트 대신 단순 Container 렌더링.
// 프로젝트가 빌드되도록 타입/필드만 맞춘다.

class FlSpot {
  final double x;
  final double y;
  const FlSpot(this.x, this.y);
}

class FlGridData {
  final bool show;
  final bool drawVerticalLine;
  final double? horizontalInterval;
  final double? verticalInterval;
  const FlGridData({
    this.show = true,
    this.drawVerticalLine = true,
    this.horizontalInterval,
    this.verticalInterval,
  });
}

class SideTitles {
  final bool showTitles;
  final double? reservedSize;
  final double? interval;
  final Widget Function(double, TitleMeta)? getTitlesWidget;
  const SideTitles({
    this.showTitles = true,
    this.reservedSize,
    this.interval,
    this.getTitlesWidget,
  });
}

class TitleMeta {}

class AxisTitles {
  final SideTitles sideTitles;
  const AxisTitles({required this.sideTitles});
}

class FlTitlesData {
  final bool show;
  final AxisTitles? rightTitles;
  final AxisTitles? topTitles;
  final AxisTitles? bottomTitles;
  final AxisTitles? leftTitles;
  const FlTitlesData({
    this.show = true,
    this.rightTitles,
    this.topTitles,
    this.bottomTitles,
    this.leftTitles,
  });
}

class FlBorderData {
  final bool show;
  const FlBorderData({this.show = true});
}

class FlDotData {
  final bool show;
  final FlDotPainter Function(FlSpot, double, LineChartBarData, int)? getDotPainter;
  const FlDotData({this.show = true, this.getDotPainter});
}

abstract class FlDotPainter {}

class FlDotCirclePainter extends FlDotPainter {
  final double radius;
  final Color color;
  final double strokeWidth;
  FlDotCirclePainter({required this.radius, required this.color, required this.strokeWidth});
}

class BarAreaData {
  final bool show;
  const BarAreaData({this.show = true});
}

class LineChartBarData {
  final List<FlSpot> spots;
  final bool isCurved;
  final Color? color;
  final double barWidth;
  final bool isStrokeCapRound;
  final FlDotData dotData;
  final BarAreaData belowBarData;
  final List<int>? dashArray;
  final List<int>? showingIndicators;
  const LineChartBarData({
    required this.spots,
    this.isCurved = false,
    this.color,
    this.barWidth = 1,
    this.isStrokeCapRound = false,
    this.dotData = const FlDotData(),
    this.belowBarData = const BarAreaData(),
    this.dashArray,
    this.showingIndicators,
  });
}

class LineChartData {
  final FlGridData gridData;
  final FlTitlesData titlesData;
  final FlBorderData borderData;
  final double? minX;
  final double? maxX;
  final double? minY;
  final double? maxY;
  final List<LineChartBarData> lineBarsData;
  const LineChartData({
    this.gridData = const FlGridData(),
    this.titlesData = const FlTitlesData(),
    this.borderData = const FlBorderData(),
    this.minX,
    this.maxX,
    this.minY,
    this.maxY,
    this.lineBarsData = const [],
  });
}

class LineChart extends StatelessWidget {
  final LineChartData data;
  const LineChart(this.data, {super.key});
  @override
  Widget build(BuildContext context) {
    // 단순 placeholder 위젯: 실제 차트 대신.
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCCCCCC)),
      ),
      child: const Center(child: Text('LineChart (stub)')),
    );
  }
}
