// lib/pages/admin/analytics_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math' as math;

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  late final DatabaseReference _reportsRef;
  List<int> _monthlyCounts = List.filled(12, 0);
  bool _loading = true;
  int _year = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _reportsRef = FirebaseDatabase.instance.ref('responder_reports');
    _load();
  }

  void _load() {
    _reportsRef.onValue.listen((e) {
      final counts = List<int>.filled(12, 0);
      for (final s in e.snapshot.children) {
        final ts = s.child('createdAt').value;
        if (ts is int) {
          final dt = DateTime.fromMillisecondsSinceEpoch(ts);
          if (dt.year == _year) {
            counts[dt.month - 1]++;
          }
        }
      }
      setState(() {
        _monthlyCounts = counts;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text("Monthly SOS/Reports Trend",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const Spacer(),
            DropdownButton<int>(
              value: _year,
              items: [
                for (int y = DateTime.now().year - 3; y <= DateTime.now().year; y++)
                  DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _year = v;
                  _loading = true;
                });
                _load();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            height: 280,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _BarChart(values: _monthlyCounts),
            ),
          ),
        ),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<int> values; // length 12
  const _BarChart({required this.values});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BarChartPainter(values),
      child: Container(),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  final List<int> values;
  _BarChartPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final paintAxis = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    final paintBar = Paint()..color = const Color(0xFF1E88E5);

    final padding = 28.0;
    final chartW = size.width - padding * 2;
    final chartH = size.height - padding * 2;
    final origin = Offset(padding, size.height - padding);

    // Axes
    canvas.drawLine(origin, Offset(origin.dx + chartW, origin.dy), paintAxis);
    canvas.drawLine(origin, Offset(origin.dx, origin.dy - chartH), paintAxis);

    final maxV = (values.isEmpty ? 0 : values.reduce(math.max)).clamp(0, 1);
    final barW = chartW / (values.length * 1.5);
    final gap = barW / 2;

    final textPainter =
    TextPainter(textAlign: TextAlign.center, textDirection: TextDirection.ltr);

    for (int i = 0; i < values.length; i++) {
      final x = origin.dx + i * (barW + gap) + gap;
      final h = maxV == 0 ? 0.0 : (values[i] / maxV) * (chartH * 0.9);
      final rect = Rect.fromLTWH(x, origin.dy - h, barW, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), paintBar);

      // Labels
      final label = ['J','F','M','A','M','J','J','A','S','O','N','D'][i];
      textPainter.text =
          TextSpan(text: label, style: TextStyle(fontSize: 10, color: Colors.grey.shade700));
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + barW / 2 - textPainter.width / 2, origin.dy + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter oldDelegate) =>
      oldDelegate.values != values;
}