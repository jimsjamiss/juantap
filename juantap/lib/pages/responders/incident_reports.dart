import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class IncidentReportsPage extends StatefulWidget {
  const IncidentReportsPage({super.key});

  @override
  State<IncidentReportsPage> createState() => _IncidentReportsPageState();
}

class _IncidentReportsPageState extends State<IncidentReportsPage> {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  Map<String, List<Map<String, dynamic>>> reportsByDate = {};
  Set<int> availableYears = {};
  Set<int> availableMonths = {};
  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final ref = FirebaseDatabase.instance.ref('responder_reports/$userId');
    final snapshot = await ref.get();

    if (snapshot.exists) {
      final data = snapshot.value as Map;
      final tempMap = <String, List<Map<String, dynamic>>>{};
      final tempYears = <int>{};
      final tempMonths = <int>{};

      for (var entry in data.entries) {
        final report = Map<String, dynamic>.from(entry.value);
        final date = report['date'];
        if (date != null) {
          tempMap.putIfAbsent(date, () => []).add(report);

          final parts = date.split('/');
          if (parts.length == 3) {
            final month = int.tryParse(parts[0]) ?? 1;
            final year = int.tryParse(parts[2]) ?? DateTime.now().year;
            tempYears.add(year);
            tempMonths.add(month);
          }
        }
      }

      setState(() {
        reportsByDate = tempMap;
        availableYears = tempYears;
        availableMonths = tempMonths;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final int daysInMonth = DateUtils.getDaysInMonth(selectedYear, selectedMonth);

    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text('Responder', style: TextStyle(color: Colors.white)),
      ),
      body: reportsByDate.isEmpty
          ? const Center(child: Text('No incident reports found', style: TextStyle(color: Colors.white)))
          : Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Incident Reports Calendar',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    dropdownColor: Colors.teal[100],
                    value: selectedMonth,
                    onChanged: (value) {
                      setState(() {
                        selectedMonth = value!;
                      });
                    },
                    items: List.generate(12, (index) {
                      final monthNum = index + 1;
                      return DropdownMenuItem<int>(
                        value: monthNum,
                        child: Text(DateFormat('MMMM').format(DateTime(0, monthNum)),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<int>(
                    dropdownColor: Colors.teal[100],
                    value: selectedYear,
                    onChanged: (value) {
                      setState(() {
                        selectedYear = value!;
                      });
                    },
                    items: availableYears.map((year) {
                      return DropdownMenuItem<int>(
                        value: year,
                        child: Text('$year', style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                itemCount: daysInMonth,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemBuilder: (context, index) {
                  final day = index + 1;
                  final dateKey =
                      '${selectedMonth.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}/$selectedYear';
                  final reportsToday = reportsByDate[dateKey] ?? [];

                  return GestureDetector(
                    onTap: reportsToday.isNotEmpty
                        ? () => _showReportsDialog(context, dateKey, reportsToday)
                        : null,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Text('$day', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          if (reportsToday.isNotEmpty)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                child: Text('${reportsToday.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportsDialog(
      BuildContext context, String date, List<Map<String, dynamic>> reports) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Reports on $date'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                final double? lat = double.tryParse(report['latitude']?.toString() ?? '');
                final double? lng = double.tryParse(report['longitude']?.toString() ?? '');

                return Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(report['description'] ?? 'No description'),
                        subtitle: Text(
                          'Time: ${report['time'] ?? ''}\nStatus: ${report['status'] ?? ''}',
                        ),
                      ),
                      if (lat != null && lng != null)
                        SizedBox(
                          height: 180,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: LatLng(lat, lng),
                                zoom: 16,
                              ),
                              markers: {
                                Marker(
                                  markerId: MarkerId('report_$index'),
                                  position: LatLng(lat, lng),
                                )
                              },
                              zoomControlsEnabled: false,
                              liteModeEnabled: true,
                              myLocationEnabled: false,
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}