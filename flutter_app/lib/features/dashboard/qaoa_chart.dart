import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// QAOA energy curve (CVaR α=0.25). Pass live points from plan benchmark when available.
class QaoaConvergenceChart extends StatelessWidget {
  const QaoaConvergenceChart({super.key, this.points = demoPoints});

  final List<FlSpot> points;

  static const demoPoints = [
    FlSpot(0, 4.2),
    FlSpot(1, 3.6),
    FlSpot(2, 2.9),
    FlSpot(3, 2.1),
    FlSpot(4, 1.4),
    FlSpot(5, 0.95),
    FlSpot(6, 0.72),
    FlSpot(7, 0.55),
    FlSpot(8, 0.48),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QAOA Energy Minimization (CVaR α=0.25)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 5,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(color: AppColors.clay.withValues(alpha: 0.25), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: 2,
                    getTitlesWidget: (v, _) => Text('p${v.toInt()}', style: const TextStyle(fontSize: 12, color: AppColors.soilBrown)),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    interval: 1,
                    getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0), style: const TextStyle(fontSize: 12, color: AppColors.soilBrown)),
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: points,
                  isCurved: true,
                  color: AppColors.deepGreen,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(show: true, color: AppColors.deepGreen.withValues(alpha: 0.12)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
