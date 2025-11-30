// 📦 Full updated IncidentReportsPage — with DateTime modal, Status Filter, and Delete Button UI Update
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'web_live_map.dart'; // ✅ Import your real-time web map widget
import 'package:intl/intl.dart';


class IncidentReportsPage extends StatefulWidget {
  const IncidentReportsPage({super.key});

  @override
  State<IncidentReportsPage> createState() => _IncidentReportsPageState();
}

class _IncidentReportsPageState extends State<IncidentReportsPage> {
  late final DatabaseReference _reportsRef;
  List<_ReportRow> _rows = [];
  bool _loading = true;
  DateTimeRange? _range;
  String? _monthRangeLabel;
  String _statusFilter = 'All'; // ✅ new status filter

  @override
  void initState() {
    super.initState();
    _reportsRef = FirebaseDatabase.instance.ref('responder_reports');
    _bind();
  }

  void _bind() {
    _reportsRef.onValue.listen((event) {
      final tmp = <_ReportRow>[];

      for (final responderSnapshot in event.snapshot.children) {
        final responderId = responderSnapshot.key ?? '';

        for (final reportSnapshot in responderSnapshot.children) {
          final reportId = reportSnapshot.key ?? '';
          final data = Map<String, dynamic>.from(reportSnapshot.value as Map);

          // ✅ Match responder’s saved data structure
          final timestamp = data['timestamp'];
          DateTime? parsedTime;
          if (timestamp != null) {
            try {
              parsedTime = DateTime.parse(timestamp);
            } catch (_) {}
          }

          tmp.add(_ReportRow(
            responderId: responderId,
            reportId: reportId,
            responderName: data['responderName'] ?? responderId,
            citizenName: data['userName'] ?? 'Unknown',
            incidentType: data['incidentType'] ?? 'Unknown',
            date: parsedTime != null
                ? "${parsedTime.month}/${parsedTime.day}/${parsedTime.year}"
                : 'Unknown',
            time: parsedTime != null
                ? DateFormat('h:mm a').format(parsedTime)
                : 'Unknown',
            description: data['actionStory'] ?? 'No details provided',
            location: data['placeOfIncident'] ?? 'Unknown',
            status: (data['resolved'] == 'Yes')
                ? 'Resolved'
                : (data['resolved'] == 'No' ? 'Pending' : 'Pending'),
            lat: (data['latitude'] != null)
                ? (data['latitude'] as num).toDouble()
                : null,
            lng: (data['longitude'] != null)
                ? (data['longitude'] as num).toDouble()
                : null,
          ));
        }
      }

      setState(() {
        _rows = tmp.reversed.toList();
        _loading = false;
      });
    });
  }


  List<_ReportRow> get _filtered {
    List<_ReportRow> filtered = _rows;
    if (_statusFilter != 'All') {
      filtered = filtered
          .where((r) => r.status.toLowerCase() == _statusFilter.toLowerCase())
          .toList();
    }
    if (_range != null) {
      filtered = filtered.where((r) {
        try {
          final dateParts = r.date.split('/');
          if (dateParts.length == 3) {
            final d = DateTime(
              int.parse(dateParts[2]),
              int.parse(dateParts[0]),
              int.parse(dateParts[1]),
            );
            return !d.isBefore(_range!.start) && !d.isAfter(_range!.end);
          }
          return false;
        } catch (_) {
          return false;
        }
      }).toList();
    }
    return filtered;
  }

  // 🕓 Custom month picker with year input
  Future<void> _pickRange() async {
    int? selectedMonth;
    final yearController = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFAFCFF),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Select Month',
            style: TextStyle(
              color: Color(0xFF084C41),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: StatefulBuilder(
            builder: (context, setState) {
              final months = List.generate(
                12,
                    (index) => DateFormat('MMMM').format(DateTime(0, index + 1)),
              );

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Month',
                      border: OutlineInputBorder(),
                    ),
                    value: selectedMonth,
                    items: List.generate(
                      months.length,
                          (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text(months[index]),
                      ),
                    ),
                    onChanged: (value) => setState(() {
                      selectedMonth = value;
                      errorText = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: yearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 2025',
                    ),
                    onChanged: (_) => setState(() => errorText = null),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
              const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final year = int.tryParse(yearController.text);
                if (selectedMonth == null) {
                  return;
                }
                if (year == null) {
                  setState(() {
                    errorText = 'Please enter a valid numeric year.';
                  });
                  return;
                }
                if (year < 2023 || year > 2035) {
                  setState(() {
                    errorText = 'Year must be between 2023 and 2035.';
                  });
                  return;
                }

                final start = DateTime(year, selectedMonth!, 1);
                final end = DateTime(year, selectedMonth! + 1, 1)
                    .subtract(const Duration(milliseconds: 1));
                setState(() {
                  _range = DateTimeRange(start: start, end: end);
                  _monthRangeLabel = DateFormat('MMMM yyyy').format(start);
                });
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    yearController.dispose();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return const Color(0xFF2EB872);
      case 'in_progress':
        return const Color(0xFF1E88E5);
      default:
        return const Color(0xFFFFA726);
    }
  }

  // 🗑 Delete confirmation logic
  Future<void> _confirmDelete(_ReportRow r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
            'Are you sure you want to delete Report #${r.reportId.substring(0, 6)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _reportsRef.child(r.responderId).child(r.reportId).remove();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Report deleted successfully'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFC8F4E4),
            Color(0xFFA7E2C9),
            Color(0xFF7FD1AE),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Incident Reports",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF084C41),
              ),
            ),
            const SizedBox(height: 20),
            _buildFilterBar(),
            const SizedBox(height: 20),
            Expanded(
              child: Card(
                color: const Color(0xFFFAFCFF),
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _filtered.isEmpty
                      ? const Center(
                    child: Text(
                      'No reports found for selected filter.',
                      style: TextStyle(
                          color: Colors.black54, fontSize: 16),
                    ),
                  )
                      : ListView.builder(
                    padding: const EdgeInsets.only(top: 8),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) {
                      final r = _filtered[i];
                      return _build3DReportCard(r);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔍 Filter Bar with Date and Status
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ElevatedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            label: Text(
              _monthRangeLabel ?? 'Filter by Month',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _statusFilter,
            underline: const SizedBox(),
            borderRadius: BorderRadius.circular(10),
            items: const [
              DropdownMenuItem(value: 'All', child: Text('All Status')),
              DropdownMenuItem(value: 'Pending', child: Text('Pending')),
              DropdownMenuItem(
                  value: 'In_Progress', child: Text('In Progress')),
              DropdownMenuItem(value: 'Resolved', child: Text('Resolved')),
            ],
            onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _range = null;
              _statusFilter = 'All';
              _monthRangeLabel = null;
            }),
            icon: const Icon(Icons.clear),
            label: const Text('Clear'),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.teal),
            onPressed: _bind,
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _build3DReportCard(_ReportRow r) {
    final gradient = LinearGradient(
      colors: [
        _statusColor(r.status).withOpacity(0.15),
        Colors.white.withOpacity(0.9),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _statusColor(r.status).withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(3, 5),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        onTap: () => _showReportDetails(r),
        leading: Container(
          height: 45,
          width: 45,
          decoration: BoxDecoration(
            color: _statusColor(r.status),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.notes_rounded, color: Colors.white),
        ),
        title: Text(
          'Report #${r.reportId.substring(0, 6)}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Color(0xFF084C41),
          ),
        ),
        subtitle: Text(
          '${r.location}\n${r.date} • ${r.time}',
          style: const TextStyle(color: Colors.black87, height: 1.4),
        ),

        // 🔧 Updated trailing layout: centered View Map & Status + Delete Icon on right
        trailing: SizedBox(
          width: 160,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(r.status).withOpacity(0.1),
                        border: Border.all(
                          color: _statusColor(r.status).withOpacity(0.3),
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        r.status.toUpperCase(),
                        style: TextStyle(
                          color: _statusColor(r.status),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      icon: Icon(
                        Icons.location_on_rounded,
                        size: 16,
                        color: r.status.toLowerCase() == 'resolved'
                            ? Colors.green
                            : r.status.toLowerCase() == 'in_progress'
                            ? Colors.blueAccent
                            : Colors.orange,
                      ),
                      label: const Text('View Map', style: TextStyle(fontSize: 11)),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Colors.teal.shade700,
                      ),
                      onPressed: () => _showMapDialog(r),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _confirmDelete(r),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 📋 Report Details Dialog
  void _showReportDetails(_ReportRow r) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          height: 820,
          width: 1200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFFF9FFF9), Color(0xFFE8FFF3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 1,
                child:
                Padding(padding: const EdgeInsets.all(20), child: WebLiveMap(centerLat: r.lat, centerLng: r.lng)),
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.assignment_rounded,
                              color: Color(0xFF1E88E5), size: 32),
                          SizedBox(width: 10),
                          Text(
                            "Report Details",
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF084C41),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      _infoRow('Citizen', r.citizenName),
                      _infoRow('Responder', r.responderName),
                      _infoRow('Responder ID', r.responderId),
                      _infoRow('Report ID', r.reportId),
                      _infoRow('Incident Type', r.incidentType),
                      _infoRow('Date', r.date),
                      _infoRow('Time', r.time),
                      _infoRow('Location', r.location),
                      _infoRow('Description', r.description),
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: _statusColor(r.status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: Text(
                          r.status.toUpperCase(),
                          style: TextStyle(
                            color: _statusColor(r.status),
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 22),
                          label: const Text("Close"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E88E5),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(40)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: RichText(
        text: TextSpan(
          style:
          const TextStyle(color: Colors.black87, fontSize: 16),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black),
            ),
            TextSpan(text: value.isNotEmpty ? value : '-'),
          ],
        ),
      ),
    );
  }

  void _showMapDialog(_ReportRow r) {
    if (r.lat == null || r.lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("No map location available for this report."),
      ));
      return;
    }

    // ✅ Choose pin color based on status
    BitmapDescriptor pinColor;
    switch (r.status.toLowerCase()) {
      case 'resolved':
        pinColor = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
        break;
      case 'in_progress':
        pinColor = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
        break;
      default:
        pinColor = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    }

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          height: 300,
          width: 350,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(r.lat!, r.lng!),
                zoom: 15,
              ),
              markers: {
                Marker(
                  markerId: MarkerId('report_${r.reportId}'),
                  position: LatLng(r.lat!, r.lng!),
                  icon: pinColor,
                  infoWindow: InfoWindow(
                    title: r.location,
                    snippet: '${r.status.toUpperCase()} • ${r.date} ${r.time}',
                  ),
                ),
              },
            ),
          ),
        ),
      ),
    );
  }

}

// -------------------- Model --------------------
class _ReportRow {
  final String responderId;
  final String reportId;
  final String responderName;
  final String citizenName;
  final String incidentType;
  final String date;
  final String time;
  final String description;
  final String location;
  final String status;
  final double? lat;
  final double? lng;

  _ReportRow({
    required this.responderId,
    required this.reportId,
    required this.responderName,
    required this.citizenName,
    required this.incidentType,
    required this.date,
    required this.time,
    required this.description,
    required this.location,
    required this.status,
    this.lat,
    this.lng,
  });
}
