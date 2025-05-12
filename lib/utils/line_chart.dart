import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pandaboat/data/constants.dart';

int? calculateRoundedInterval(List<double> data, int intervals, List<Map<dynamic, int>> rules) {
  if (data.length < 5) return null;

  final rawInterval = (data.last - data.first) / intervals;
  for (var rule in rules) {
    final key = rule.keys.first;
    final value = rule.values.first;

    if (key is num && rawInterval < key) {
      return max((rawInterval / value).round(), 1) * value;
    }
    if (key == 'else') {
      return (rawInterval / value).round() * value;
    }
  }
  return rawInterval.round();
}

Widget buildSimpleLineChart({
  required List<double> xData,
  required List<double> yData,
  bool isDarkMode = true,
  List<double>? yData2,
  Color color = Colors.blueAccent,
  Color color2 = Colors.lightGreen,
}) {
  double minX = 0;
  double maxX = xData.reduce(max);

  double minY = 0;
  double maxY = yData.reduce(max);

  double minY2 = 0;
  double maxY2 = yData2?.reduce(max) ?? 0;

  final spots = List.generate(xData.length, (i) => FlSpot(xData[i], yData[i]));

  // Normalize Y2 to Y-range
  double y2Scale(double y2) {
    if (maxY2 == minY2) return minY; // or (minY + maxY) / 2 if you want to center it
    return minY + ((y2 - minY2) / (maxY2 - minY2)) * (maxY - minY);
  }

  final spots2 =
      yData2 != null
          ? List.generate(xData.length, (i) => FlSpot(xData[i], y2Scale(yData2[i])))
          : null;

  List<Map<dynamic, int>> xRules = [
    {7.5: 5},
    {100: 10},
    {500: 100},
    {'else': 500},
  ];
  int? intervalX = calculateRoundedInterval(xData, 5, xRules);

  List<Map<dynamic, int>> yRules = [
    {5: 1},
    {'else': 5},
  ];
  int? intervalY = calculateRoundedInterval(yData, 10, yRules);
  int? intervalY2 = yData2 != null ? calculateRoundedInterval(yData2, 10, yRules) : null;

  return LineChart(
    LineChartData(
      lineTouchData: LineTouchData(enabled: true),
      gridData: FlGridData(show: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: intervalX?.toDouble(),
            getTitlesWidget:
                (value, _) => Text(value.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: intervalY?.toDouble(),
            getTitlesWidget:
                (value, _) => Text(value.toStringAsFixed(0), style: const TextStyle(fontSize: 10)),
          ),
        ),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            intervalY2 != null
                ? AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    interval: maxY2 == 0 ? null : intervalY2.toDouble() * maxY / maxY2,
                    getTitlesWidget:
                        (value, _) => Text(
                          maxY == 0
                              ? value.toStringAsFixed(0)
                              : (value * maxY2 / maxY).toStringAsFixed(0),
                          style: const TextStyle(fontSize: 10),
                        ),
                  ),
                )
                : AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: isDarkMode ? secondaryColor : Colors.black, width: 1),
      ),
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          color: color,
          barWidth: 2,
          belowBarData: BarAreaData(show: false),
          dotData: FlDotData(show: false),
        ),
        if (spots2 != null)
          LineChartBarData(
            spots: spots2,
            isCurved: true,
            color: color2,
            barWidth: 2,
            belowBarData: BarAreaData(show: false),
            dotData: FlDotData(show: false),
          ),
      ],
    ),
  );
}
