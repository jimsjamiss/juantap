// lib/pages/admin/geofencing_page.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class GeofencingPage extends StatefulWidget {
  const GeofencingPage({super.key});

  @override
  State<GeofencingPage> createState() => _GeofencingPageState();
}

class _GeofencingPageState extends State<GeofencingPage> {
  late final DatabaseReference _zonesRef;
  GoogleMapController? _mapCtrl;
  final Set<Circle> _circles = {};
  final Set<Marker> _markers = {};
  final _labelCtrl = TextEditingController();
  double _radius = 150; // meters

  @override
  void initState() {
    super.initState();
    _zonesRef = FirebaseDatabase.instance.ref('danger_zones');
    _loadZones();
  }

  void _loadZones() {
    _zonesRef.onValue.listen((e) {
      final Set<Circle> circles = {};
      final Set<Marker> marks = {};
      for (final z in e.snapshot.children) {
        final label = (z.child('label').value ?? 'Danger Zone') as String;
        final lat = (z.child('center/lat').value ?? 0).toString();
        final lng = (z.child('center/lng').value ?? 0).toString();
        final radius = (z.child('radiusMeters').value ?? 100).toString();
        final center =
        LatLng(double.tryParse(lat) ?? 0, double.tryParse(lng) ?? 0);

        circles.add(Circle(
          circleId: CircleId(z.key!),
          center: center,
          radius: double.tryParse(radius) ?? 100,
          strokeWidth: 2,
          strokeColor: Colors.redAccent,
          fillColor: Colors.redAccent.withOpacity(.12),
        ));

        marks.add(Marker(
          markerId: MarkerId('m_${z.key}'),
          position: center,
          infoWindow: InfoWindow(title: label),
        ));
      }
      setState(() {
        _circles
          ..clear()
          ..addAll(circles);
        _markers
          ..clear()
          ..addAll(marks);
      });
    });
  }

  Future<void> _saveZone(LatLng center, String label, double radius) async {
    final id = _zonesRef.push().key!;
    await _zonesRef.child(id).set({
      'label': label.isEmpty ? 'Danger Zone' : label,
      'type': 'circle',
      'center': {'lat': center.latitude, 'lng': center.longitude},
      'radiusMeters': radius,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Danger zone saved')),
      );
    }
  }

  void _onLongPress(LatLng latLng) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Danger Zone',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: Colors.redAccent),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Label (e.g., High Crime Area)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Radius:'),
                    Expanded(
                      child: Slider(
                        min: 50,
                        max: 500,
                        divisions: 9,
                        value: _radius,
                        label: '${_radius.toStringAsFixed(0)} m',
                        activeColor: Colors.redAccent,
                        onChanged: (v) => setState(() => _radius = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _saveZone(latLng, _labelCtrl.text.trim(), _radius);
                          _labelCtrl.clear();
                        },
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: const Text('Save Zone',
                            style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultCenter =
    const LatLng(10.3236, 123.9221); // default: Mandaue City

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: const [
                Icon(Icons.info, color: Colors.redAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '💡 Long-press on the map to add a circular danger zone',
                    style: TextStyle(color: Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: GoogleMap(
            initialCameraPosition:
            CameraPosition(target: defaultCenter, zoom: 13),
            onMapCreated: (c) => _mapCtrl = c,
            markers: _markers,
            circles: _circles,
            onLongPress: _onLongPress,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
        ),
      ],
    );
  }
}