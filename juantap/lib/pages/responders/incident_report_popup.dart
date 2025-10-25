import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class IncidentReportPopup extends StatefulWidget {
  final String userId;
  final String userName;
  final LatLng? responderLocation;

  const IncidentReportPopup({
    super.key,
    required this.userId,
    required this.userName,
    required this.responderLocation,
  });

  @override
  State<IncidentReportPopup> createState() => _IncidentReportPopupState();
}

class _IncidentReportPopupState extends State<IncidentReportPopup> {
  final _actionStoryController = TextEditingController();
  final _timeRescuedController = TextEditingController();
  final _newIncidentController = TextEditingController();
  final _newPlaceController = TextEditingController();

  List<String> _incidentTypes = ['Crime / Assault', 'Add New Incident'];
  List<String> _incidentPlaces = ['Street', 'Market', 'School', 'Add New Place'];

  String? _selectedIncidentType;
  String? _selectedPlace;
  bool? _isResolved;

  @override
  void initState() {
    super.initState();
    _loadIncidentTypes();
    _loadIncidentPlaces();
  }

  // Load existing incident types
  Future<void> _loadIncidentTypes() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('incident_types').get();
      if (snap.exists) {
        final data = snap.value as Map;
        final loaded = data.values.map((e) => e.toString()).toList();
        setState(() => _incidentTypes = [...loaded, 'Add New Incident']);
      }
    } catch (_) {}
  }

  // Load existing places of incidents
  Future<void> _loadIncidentPlaces() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('incident_places').get();
      if (snap.exists) {
        final data = snap.value as Map;
        final loaded = data.values.map((e) => e.toString()).toList();
        setState(() => _incidentPlaces = [...loaded, 'Add New Place']);
      }
    } catch (_) {}
  }

  // Add new incident type to Firebase
  Future<void> _addNewIncidentType(String name) async {
    final ref = FirebaseDatabase.instance.ref('incident_types').push();
    await ref.set(name);
    setState(() {
      _incidentTypes.insert(_incidentTypes.length - 1, name);
      _selectedIncidentType = name;
    });
  }

  // Add new place of incident to Firebase
  Future<void> _addNewPlace(String name) async {
    final ref = FirebaseDatabase.instance.ref('incident_places').push();
    await ref.set(name);
    setState(() {
      _incidentPlaces.insert(_incidentPlaces.length - 1, name);
      _selectedPlace = name;
    });
  }

  // Prompt dialog for new incident type
  void _promptAddNewIncident() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add New Incident Type"),
        content: TextField(
          controller: _newIncidentController,
          decoration: const InputDecoration(hintText: "Enter new incident type"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final type = _newIncidentController.text.trim();
              if (type.isNotEmpty) {
                await _addNewIncidentType(type);
                _newIncidentController.clear();
                Navigator.pop(context);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // Prompt dialog for new place of incident
  void _promptAddNewPlace() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add New Place of Incident"),
        content: TextField(
          controller: _newPlaceController,
          decoration: const InputDecoration(hintText: "Enter new place (e.g., Park, Mall, Roadside)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final place = _newPlaceController.text.trim();
              if (place.isNotEmpty) {
                await _addNewPlace(place);
                _newPlaceController.clear();
                Navigator.pop(context);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  // Custom time picker
  Future<void> _pickTimeRescued() async {
    TimeOfDay selectedTime = TimeOfDay.now();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return SizedBox(
          height: 250,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text(
                  "Select Time of Rescue",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  use24hFormat: false,
                  initialDateTime: DateTime.now(),
                  onDateTimeChanged: (DateTime value) {
                    selectedTime = TimeOfDay.fromDateTime(value);
                  },
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25C09C),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  setState(() {
                    _timeRescuedController.text = selectedTime.format(context);
                  });
                  Navigator.pop(context);
                },
                child: const Text("Confirm Time", style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // Save report to Firebase
  Future<void> _submitIncidentReport() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final responderUid = user.uid;
    final responderSnap = await FirebaseDatabase.instance.ref('users/$responderUid').get();
    final responderName = (responderSnap.value as Map?)?['username'] ?? 'Unknown';
    final now = DateTime.now();

    await FirebaseDatabase.instance.ref('responder_reports/$responderUid').push().set({
      'responderName': responderName,
      'userId': widget.userId,
      'userName': widget.userName,
      'incidentType': _selectedIncidentType ?? 'Unspecified',
      'placeOfIncident': _selectedPlace ?? 'Unknown',
      'actionStory': _actionStoryController.text.trim(),
      'timeRescued': _timeRescuedController.text.trim(),
      'resolved': _isResolved == true ? 'Yes' : 'No',
      'timestamp': now.toIso8601String(),
      'latitude': widget.responderLocation?.latitude,
      'longitude': widget.responderLocation?.longitude,
    });

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incident report submitted successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: LayoutBuilder(builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF25C09C), Color(0xFF2ECC71)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                  'Incident Action Report',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),

                // INCIDENT TYPE DROPDOWN
                _buildDropdown(
                  label: 'Incident Type',
                  hint: 'Select or add new type',
                  value: _selectedIncidentType,
                  items: _incidentTypes,
                  onChanged: (v) {
                    if (v == 'Add New Incident') {
                      _promptAddNewIncident();
                    } else {
                      setState(() => _selectedIncidentType = v);
                    }
                  },
                ),

                const SizedBox(height: 12),

                // PLACE OF INCIDENT DROPDOWN
                _buildDropdown(
                  label: 'Place of Incident',
                  hint: 'Select or add new place',
                  value: _selectedPlace,
                  items: _incidentPlaces,
                  onChanged: (v) {
                    if (v == 'Add New Place') {
                      _promptAddNewPlace();
                    } else {
                      setState(() => _selectedPlace = v);
                    }
                  },
                ),

                const SizedBox(height: 12),

                _buildField(
                  'Action Story',
                  'Explain how the rescue was performed...',
                  _actionStoryController,
                  Icons.article_outlined,
                  4,
                ),
                const SizedBox(height: 12),

                // Time Rescued Picker
                GestureDetector(
                  onTap: _pickTimeRescued,
                  child: AbsorbPointer(
                    child: _buildField(
                      'Time Rescued',
                      'Tap to select time of rescue',
                      _timeRescuedController,
                      Icons.watch_later_outlined,
                      1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Was the incident resolved?',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  ChoiceChip(
                    label: const Text('Yes'),
                    selected: _isResolved == true,
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                        color: _isResolved == true ? Colors.green : Colors.black87,
                        fontWeight: FontWeight.bold),
                    onSelected: (_) => setState(() => _isResolved = true),
                  ),
                  const SizedBox(width: 16),
                  ChoiceChip(
                    label: const Text('No'),
                    selected: _isResolved == false,
                    selectedColor: Colors.white,
                    labelStyle: TextStyle(
                        color: _isResolved == false ? Colors.red : Colors.black87,
                        fontWeight: FontWeight.bold),
                    onSelected: (_) => setState(() => _isResolved = false),
                  ),
                ]),
                const SizedBox(height: 25),

                ElevatedButton.icon(
                  onPressed: _submitIncidentReport,
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  label: const Text("Submit Report",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8449),
                    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white70, fontSize: 14)),
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String hint,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
        child: DropdownButtonFormField<String>(
          value: value,
          icon: const Icon(Icons.arrow_drop_down),
          decoration: InputDecoration(border: InputBorder.none, hintText: hint),
          items: items.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
          onChanged: onChanged,
        ),
      ),
    ]);
  }

  Widget _buildField(
      String label,
      String hint,
      TextEditingController c,
      IconData icon,
      int maxLines, {
        bool readOnly = false,
        VoidCallback? onTap,
      }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      const SizedBox(height: 6),
      TextField(
        controller: c,
        readOnly: readOnly,
        onTap: onTap,
        maxLines: maxLines,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.teal[700]),
          filled: true,
          fillColor: Colors.white,
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black54, fontSize: 13),
          border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        ),
      ),
    ]);
  }
}
