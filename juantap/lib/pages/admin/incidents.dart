import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

class AdminIncidentListPage extends StatefulWidget {
  const AdminIncidentListPage({super.key});

  @override
  State<AdminIncidentListPage> createState() => _AdminIncidentListPageState();
}

class _AdminIncidentListPageState extends State<AdminIncidentListPage> {
  Map<String, List<Map<String, dynamic>>> reportsByDate = {};
  Set<int> availableYears = {};
  Set<int> availableMonths = {};
  int selectedYear = DateTime.now().year;
  int selectedMonth = DateTime.now().month;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final dbRef = FirebaseDatabase.instance.ref('responder_reports');
    final snapshot = await dbRef.get();

    if (snapshot.exists) {
      final Map data = snapshot.value as Map;
      final tempMap = <String, List<Map<String, dynamic>>>{};
      final tempYears = <int>{};
      final tempMonths = <int>{};

      data.forEach((responderId, reportGroup) {
        final reports = Map<String, dynamic>.from(reportGroup);
        reports.forEach((reportId, reportData) {
          final report = Map<String, dynamic>.from(reportData);
          report['responderId'] = responderId;
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
        });
      });

      setState(() {
        reportsByDate = tempMap;
        availableYears = tempYears;
        availableMonths = tempMonths;
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
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
        title: const Text('Incident Reports Calendar', style: TextStyle(color: Colors.white)),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : reportsByDate.isEmpty
          ? const Center(child: Text('No reports found', style: TextStyle(color: Colors.white)))
          : Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    dropdownColor: Colors.teal[100],
                    value: selectedMonth,
                    onChanged: (value) => setState(() => selectedMonth = value!),
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
                    onChanged: (value) => setState(() => selectedYear = value!),
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
            const SizedBox(height: 10),
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
                            child: Text('$day',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
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
                final responderName = report['responderName'] ?? report['responderId'];

                return Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: Text(responderName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            'Time: ${report['time'] ?? ''}\nStatus: ${report['status'] ?? ''}\nDescription: ${report['description'] ?? 'No description'}'),
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