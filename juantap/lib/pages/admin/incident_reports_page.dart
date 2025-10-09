import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// -------------------- Incident Reports --------------------
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

          final date = data['date'] ?? 'Unknown';
          final time = data['time'] ?? 'Unknown';
          final description = data['description'] ?? 'No description';
          final location = data['location'] ?? 'Unknown';
          final status = data['status'] ?? 'Pending';

          tmp.add(_ReportRow(
            responderId: responderId,
            reportId: reportId,
            date: date,
            time: time,
            description: description,
            location: location,
            status: status,
          ));
        }
      }

      setState(() {
        _rows = tmp.reversed.toList();
        _loading = false;
      });
    });
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Filter buttons
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range),
                label: const Text('Filter by date'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => setState(() => _range = null),
                icon: const Icon(Icons.clear),
                label: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              color: const Color(0xFFF8F7FB),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 20),
                itemBuilder: (ctx, i) {
                  final r = _rows[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    onTap: () => _showReportDetails(r),
                    leading: const Icon(Icons.description, color: Colors.orangeAccent, size: 40),
                    title: Text(
                      'Report #${r.reportId.substring(0, 6)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${r.location}\n${r.date} • ${r.time}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _statusColor(r.status).withOpacity(.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _statusColor(r.status).withOpacity(.4)),
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
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportDetails(_ReportRow r) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('📋 Report Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('Responder ID', r.responderId),
            _infoRow('Report ID', r.reportId),
            _infoRow('Date', r.date),
            _infoRow('Time', r.time),
            _infoRow('Location', r.location),
            _infoRow('Description', r.description),
            const SizedBox(height: 10),
            Text(
              'Status: ${r.status}',
              style: TextStyle(
                color: _statusColor(r.status),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87),
          children: [
            TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Colors.green;
      case 'in_progress':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }
}

// -------------------- Models --------------------
class _ReportRow {
  final String responderId;
  final String reportId;
  final String date;
  final String time;
  final String description;
  final String location;
  final String status;

  _ReportRow({
    required this.responderId,
    required this.reportId,
    required this.date,
    required this.time,
    required this.description,
    required this.location,
    required this.status,
  });
}