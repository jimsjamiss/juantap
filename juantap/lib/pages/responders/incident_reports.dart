import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class IncidentReportsResponder extends StatefulWidget {
  const IncidentReportsResponder({super.key});

  @override
  State<IncidentReportsResponder> createState() =>
      _IncidentReportsResponderState();
}

class _IncidentReportsResponderState extends State<IncidentReportsResponder> {
  final DatabaseReference _reportsRef =
  FirebaseDatabase.instance.ref('responder_reports');
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _filteredReports = [];

  bool _isLoading = true;

  String _selectedType = 'All';
  String _selectedStatus = 'All';

  List<String> _incidentTypes = ['All'];
  final List<String> _statusOptions = ['All', 'Resolved', 'Not Resolved'];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (_currentUser == null) return;

    final snapshot = await _reportsRef.child(_currentUser!.uid).get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final List<Map<String, dynamic>> loaded = [];

      data.forEach((key, value) {
        loaded.add({
          'id': key,
          ...Map<String, dynamic>.from(value),
        });
      });

      loaded.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

      final uniqueTypes = loaded
          .map((r) => (r['incidentType'] ?? 'Unknown').toString())
          .toSet()
          .toList()
        ..sort();

      setState(() {
        _reports = loaded;
        _filteredReports = List.from(loaded);
        _incidentTypes = ['All', ...uniqueTypes];
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredReports = _reports.where((report) {
        final typeMatch =
            _selectedType == 'All' || report['incidentType'] == _selectedType;
        final resolved =
            (report['resolved'] ?? '').toString().toLowerCase() == "yes";
        final statusMatch = _selectedStatus == 'All' ||
            (_selectedStatus == 'Resolved' && resolved) ||
            (_selectedStatus == 'Not Resolved' && !resolved);
        return typeMatch && statusMatch;
      }).toList();
    });
  }

  String _formatDate(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('MMM d, yyyy – h:mm a').format(dt);
    } catch (_) {
      return "Unknown";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
        title: const Text(
          "Incident Reports",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: const BackButton(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _reports.isEmpty
          ? const Center(
        child: Text(
          "No incident reports yet.",
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadReports,
        color: const Color(0xFF1E8449),
        child: Column(
          children: [
            _buildFilterSection(),
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _filteredReports.length,
                itemBuilder: (context, index) {
                  final report = _filteredReports[index];
                  return _buildReportCard(report);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF21867A),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Filter Reports",
            style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Incident Type",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedType,
                            items: _incidentTypes
                                .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type,
                                  overflow: TextOverflow.ellipsis),
                            ))
                                .toList(),
                            onChanged: (value) {
                              setState(() => _selectedType = value!);
                              _applyFilters();
                            },
                            icon: const Icon(Icons.arrow_drop_down),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Status",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedStatus,
                            items: _statusOptions
                                .map((status) => DropdownMenuItem(
                              value: status,
                              child: Text(status),
                            ))
                                .toList(),
                            onChanged: (value) {
                              setState(() => _selectedStatus = value!);
                              _applyFilters();
                            },
                            icon: const Icon(Icons.arrow_drop_down),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final bool resolved =
        (report['resolved'] ?? '').toString().toLowerCase() == "yes";
    final LatLng? location = (report['latitude'] != null &&
        report['longitude'] != null)
        ? LatLng(report['latitude'], report['longitude'])
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            resolved ? const Color(0xFF25C09C) : const Color(0xFFFF6B6B),
            resolved ? const Color(0xFF2ECC71) : const Color(0xFFFF8E53),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                resolved ? Icons.check_circle : Icons.error_outline,
                color: Colors.white,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  report['incidentType'] ?? "Unknown Type",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildInfoRow(
              Icons.person, "Citizen", report['userName'] ?? "Unknown"),
          _buildInfoRow(
              Icons.badge, "Responder", report['responderName'] ?? "Unknown"),
          _buildInfoRow(Icons.schedule, "Time Rescued",
              report['timeRescued'] ?? "N/A"),
          _buildInfoRow(Icons.calendar_today, "Reported At",
              _formatDate(report['timestamp'])),
          _buildInfoRow(Icons.place, "Place of Incident",
              report['placeOfIncident'] ?? "Unknown"),
          const Divider(color: Colors.white30, height: 20),
          Text(
            "Action Story",
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              report['actionStory'] ?? "No details provided.",
              style:
              const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
            ),
          ),
          if (location != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    "Lat: ${location.latitude.toStringAsFixed(5)}, Lng: ${location.longitude.toStringAsFixed(5)}",
                    style:
                    const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 6),
          Text(
            "$label: ",
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
