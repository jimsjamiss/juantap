// 📦 Full updated IncidentReportsPage — with live Web Map centered on report location
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'web_live_map.dart'; // ✅ Import your real-time web map widget

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
  String _statusFilter = 'All';

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
          tmp.add(_ReportRow(
            responderId: responderId,
            reportId: reportId,
            date: data['date'] ?? 'Unknown',
            time: data['time'] ?? 'Unknown',
            description: data['description'] ?? 'No description',
            location: data['location'] ?? 'Unknown',
            status: data['status'] ?? 'Pending',
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
            return d.isAfter(_range!.start) && d.isBefore(_range!.end);
          }
          return false;
        } catch (_) {
          return false;
        }
      }).toList();
    }
    return filtered;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) setState(() => _range = picked);
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
            icon: const Icon(Icons.date_range, color: Colors.white),
            label: const Text(
              'Filter by date',
              style: TextStyle(
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
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _range = null;
              _statusFilter = 'All';
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
            boxShadow: [
              BoxShadow(
                color: _statusColor(r.status).withOpacity(0.4),
                blurRadius: 6,
                offset: const Offset(2, 3),
              ),
            ],
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
          style: const TextStyle(
            color: Colors.black87,
            height: 1.4,
            fontSize: 13,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              icon: const Icon(Icons.map_outlined, size: 14),
              label:
              const Text('View Map', style: TextStyle(fontSize: 11)),
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
    );
  }

  // 🧾 Report Details Dialog — uses live map centered on report location
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
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withOpacity(0.15),
                blurRadius: 18,
                offset: const Offset(4, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // ✅ Live map focuses on specific report coordinates
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: WebLiveMap(
                    centerLat: r.lat,
                    centerLng: r.lng,
                  ),
                ),
              ),

              // 🧾 Right side info
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
                      _infoRow('Responder ID', r.responderId),
                      _infoRow('Report ID', r.reportId),
                      _infoRow('Date', r.date),
                      _infoRow('Time', r.time),
                      _infoRow('Location', r.location),
                      _infoRow('Description', r.description),
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color:
                          _statusColor(r.status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color:
                              _statusColor(r.status).withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(2, 4),
                            ),
                          ],
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
                          label: const Text(
                            "Close",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E88E5),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(40),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 30, vertical: 16),
                            elevation: 6,
                            shadowColor:
                            const Color(0xFF1E88E5).withOpacity(0.4),
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
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            TextSpan(text: value.isNotEmpty ? value : '-'),
          ],
        ),
      ),
    );
  }

  void _showMapDialog(_ReportRow r) {
    if (r.lat == null || r.lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No map location available for this report."),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  markerId: const MarkerId('report'),
                  position: LatLng(r.lat!, r.lng!),
                  infoWindow: InfoWindow(title: r.location),
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
    required this.date,
    required this.time,
    required this.description,
    required this.location,
    required this.status,
    this.lat,
    this.lng,
  });
}
