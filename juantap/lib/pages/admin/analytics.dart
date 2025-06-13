import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  int selectedMonth = DateTime.now().month - 1;
  final List<String> months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  List<int> sosCounts = List.filled(12, 0);
  List<int> activeUsers = List.filled(12, 0);

  @override
  void initState() {
    super.initState();
    fetchSOSCounts();
    fetchActiveUsers();
  }

  void fetchSOSCounts() async {
    final dbRef = FirebaseDatabase.instance.ref('sos_alerts');
    final snapshot = await dbRef.get();

    List<int> counts = List.filled(12, 0);

    for (final user in snapshot.children) {
      for (final alert in user.children) {
        final timestamp = alert.child('location').child('timestamp').value?.toString();
        if (timestamp != null) {
          try {
            final date = DateTime.parse(timestamp);
            counts[date.month - 1]++;
          } catch (_) {
            // Ignore invalid formats
          }
        }
      }
    }

    setState(() {
      sosCounts = counts;
    });
  }

  void fetchActiveUsers() async {
    final dbRef = FirebaseDatabase.instance.ref('responder_reports');
    final snapshot = await dbRef.get();

    Set<String> seen = {};
    List<int> counts = List.filled(12, 0);

    for (final user in snapshot.children) {
      for (final report in user.children) {
        final dateStr = report.child('date').value?.toString();
        if (dateStr != null && dateStr.contains("/")) {
          final parts = dateStr.split("/");
          if (parts.length >= 3) {
            final month = int.tryParse(parts[0]) ?? 0;
            final uniqueKey = '${user.key}_${report.key}';
            if (!seen.contains(uniqueKey) && month >= 1 && month <= 12) {
              seen.add(uniqueKey);
              counts[month - 1]++;
            }
          }
        }
      }
    }

    setState(() {
      activeUsers = counts;
    });
  }

  List<FlSpot> getSpots() {
    return List.generate(
      sosCounts.length,
          (i) => FlSpot(i.toDouble(), sosCounts[i].toDouble()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
        title: const Text("Analytics", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            Text('${months[selectedMonth]} Statistics',
                style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 4),
            Text('${sosCounts[selectedMonth]}',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            Container(
              height: 200,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(12),
              child: LineChart(
                LineChartData(
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, _) {
                          int index = value.toInt();
                          return Text(months[index % 12],
                              style: const TextStyle(fontSize: 10, color: Colors.white));
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (value, _) {
                          return Text(value.toInt().toString(),
                              style: const TextStyle(fontSize: 10, color: Colors.white));
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: getSpots(),
                      isCurved: true,
                      barWidth: 4,
                      color: Colors.white,
                      dotData: FlDotData(show: true),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: months.length,
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => setState(() => selectedMonth = index),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selectedMonth == index ? Colors.white : Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        months[index],
                        style: TextStyle(
                          color: selectedMonth == index ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.warning,
                      label: 'SOS Counts',
                      value: '${sosCounts[selectedMonth]}',
                      indicator: '+12.43%',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.person,
                      label: 'Active Users',
                      value: '${activeUsers[selectedMonth]}/68',
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

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    String? indicator,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFB2DFDB), Color(0xFF4DB6AC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.black),
              if (indicator != null) ...[
                const SizedBox(width: 4),
                Text(indicator, style: const TextStyle(fontSize: 12)),
              ]
            ],
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}