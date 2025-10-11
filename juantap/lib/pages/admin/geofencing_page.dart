import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';

class GeofencingPage extends StatefulWidget {
  const GeofencingPage({super.key});

  @override
  State<GeofencingPage> createState() => _GeofencingPageState();
}

class _GeofencingPageState extends State<GeofencingPage>
    with SingleTickerProviderStateMixin {
  late final DatabaseReference _zonesRef;
  final MapController _mapCtrl = MapController();

  final List<Map<String, dynamic>> _zones = [];
  final _labelCtrl = TextEditingController();
  double _radius = 150;

  String? _focusedZoneId;
  LatLng? _focusedPosition;
  double _pulseRadius = 0;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    _zonesRef = FirebaseDatabase.instance.ref('danger_zones');
    _loadZones();
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }

  // 🔁 Load zones
  void _loadZones() {
    _zonesRef.onValue.listen((event) {
      if (!event.snapshot.exists) return;
      final Map<dynamic, dynamic> zones =
      Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final List<Map<String, dynamic>> loadedZones = [];

      zones.forEach((id, data) {
        final z = Map<String, dynamic>.from(data);
        loadedZones.add({
          'id': id,
          'name': z['name'] ?? z['label'] ?? 'Unnamed Zone',
          'lat': (z['lat'] as num?)?.toDouble() ?? 0,
          'lng': (z['lng'] as num?)?.toDouble() ?? 0,
          'radius': (z['radius'] as num?)?.toDouble() ?? 100,
        });
      });

      setState(() {
        _zones
          ..clear()
          ..addAll(loadedZones);
      });
    });
  }

  // 💾 Save new zone (fixed)
  Future<void> _saveZone(LatLng center, String label, double radius) async {
    final id = _zonesRef.push().key!;

    await _zonesRef.child(id).set({
      'name': label.isEmpty ? 'Danger Zone' : label,
      'lat': center.latitude,
      'lng': center.longitude,
      'radius': radius,
      'created_at': DateTime.now().toIso8601String(),
      'report_count': 0, // ✅ new counter field
      'reports': {}, // ✅ proper structure
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Danger zone added successfully')),
    );
  }

  // 🧹 Fix existing invalid zones
  Future<void> _cleanOldZones() async {
    final snapshot = await _zonesRef.get();

    if (snapshot.exists) {
      final zones = Map<String, dynamic>.from(snapshot.value as Map);

      int fixedCount = 0;
      for (var entry in zones.entries) {
        final id = entry.key;
        final zone = Map<String, dynamic>.from(entry.value);

        if (zone["reports"] is Map &&
            (zone["reports"] as Map).containsKey("reports_count")) {
          await _zonesRef.child(id).update({
            "reports": {}, // ✅ clean structure
            "report_count": 0, // ✅ separate count field
          });
          fixedCount++;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🧹 Fixed $fixedCount old zone(s) successfully!"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // 🗑️ Delete zone
  Future<void> _deleteZone(String id) async {
    await _zonesRef.child(id).remove();
    setState(() => _zones.removeWhere((z) => z['id'] == id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🗑️ Zone deleted successfully')),
    );
  }

  // ⚠️ Confirmation delete popup
  void _confirmDelete(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFFF9FFF9), Color(0xFFE8FFF3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(3, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              const Text(
                "Delete Zone?",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF084C41),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Are you sure you want to delete “$name”?",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deleteZone(id);
                    },
                    icon: const Icon(Icons.delete_forever_rounded,
                        color: Colors.white, size: 18),
                    label: const Text("Delete",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      elevation: 6,
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF1E88E5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(
                          color: Color(0xFF1E88E5),
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 📍 Add zone modal
  void _openAddZoneDialog(LatLng latLng) {
    double tempRadius = _radius;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFF9FFF9), Color(0xFFE8FFF3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            top: 24,
            left: 20,
            right: 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "New Danger Zone",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF084C41),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _labelCtrl,
                    decoration: InputDecoration(
                      prefixIcon:
                      const Icon(Icons.label_outline, color: Colors.black54),
                      labelText: "Zone Label (e.g. High Crime Area)",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      fillColor: Colors.white,
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, color: Colors.redAccent),
                        onPressed: () => setModalState(() =>
                        tempRadius = (tempRadius - 10).clamp(50, 1000)),
                      ),
                      Expanded(
                        child: Slider(
                          min: 50,
                          max: 1000,
                          divisions: 95,
                          value: tempRadius,
                          activeColor: Colors.teal,
                          onChanged: (v) => setModalState(() => tempRadius = v),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.green),
                        onPressed: () => setModalState(() =>
                        tempRadius = (tempRadius + 10).clamp(50, 1000)),
                      ),
                      Text("${tempRadius.toStringAsFixed(0)} m"),
                    ],
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E88E5),
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(40),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 14),
                    ),
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text(
                      "Save Zone",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() => _radius = tempRadius);
                      _saveZone(latLng, _labelCtrl.text.trim(), tempRadius);
                      _labelCtrl.clear();
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // 🗺️ Tap to add
  void _onTap(LatLng latLng) => _openAddZoneDialog(latLng);

  // 🎯 Focus zone animation
  void _focusOnZone(Map<String, dynamic> zone) {
    final LatLng target = LatLng(zone['lat'], zone['lng']);
    final double radius = zone['radius'];
    _mapCtrl.move(target, 17);
    setState(() {
      _focusedZoneId = zone['id'];
      _focusedPosition = target;
      _pulseRadius = 0;
    });

    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      setState(() {
        _pulseRadius += 8;
        if (_pulseRadius >= radius) _pulseRadius = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    const defaultCenter = LatLng(10.3236, 123.9221);

    final List<Marker> markers = _zones.map((z) {
      final bool isFocused = z['id'] == _focusedZoneId;
      return Marker(
        width: isFocused ? 50 : 40,
        height: isFocused ? 50 : 40,
        point: LatLng(z['lat'], z['lng']),
        child: Icon(
          Icons.warning_amber_rounded,
          color: isFocused ? Colors.orangeAccent : Colors.deepOrange,
          size: isFocused ? 48 : 36,
        ),
      );
    }).toList();

    final List<CircleMarker> circles = [
      ..._zones.map((z) => CircleMarker(
        point: LatLng(z['lat'], z['lng']),
        color: Colors.orange.withOpacity(0.25),
        borderStrokeWidth: 2,
        borderColor: Colors.deepOrange,
        useRadiusInMeter: true,
        radius: z['radius'],
      )),
      if (_focusedPosition != null && _focusedZoneId != null)
        CircleMarker(
          point: _focusedPosition!,
          color: Colors.orangeAccent.withOpacity(0.2),
          borderStrokeWidth: 1.5,
          borderColor: Colors.orangeAccent,
          useRadiusInMeter: true,
          radius: _pulseRadius,
        ),
    ];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFC8F4E4), Color(0xFFA7E2C9), Color(0xFF7FD1AE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 🗺️ Map Section
            Expanded(
              flex: 3,
              child: Card(
                color: const Color(0xFFFAFCFF),
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: defaultCenter,
                    initialZoom: 15,
                    onTap: (_, latlng) => _onTap(latlng),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.juantap.admin',
                    ),
                    CircleLayer(circles: circles),
                    MarkerLayer(markers: markers),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),

            // 📋 Right Panel
            Expanded(flex: 2, child: _buildRightPanel()),
          ],
        ),
      ),
    );
  }

  // 📋 Right panel
  Widget _buildRightPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFF),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.teal.withOpacity(0.15),
            blurRadius: 10,
            offset: const Offset(3, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Geofencing Zones",
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF084C41),
            ),
          ),
          const Divider(height: 24),

          // 🧹 Fix Old Zones Button
          ElevatedButton.icon(
            onPressed: _cleanOldZones,
            icon: const Icon(Icons.cleaning_services_rounded),
            label: const Text("Fix Old Zones"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.location_pin, color: Colors.deepOrange),
              const SizedBox(width: 8),
              Text(
                "Total Zones: ${_zones.length}",
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black87),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _zones.length,
              itemBuilder: (context, index) {
                final zone = _zones[index];
                final bool isFocused = _focusedZoneId == zone['id'];
                return Container(
                  margin:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isFocused
                          ? [Color(0xFFFFE0B2), Color(0xFFFFCC80)]
                          : [Color(0xFFFFF3E0), Color(0xFFFFEFD5)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(3, 3),
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.deepOrange,
                      child: Icon(Icons.warning_amber_rounded,
                          color: Colors.white),
                    ),
                    title: Text(
                      zone['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF084C41),
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      "Lat: ${zone['lat'].toStringAsFixed(4)}, Lng: ${zone['lng'].toStringAsFixed(4)}",
                      style:
                      TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Color(0xFF1E88E5)),
                      onPressed: () => _confirmDelete(
                          zone['id'].toString(), zone['name'].toString()),
                    ),
                    onTap: () => _focusOnZone(zone),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
