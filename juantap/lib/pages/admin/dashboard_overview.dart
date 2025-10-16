import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

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
  late final DatabaseReference _guidesRef;

  int _totalUsers = 0;
  int _totalSOS = 0;
  int _totalZones = 0;
  int _reportsThisMonth = 0;
  int _totalGuides = 0;
  bool _isHovered = false; // ✅ for hover animation

  @override
  void initState() {
    super.initState();
    _usersRef = FirebaseDatabase.instance.ref('users');
    _sosRef = FirebaseDatabase.instance.ref('sos_alerts');
    _zonesRef = FirebaseDatabase.instance.ref('danger_zones');
    _reportsRef = FirebaseDatabase.instance.ref('responder_reports');
    _guidesRef = FirebaseDatabase.instance.ref('self_defense_guides');
    _bindStats();
  }

  void _bindStats() {
    _usersRef.onValue.listen((e) => setState(() => _totalUsers = e.snapshot.children.length));
    _sosRef.onValue.listen((e) => setState(() => _totalSOS = e.snapshot.children.length));
    _zonesRef.onValue.listen((e) => setState(() => _totalZones = e.snapshot.children.length));

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
                final year = int.parse(parts[2]);
                if (year == now.year && month == now.month) monthCount++;
              }
            } catch (_) {}
          }
        }
      }
      setState(() => _reportsThisMonth = monthCount);
    });

    _guidesRef.onValue.listen((e) => setState(() => _totalGuides = e.snapshot.children.length));
  }

  // ✅ Uploaded Guides Popup
  void _showUploadedGuidesPopup() async {
    final snapshot = await _guidesRef.get();
    final guides = snapshot.children.toList();

    showGeneralDialog(
      context: context,
      barrierLabel: "Close",
      barrierDismissible: true,
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, _, __) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(animation.value),
          child: Opacity(
            opacity: animation.value,
            child: AlertDialog(
              backgroundColor: const Color(0xFFF8FFF8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: const [
                  Icon(Icons.menu_book_rounded, color: Color(0xFF2EB872)),
                  SizedBox(width: 8),
                  Text(
                    "Uploaded Self-Defense Guides",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0E4D35),
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
              content: guides.isEmpty
                  ? const Text("No uploaded guides found.", style: TextStyle(color: Colors.grey))
                  : SizedBox(
                width: 420,
                height: 320,
                child: ListView.builder(
                  itemCount: guides.length,
                  itemBuilder: (context, index) {
                    final id = guides[index].key!;
                    final link = guides[index].child('link').value?.toString() ?? 'No link';
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.08),
                            blurRadius: 6,
                            offset: const Offset(2, 3),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: link == 'No link'
                                ? Colors.red.withOpacity(0.12)
                                : const Color(0xFFE8F5E9),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: link == 'No link'
                                ? Colors.redAccent
                                : const Color(0xFF11998E),
                            size: 28,
                          ),
                        ),
                        title: Text(
                          link == 'No link' ? 'Invalid or Empty Link' : link,
                          style: TextStyle(
                            color: link == 'No link'
                                ? Colors.redAccent
                                : const Color(0xFF0E4D35),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.redAccent),
                          onPressed: () => _showConfirmDeleteDialog(id),
                        ),
                        onTap: link != 'No link'
                            ? () async {
                          final uri = Uri.parse(link);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        }
                            : null,
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close", style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ✅ Confirm Delete Dialog
  void _showConfirmDeleteDialog(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Delete Guide?",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
        content: const Text(
          "Are you sure you want to delete this self-defense guide?",
          style: TextStyle(color: Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await _guidesRef.child(id).remove();
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("🗑️ Guide deleted successfully")),
              );
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  // ✅ Upload Guide Dialog
  void _showUploadGuideDialog() {
    final TextEditingController _linkController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Upload Self-Defense Guide",
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0E4D35))),
        content: TextField(
          controller: _linkController,
          decoration: InputDecoration(
            hintText: "Enter YouTube link...",
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton.icon(
            onPressed: () async {
              final link = _linkController.text.trim();
              if (link.isEmpty || !link.contains("youtube.com")) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text("Please enter a valid YouTube link")));
                return;
              }

              final id = _guidesRef.push().key!;
              await _guidesRef.child(id).set({'link': link, 'uploaded_at': DateTime.now().toIso8601String()});

              Navigator.pop(context);
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text("✅ Guide uploaded successfully")));
            },
            icon: const Icon(Icons.cloud_upload_rounded),
            label: const Text("Upload"),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38EF7D), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // ✅ UI Layout
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
          Color(0xFFC8F4E4),
          Color(0xFFA7E2C9),
          Color(0xFF7FD1AE),
        ]),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Dashboard Overview",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF084C41))),
            ElevatedButton.icon(
              onPressed: _showUploadGuideDialog,
              icon: const Icon(Icons.video_library_rounded, size: 20),
              label: const Text("Upload Guide"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ]),
          const SizedBox(height: 24),

          // ✅ Stats Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _MiniStatCard(label: 'Total Users', value: _totalUsers, icon: Icons.people, gradient: const LinearGradient(colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)])),
              const SizedBox(width: 16),
              _MiniStatCard(label: 'Total SOS Alerts', value: _totalSOS, icon: Icons.sos, gradient: const LinearGradient(colors: [Color(0xFF56CCF2), Color(0xFF2F80ED)])),
              const SizedBox(width: 16),
              _MiniStatCard(label: 'Danger Zones', value: _totalZones, icon: Icons.warning_amber_rounded, gradient: const LinearGradient(colors: [Color(0xFF38EF7D), Color(0xFF11998E)])),
              const SizedBox(width: 16),
              _MiniStatCard(label: 'Reports (This Month)', value: _reportsThisMonth, icon: Icons.assignment_turned_in, gradient: const LinearGradient(colors: [Color(0xFFB993D6), Color(0xFF8CA6DB)])),
              const SizedBox(width: 16),

              // ✅ Hover-Enabled Uploaded Guides Card
              // ✅ Hover-Enabled Uploaded Guides Card with Glow
              MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  transform: _isHovered ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
                  decoration: BoxDecoration(
                    boxShadow: _isHovered
                        ? [
                      BoxShadow(
                        color: Colors.white.withOpacity(0.6), // 💫 soft glow
                        blurRadius: 25,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black26.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                        : [],
                  ),
                  child: GestureDetector(
                    onTap: _showUploadedGuidesPopup,
                    child: _MiniStatCard(
                      label: 'Uploaded Guides',
                      value: _totalGuides,
                      icon: Icons.menu_book_rounded,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF38EF7D), Color(0xFF7FD1AE), Color(0xFF11998E)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      outline: true,
                    ),
                  ),
                ),
              ),

            ]),
          ),
          const SizedBox(height: 32),
          const _ChartSection(),
        ]),
      ),
    );
  }
}

// ✅ MiniStatCard Widget
class _MiniStatCard extends StatefulWidget {
  final String label;
  final int value;
  final LinearGradient gradient;
  final IconData icon;
  final bool outline;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.gradient,
    required this.icon,
    this.outline = false,
  });

  @override
  State<_MiniStatCard> createState() => _MiniStatCardState();
}

class _MiniStatCardState extends State<_MiniStatCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _counter;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _counter = IntTween(begin: 0, end: widget.value).animate(_controller);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _MiniStatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _counter = IntTween(begin: 0, end: widget.value).animate(_controller);
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 90,
      decoration: BoxDecoration(
        gradient: widget.gradient,
        borderRadius: BorderRadius.circular(16),
        border: widget.outline ? Border.all(color: Colors.black, width: 2) : null,
        boxShadow: [
          BoxShadow(color: Colors.green.withOpacity(0.2), blurRadius: 8, offset: const Offset(2, 3)),
        ],
      ),
      child: Stack(children: [
        Positioned(right: 8, top: 8, child: Icon(widget.icon, size: 40, color: Colors.white.withOpacity(0.2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(widget.label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            AnimatedBuilder(
              animation: _counter,
              builder: (context, child) => Text(
                _counter.value.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ✅ Chart Section
class _ChartSection extends StatelessWidget {
  const _ChartSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFF4FFF9),
      elevation: 6,
      shadowColor: Colors.green.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Monthly Responder Reports",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0E4D35))),
          SizedBox(height: 16),
          _AnimatedLineChartContainer(),
        ]),
      ),
    );
  }
}

// ✅ Animated Line Chart Section
class _AnimatedLineChartContainer extends StatefulWidget {
  const _AnimatedLineChartContainer({super.key});

  @override
  State<_AnimatedLineChartContainer> createState() => _AnimatedLineChartContainerState();
}

class _AnimatedLineChartContainerState extends State<_AnimatedLineChartContainer> with SingleTickerProviderStateMixin {
  final DatabaseReference _reportsRef = FirebaseDatabase.instance.ref('responder_reports');
  List<int> _monthlyCounts = List.filled(12, 0);
  bool _loading = true;
  int _year = DateTime.now().year;
  StreamSubscription<DatabaseEvent>? _subscription;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
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
                if (year == _year && month >= 1 && month <= 12) counts[month - 1]++;
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
        _controller.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        const Spacer(),
        DropdownButton<int>(
          dropdownColor: const Color(0xFFE8FFF4),
          value: _year,
          items: [
            for (int y = DateTime.now().year - 3; y <= DateTime.now().year; y++)
              DropdownMenuItem(value: y, child: Text('$y', style: const TextStyle(color: Color(0xFF0E4D35)))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _year = v);
            _listenReports();
          },
        ),
      ]),
      const SizedBox(height: 12),
      if (_loading)
        const SizedBox(height: 250, child: Center(child: CircularProgressIndicator(color: Color(0xFF38EF7D))))
      else
        SizedBox(
          height: 280,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => _GradientLineChart(
              values: _monthlyCounts.map((v) => (v * _controller.value).round()).toList(),
            ),
          ),
        ),
    ]);
  }
}

class _GradientLineChart extends StatelessWidget {
  final List<int> values;
  const _GradientLineChart({required this.values});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GradientLineChartPainter(values), child: Container());
  }
}

class _GradientLineChartPainter extends CustomPainter {
  final List<int> values;
  _GradientLineChartPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final paddingLeft = 55.0;
    final paddingBottom = 32.0;
    final chartW = size.width - paddingLeft - 20;
    final chartH = size.height - paddingBottom - 20;
    final origin = Offset(paddingLeft, size.height - paddingBottom);
    final paintGrid = Paint()..color = const Color(0xFFBFE8D1)..strokeWidth = 0.7;
    final maxV = (values.isEmpty ? 0 : values.reduce(math.max)).clamp(1, 1 << 30);
    final stepX = chartW / 11;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    const labelCount = 5;

    for (int i = 0; i <= labelCount; i++) {
      final val = (maxV / labelCount * i).round();
      final y = origin.dy - (i / labelCount) * chartH;
      canvas.drawLine(Offset(origin.dx, y), Offset(origin.dx + chartW, y), paintGrid);
      textPainter.text =
          TextSpan(text: '$val', style: const TextStyle(fontSize: 11, color: Color(0xFF0E4D35)));
      textPainter.layout();
      textPainter.paint(canvas, Offset(paddingLeft - textPainter.width - 8, y - 6));
    }

    final points = [
      for (int i = 0; i < values.length; i++)
        Offset(origin.dx + i * stepX, origin.dy - (values[i] / maxV) * chartH)
    ];

    final path = Path();
    if (points.isNotEmpty) {
      path.moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) path.lineTo(points[i].dx, points[i].dy);
    }

    final fillGradient = LinearGradient(
      colors: [const Color(0xFF38EF7D).withOpacity(0.25), Colors.transparent],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    final fillPaint =
    Paint()..shader = fillGradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final fillPath = Path.from(path)
      ..lineTo(origin.dx + chartW, origin.dy)
      ..lineTo(origin.dx, origin.dy)
      ..close();
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF38EF7D)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = const Color(0xFF2EB872)..style = PaintingStyle.fill;
    for (final p in points) canvas.drawCircle(p, 3.5, dotPaint);

    const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
    for (int i = 0; i < months.length; i++) {
      final x = origin.dx + i * stepX;
      final tp = TextPainter(
        text: TextSpan(text: months[i], style: const TextStyle(fontSize: 11, color: Color(0xFF0E4D35))),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, origin.dy + 8));
    }
  }

  @override
  bool shouldRepaint(covariant _GradientLineChartPainter oldDelegate) => oldDelegate.values != values;
}
