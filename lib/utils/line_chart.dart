import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pandaboat/data/constants.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

int? calculateRoundedInterval(List<double> data, double rawInterval, List<Map<dynamic, int>> rules) {
  if (data.length < 5) return null;

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
  String xLabel = '',
  String yLabel = '',
  String yLabel2 = '',
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

  final spots = List.generate(xData.length, (i) => ChartData(xData[i], yData[i]));
  final spots2 =
      yData2 != null ? List.generate(xData.length, (i) => ChartData(xData[i], yData2[i])) : null;

  List<Map<dynamic, int>> xRules = [
    {7.5: 5},
    {100: 10},
    {500: 100},
    {'else': 500},
  ];
  int? intervalX = calculateRoundedInterval(xData, maxX/5, xRules);

  List<Map<dynamic, int>> yRules = [
    {5: 1},
    {'else': 5},
  ];
  int? intervalY = calculateRoundedInterval(yData, maxY/10, yRules);
  int? intervalY2 = yData2 != null ? calculateRoundedInterval(yData2, maxY2/10, yRules) : null;

  return SfCartesianChart(
    zoomPanBehavior: ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      zoomMode: ZoomMode.xy,
      maximumZoomLevel: 0.05,
    ),
    series: [
      LineSeries<ChartData, double>(
        animationDuration: 0,
        dataSource: spots,
        xValueMapper: (ChartData data, _) => data.x,
        yValueMapper: (ChartData data, _) => data.y,
        color: color,
        width: 2,
        markerSettings: MarkerSettings(
          isVisible: true,
          width: 2.5,
          height: 2.5,
          color: color,
          shape: DataMarkerType.circle,
        ),
      ),
      if (spots2 != null)
        LineSeries<ChartData, double>(
          yAxisName: 'secondaryYAxis',
          animationDuration: 0,
          dataSource: spots2,
          xValueMapper: (ChartData data, _) => data.x,
          yValueMapper: (ChartData data, _) => data.y,
          color: color2,
          width: 2,
          markerSettings: MarkerSettings(
            isVisible: true,
            width: 2.5,
            height: 2.5,
            color: color2,
            shape: DataMarkerType.circle,
          ),
        ),
    ],
    primaryXAxis: NumericAxis(
      minimum: minX,
      maximum: maxX,
      interval: intervalX?.toDouble(),
      labelFormat: '{value}',
      title: AxisTitle(text: xLabel),
    ),
    primaryYAxis: NumericAxis(
      minimum: minY,
      maximum: maxY,
      interval: intervalY?.toDouble(),
      labelFormat: '{value}',
      title: AxisTitle(text: yLabel, textStyle: TextStyle(color: color)),
    ),
    axes:
        yData2 != null
            ? [
              NumericAxis(
                name: 'secondaryYAxis',
                minimum: minY2,
                maximum: maxY2,
                interval: intervalY2?.toDouble(),
                opposedPosition: true,
                labelFormat: '{value}',
                title: AxisTitle(text: yLabel2, textStyle: TextStyle(color: color2)),
              ),
            ]
            : const <ChartAxis>[],
    tooltipBehavior: TooltipBehavior(
      animationDuration: 0,
      duration: 5000,
      enable: true,
      format: 'point.x, point.y',
      builder: (dynamic data, dynamic point, dynamic series, int pointIndex, int seriesIndex) {
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: secondaryColor, borderRadius: BorderRadius.circular(4)),
          child: Text(
            '(${(data.x).toStringAsFixed(1)}, ${(data.y).toStringAsFixed(1)})',
            style: TextStyle(color: color),
          ),
        );
      },
    ),
  );
}

class ChartData {
  final double x;
  final double y;

  ChartData(this.x, this.y);
}
