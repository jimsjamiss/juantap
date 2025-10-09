import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math' as math;
import 'dart:async';

class DashboardOverview extends StatefulWidget {
  const DashboardOverview({super.key});

  @override
  State<DashboardOverview> createState() => _DashboardOverviewState();
}

class _DashboardOverviewState extends State<DashboardOverview> {
  late final DatabaseReference _usersRef;
  late final DatabaseReference _sosRef;
  late final DatabaseReference _zonesRef;
  late final DatabaseReference _reportsRef;

  int _totalUsers = 0;
  int _totalSOS = 0;
  int _totalZones = 0;
  int _reportsThisMonth = 0;

  @override
  void initState() {
    super.initState();
    _usersRef = FirebaseDatabase.instance.ref('users');
    _sosRef = FirebaseDatabase.instance.ref('sos_alerts');
    _zonesRef = FirebaseDatabase.instance.ref('danger_zones');
    _reportsRef = FirebaseDatabase.instance.ref('responder_reports');
    _bindStats();
  }

  void _bindStats() {
    _usersRef.onValue.listen((e) {
      setState(() => _totalUsers = e.snapshot.children.length);
    });

    _sosRef.onValue.listen((e) {
      setState(() => _totalSOS = e.snapshot.children.length);
    });

    _zonesRef.onValue.listen((e) {
      setState(() => _totalZones = e.snapshot.children.length);
    });

    _reportsRef.onValue.listen((e) {
      final now = DateTime.now();
      int monthCount = 0;
      for (final userSnap in e.snapshot.children) {
        for (final reportSnap in userSnap.children) {
          final dateStr = reportSnap.child('date').value?.toString();
          if (dateStr != null && dateStr.contains('/')) {
            try {
              final parts = dateStr.split('/');
              if (parts.length == 3) {
                final month = int.parse(parts[0]);
                final day = int.parse(parts[1]);
                final year = int.parse(parts[2]);
                final reportDate = DateTime(year, month, day);
                if (reportDate.year == now.year &&
                    reportDate.month == now.month) {
                  monthCount++;
                }
              }
            } catch (_) {}
          }
        }
      }
      setState(() => _reportsThisMonth = monthCount);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatCard(
        icon: Icons.people,
        label: 'Total Users',
        value: _totalUsers.toString(),
        color: const Color(0xFF1E88E5),
      ),
      _StatCard(
        icon: Icons.sos,
        label: 'Total SOS Alerts',
        value: _totalSOS.toString(),
        color: Colors.redAccent,
      ),
      _StatCard(
        icon: Icons.warning_amber,
        label: 'Danger Zones',
        value: _totalZones.toString(),
        color: Colors.orange,
      ),
      _StatCard(
        icon: Icons.assignment_turned_in,
        label: 'Reports (This Month)',
        value: _reportsThisMonth.toString(),
        color: Colors.green,
      ),
    ];

    return Container(
      color: const Color(0xFFF7F9FB),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Dashboard Overview",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF264653),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh, color: Color(0xFF264653)),
                  tooltip: "Refresh",
                )
              ],
            ),
            const SizedBox(height: 24),

            // Stats grid
            LayoutBuilder(
              builder: (ctx, c) {
                final w = c.maxWidth;
                final cross = w > 1400 ? 4 : w > 900 ? 2 : 1;
                return GridView.count(
                  crossAxisCount: cross,
                  shrinkWrap: true,
                  childAspectRatio: 2.8,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 20,
                  physics: const NeverScrollableScrollPhysics(),
                  children: cards,
                );
              },
            ),

            const SizedBox(height: 32),

            // ✅ Zigzag Line Chart
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Monthly Responder Reports",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Color(0xFF264653),
                      ),
                    ),
                    SizedBox(height: 16),
                    _LineChartContainer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- Stat Card --------------------
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF264653),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- Line Chart Container --------------------
class _LineChartContainer extends StatefulWidget {
  const _LineChartContainer({super.key});

  @override
  State<_LineChartContainer> createState() => _LineChartContainerState();
}

class _LineChartContainerState extends State<_LineChartContainer> {
  final DatabaseReference _reportsRef =
  FirebaseDatabase.instance.ref('responder_reports');
  List<int> _monthlyCounts = List.filled(12, 0);
  bool _loading = true;
  int _year = DateTime.now().year;
  StreamSubscription<DatabaseEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _listenReports();
  }

  void _listenReports() {
    _subscription?.cancel();
    setState(() => _loading = true);

    _subscription = _reportsRef.onValue.listen((e) {
      final counts = List<int>.filled(12, 0);
      for (final userSnap in e.snapshot.children) {
        for (final reportSnap in userSnap.children) {
          final dateStr = reportSnap.child('date').value?.toString();
          if (dateStr != null && dateStr.contains('/')) {
            try {
              final parts = dateStr.split('/');
              if (parts.length == 3) {
                final month = int.parse(parts[0]);
                final year = int.parse(parts[2]);
                if (year == _year && month >= 1 && month <= 12) {
                  counts[month - 1]++;
                }
              }
            } catch (_) {}
          }
        }
      }
      if (mounted) {
        setState(() {
          _monthlyCounts = counts;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Spacer(),
            DropdownButton<int>(
              value: _year,
              items: [
                for (int y = DateTime.now().year - 3; y <= DateTime.now().year; y++)
                  DropdownMenuItem(value: y, child: Text('$y')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _year = v);
                _listenReports();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const SizedBox(
            height: 250,
            child: Center(
              child: CircularProgressIndicator(color: Colors.deepPurple),
            ),
          )
        else
          SizedBox(
            height: 280,
            child: _LineChart(values: _monthlyCounts),
          ),
      ],
    );
  }
}

// -------------------- Line Chart Widget --------------------
class _LineChart extends StatelessWidget {
  final List<int> values;
  const _LineChart({required this.values});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LineChartPainter(values),
      child: Container(),
    );
  }
}

// -------------------- Zigzag Line Chart Painter --------------------
class _LineChartPainter extends CustomPainter {
  final List<int> values;
  _LineChartPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final paddingLeft = 55.0;
    final paddingBottom = 32.0;
    final chartW = size.width - paddingLeft - 20;
    final chartH = size.height - paddingBottom - 20;
    final origin = Offset(paddingLeft, size.height - paddingBottom);

    final paintAxis = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;

    final paintGrid = Paint()
      ..color = Colors.grey.shade300.withOpacity(0.6)
      ..strokeWidth = 0.6;

    final paintLine = Paint()
      ..color = const Color(0xFF1E88E5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final paintDot = Paint()
      ..color = const Color(0xFF1E88E5)
      ..style = PaintingStyle.fill;

    // Axes
    canvas.drawLine(origin, Offset(origin.dx + chartW, origin.dy), paintAxis);
    canvas.drawLine(origin, Offset(origin.dx, origin.dy - chartH), paintAxis);

    final maxV = (values.isEmpty ? 0 : values.reduce(math.max)).clamp(1, 1 << 30);
    final stepX = chartW / 11;
    final labelCount = 5;

    // ✅ Gridlines + Y-axis labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i <= labelCount; i++) {
      final val = (maxV / labelCount * i).round();
      final y = origin.dy - (i / labelCount) * chartH;

      canvas.drawLine(Offset(origin.dx, y), Offset(origin.dx + chartW, y), paintGrid);

      textPainter.text = TextSpan(
        text: '$val',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 8, y - 6));
    }

    // Line Path
    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = origin.dx + i * stepX;
      final y = origin.dy - (values[i] / maxV) * chartH;
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
      canvas.drawCircle(Offset(x, y), 4, paintDot);
    }
    canvas.drawPath(path, paintLine);

    // ✅ Month Labels
    const months = ['J','F','M','A','M','J','J','A','S','O','N','D'];
    for (int i = 0; i < months.length; i++) {
      final x = origin.dx + i * stepX;
      final tp = TextPainter(
        text: TextSpan(
          text: months[i],
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, origin.dy + 8));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.values != values;
}