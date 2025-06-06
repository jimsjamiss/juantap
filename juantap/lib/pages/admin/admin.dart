import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class admin extends StatelessWidget {
  const admin({super.key});

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF8A65), Color(0xFFFF5252)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.arrow_downward, color: Colors.white, size: 40),
              const SizedBox(height: 10),
              const Text(
                'Export as CSV file',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF28A361),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('CSV file exported')),
                  );
                },
                child: const Text('Export'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Dashboard',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 28)),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.cancel, color: Colors.white),
                      ),
                      IconButton(
                        onPressed: () => _showExportDialog(context),
                        icon: const Icon(Icons.download, color: Colors.white),
                      )
                    ],
                  )
                ],
              ),
              const SizedBox(height: 20),
              _buildSection(title: 'Manage Users', children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(
                    5,
                        (index) => const CircleAvatar(
                      radius: 20,
                      backgroundImage:
                      NetworkImage('https://i.imgur.com/8Km9tLL.jpg'),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              _buildSection(title: 'Incident Reports', children: [
                _incidentReportCard('Opao, Looc'),
                _incidentReportCard('Opao, Umapad'),
                _incidentReportCard('Opao, Umapad'),
              ]),
              const SizedBox(height: 20),
              _buildSection(title: 'Statistics', children: [
                SizedBox(
                  height: 150,
                  child: BarChart(
                    BarChartData(
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              const months = [
                                'JAN',
                                'FEB',
                                'MAR',
                                'APR',
                                'MAY',
                                'JUN',
                                'JUL',
                                'AUG',
                                'SEP',
                                'OCT',
                                'NOV',
                                'DEC'
                              ];
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(months[value.toInt()],
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 10)),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: List.generate(
                        12,
                            (i) => BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: (10 + i * 2) % 40,
                            color: Colors.white,
                            width: 8,
                          ),
                        ]),
                      ),
                    ),
                  ),
                )
              ]),
              const SizedBox(height: 20),
              Row(
                children: [
                  _summaryCard('SOS Counts', '9'),
                  const SizedBox(width: 12),
                  _summaryCard('Active Users', '40/68'),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          ...children
        ],
      ),
    );
  }

  Widget _incidentReportCard(String location) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.map_outlined, color: Colors.white70),
          const SizedBox(width: 8),
          Text(location, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}