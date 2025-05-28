import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pandaboat/data/constants.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

int? calculateRoundedInterval(
  List<double> data,
  double rawInterval,
  List<Map<dynamic, int>> rules,
) {
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

class InteractiveLineChart extends StatefulWidget {
  final List<double> xData;
  final List<double> yData;
  final List<double>? yData2;
  final String xLabel;
  final String yLabel;
  final String yLabel2;
  final Color color;
  final Color color2;

  const InteractiveLineChart({
    super.key,
    required this.xData,
    required this.yData,
    this.yData2,
    this.xLabel = '',
    this.yLabel = '',
    this.yLabel2 = '',
    this.color = Colors.blueAccent,
    this.color2 = Colors.lightGreen,
  });

  @override
  State<InteractiveLineChart> createState() => _InteractiveLineChartState();
}

class _InteractiveLineChartState extends State<InteractiveLineChart> {
  double? _minXOverride;
  double? _maxXOverride;
  double? _minYOverride;
  double? _maxYOverride;
  double? _minY2Override;
  double? _maxY2Override;
  int? _intervalXOverride;
  int? _intervalYOverride;
  int? _intervalY2Override;

  bool _showPrimarySeries = true;
  bool _showSecondarySeries = true;

  Future<void> _showChartSettingsDialog() async {
    final xMinCtrl = TextEditingController(text: _minXOverride?.toString() ?? '');
    final xMaxCtrl = TextEditingController(text: _maxXOverride?.toString() ?? '');
    final yMinCtrl = TextEditingController(text: _minYOverride?.toString() ?? '');
    final yMaxCtrl = TextEditingController(text: _maxYOverride?.toString() ?? '');
    final y2MinCtrl = TextEditingController(text: _minY2Override?.toString() ?? '');
    final y2MaxCtrl = TextEditingController(text: _maxY2Override?.toString() ?? '');
    final xIntCtrl = TextEditingController(text: _intervalXOverride?.toString() ?? '');
    final yIntCtrl = TextEditingController(text: _intervalYOverride?.toString() ?? '');
    final y2IntCtrl = TextEditingController(text: _intervalY2Override?.toString() ?? '');

    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Chart Axis Settings", style: TextStyles.dialogTitle),
                IconButton(
                  tooltip: "Reset all fields",
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    setState(() {
                      _minXOverride = null;
                      _maxXOverride = null;
                      _intervalXOverride = null;
                      _minYOverride = null;
                      _maxYOverride = null;
                      _intervalYOverride = null;
                      _minY2Override = null;
                      _maxY2Override = null;
                      _intervalY2Override = null;
                    });
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildNumberField("Min X", xMinCtrl),
                  _buildNumberField("Max X", xMaxCtrl),
                  _buildNumberField("Interval X", xIntCtrl),
                  const Divider(),
                  _buildNumberField("Min Y", yMinCtrl),
                  _buildNumberField("Max Y", yMaxCtrl),
                  _buildNumberField("Interval Y", yIntCtrl),
                  const Divider(),
                  _buildNumberField("Min Y2", y2MinCtrl),
                  _buildNumberField("Max Y2", y2MaxCtrl),
                  _buildNumberField("Interval Y2", y2IntCtrl),
                ],
              ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () {
                  setState(() {
                    _minXOverride = double.tryParse(xMinCtrl.text);
                    _maxXOverride = double.tryParse(xMaxCtrl.text);
                    _intervalXOverride = int.tryParse(xIntCtrl.text);
                    _minYOverride = double.tryParse(yMinCtrl.text);
                    _maxYOverride = double.tryParse(yMaxCtrl.text);
                    _intervalYOverride = int.tryParse(yIntCtrl.text);
                    _minY2Override = double.tryParse(y2MinCtrl.text);
                    _maxY2Override = double.tryParse(y2MaxCtrl.text);
                    _intervalY2Override = int.tryParse(y2IntCtrl.text);
                  });
                  Navigator.pop(ctx);
                },
                child: const Text("Apply"),
              ),
            ],
          ),
    );
  }

  Widget _buildNumberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryColor, width: 2)),
        border: InputBorder.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double minX = _minXOverride ?? 0;
    final double maxX = _maxXOverride ?? widget.xData.reduce(max);

    final double minY = _minYOverride ?? 0;
    final double maxY = _maxYOverride ?? widget.yData.reduce(max);

    final double minY2 = _minY2Override ?? 0;
    final double maxY2 =
        _maxY2Override ?? (widget.yData2?.reduce(max) ?? 0) * 1.4; // scale so graphs don't overlap

    final spots = List.generate(
      widget.xData.length,
      (i) => ChartData(widget.xData[i], widget.yData[i]),
    );

    final spots2 =
        widget.yData2 != null
            ? List.generate(
              widget.xData.length,
              (i) => ChartData(widget.xData[i], widget.yData2![i]),
            )
            : null;

    final List<Map<dynamic, int>> intervals =
        widget.xLabel.contains("Time")
            ? [
              {7.5: 5},
              {100: 10},
              {300: 60},
              {'else': 300},
            ]
            : [
              {7.5: 5},
              {100: 10},
              {500: 100},
              {'else': 500},
            ];
    final int? intervalX =
        _intervalXOverride ?? calculateRoundedInterval(widget.xData, maxX / 5, intervals);

    final int? intervalY =
        _intervalYOverride ??
        calculateRoundedInterval(widget.yData, maxY / 10, [
          {5: 1},
          {'else': 5},
        ]);

    final int? intervalY2 =
        _intervalY2Override ??
        (widget.yData2 != null
            ? calculateRoundedInterval(widget.yData2!, maxY2 / 10, [
              {5: 1},
              {'else': 5},
            ])
            : null);

    return Column(
      children: [
        if (spots2 != null)
          Row(
            children: [
              Checkbox(
                value: _showPrimarySeries,
                onChanged: (val) {
                  setState(() => _showPrimarySeries = val ?? true);
                },
              ),
              const Text('Primary Series'),
              const SizedBox(width: 16),
              Checkbox(
                value: _showSecondarySeries,
                onChanged: (val) {
                  setState(() => _showSecondarySeries = val ?? true);
                },
              ),
              const Text('Secondary Series'),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: _showChartSettingsDialog,
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.settings, size: 24),
                ),
              ),
            ],
          ),
        Expanded(
          child: SfCartesianChart(
            zoomPanBehavior: ZoomPanBehavior(
              enablePinching: true,
              enablePanning: true,
              enableSelectionZooming: true,
              zoomMode: ZoomMode.xy,
              maximumZoomLevel: 0.05,
            ),
            series: [
              if (_showPrimarySeries)
                LineSeries<ChartData, double>(
                  initialIsVisible: _showPrimarySeries,
                  animationDuration: 0,
                  dataSource: spots,
                  xValueMapper: (ChartData data, _) => data.x,
                  yValueMapper: (ChartData data, _) => data.y,
                  color: widget.color,
                  width: 2,
                  markerSettings: MarkerSettings(
                    isVisible: false,
                    width: 2.2,
                    height: 2.2,
                    color: widget.color,
                    shape: DataMarkerType.circle,
                  ),
                ),
              if (_showSecondarySeries && spots2 != null)
                LineSeries<ChartData, double>(
                  initialIsVisible: _showSecondarySeries,
                  yAxisName: 'secondaryYAxis',
                  animationDuration: 0,
                  dataSource: spots2,
                  xValueMapper: (ChartData data, _) => data.x,
                  yValueMapper: (ChartData data, _) => data.y,
                  color: widget.color2,
                  width: 2,
                  markerSettings: MarkerSettings(
                    isVisible: false,
                    width: 2.2,
                    height: 2.2,
                    color: widget.color2,
                    shape: DataMarkerType.circle,
                  ),
                ),
            ],
            primaryXAxis: NumericAxis(
              minimum: minX,
              maximum: maxX,
              interval: intervalX?.toDouble(),
              labelFormat: '{value}',
              title: AxisTitle(text: widget.xLabel),
            ),
            primaryYAxis: NumericAxis(
              minimum: minY,
              maximum: maxY,
              interval: intervalY?.toDouble(),
              labelFormat: '{value}',
              title: AxisTitle(text: widget.yLabel, textStyle: TextStyle(color: widget.color)),
            ),
            axes:
                widget.yData2 != null
                    ? [
                      NumericAxis(
                        name: 'secondaryYAxis',
                        minimum: minY2,
                        maximum: maxY2,
                        interval: intervalY2?.toDouble(),
                        opposedPosition: true,
                        labelFormat: '{value}',
                        title: AxisTitle(
                          text: widget.yLabel2,
                          textStyle: TextStyle(color: widget.color2),
                        ),
                      ),
                    ]
                    : const <ChartAxis>[],
            tooltipBehavior: TooltipBehavior(
              animationDuration: 0,
              duration: 5000,
              enable: true,
              format: 'point.x, point.y',
              builder: (
                dynamic data,
                dynamic point,
                dynamic series,
                int pointIndex,
                int seriesIndex,
              ) {
                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: secondaryColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '(${(data.x).toStringAsFixed(1)}, ${(data.y).toStringAsFixed(1)})',
                    style: TextStyle(color: widget.color),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class ChartData {
  final double x;
  final double y;

  ChartData(this.x, this.y);
}
