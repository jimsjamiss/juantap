import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:latlong2/latlong.dart' show Distance;
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';





class GeofencingPage extends StatefulWidget {
  const GeofencingPage({super.key});

  @override
  State<GeofencingPage> createState() => _GeofencingPageState();
}

class _GeofencingPageState extends State<GeofencingPage>
    with SingleTickerProviderStateMixin {
  late final DatabaseReference _zonesRef;
  final MapController _mapCtrl = MapController();
  final Distance _distance = Distance();
  final List<Map<String, dynamic>> _sosZones = [];
  final List<Map<String, dynamic>> _zones = [];
  final _labelCtrl = TextEditingController();
  double _radius = 40;

  String? _focusedZoneId;
  LatLng? _focusedPosition;
  double _pulseRadius = 0;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    _zonesRef = FirebaseDatabase.instance.ref('danger_zones');
    _loadZones();
    _loadSOSZones();    // automatic SOS zones
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

  void _loadSOSZones() {
    final sosRef = FirebaseDatabase.instance.ref('only_sos_alerts');

    sosRef.onValue.listen((event) {
      if (!event.snapshot.exists) return;

      final Map<dynamic, dynamic> users =
      Map<dynamic, dynamic>.from(event.snapshot.value as Map);

      final List<Map<String, dynamic>> loadedSOS = [];

      users.forEach((userId, alerts) {
        final Map<dynamic, dynamic> alertMap =
        Map<dynamic, dynamic>.from(alerts);

        alertMap.forEach((alertId, data) {
          final a = Map<String, dynamic>.from(data);

          if (a['location'] == null) return;

          final loc = Map<String, dynamic>.from(a['location']);

          loadedSOS.add({
            'id': alertId,
            'userId': userId,
            'username': a['username'] ?? 'Unknown',
            'reason': a['reason'] ?? 'SOS Alert',

            'crimeType': a['crimeType'] ?? 'Not specified',
            'proofUrl': a['proofUrl'] ?? '',
            'isVideo': a['isVideo'] ?? false,


            // 🟢 NEW: FULL USER DETAILS
            'address': a['address'] ?? '',
            'birthdate': a['birthdate'] ?? '',
            'email': a['email'] ?? '',
            'nationality': a['nationality'] ?? '',
            'phone': a['phone'] ?? '',
            'profileImage': a['profileImage'] ?? '',

            // Location details
            'lat': (loc['lat'] as num).toDouble(),
            'lng': (loc['lng'] as num).toDouble(),
            'placeName': loc['placeName'] ?? 'Unknown area',

            'timestamp': a['timestamp'] ?? '',
          });
        });
      });

      setState(() {
        _sosZones
          ..clear()
          ..addAll(loadedSOS);
      });

      // 👇 auto-detect clusters once SOS zones update
      _detectDangerClusters();
    });
  }

  Future<ChewieController> _initializeVideoPlayer(String url) async {
    final videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    await videoPlayerController.initialize();

    return ChewieController(
      videoPlayerController: videoPlayerController,
      autoPlay: false,
      looping: false,
      allowFullScreen: true,
      allowPlaybackSpeedChanging: true,
      autoInitialize: true,
    );
  }

  void _goToSOSGroupCenter(List<Map<String, dynamic>> alerts) {
    if (alerts.isEmpty) return;

    // compute center
    final double avgLat = alerts.map((a) => a['lat'] as double).reduce((a, b) => a + b) / alerts.length;
    final double avgLng = alerts.map((a) => a['lng'] as double).reduce((a, b) => a + b) / alerts.length;

    final LatLng target = LatLng(avgLat, avgLng);

    // zoom into the zone
    _mapCtrl.move(target, 17);
  }


  void _detectDangerClusters() async {
    if (_sosZones.length < 3) return;

    const double clusterRadius = 120; // meters

    List<Map<String, dynamic>> processed = [];

    for (var p in _sosZones) {
      if (processed.contains(p)) continue;

      List<Map<String, dynamic>> cluster = [];

      for (var q in _sosZones) {
        final double d = _distance(
          LatLng(p['lat'], p['lng']),
          LatLng(q['lat'], q['lng']),
        );

        if (d <= clusterRadius) {
          cluster.add(q);
        }
      }

      // Cluster found
      if (cluster.length >= 3) {
        // Compute average center
        double avgLat = cluster
            .map((c) => c['lat'] as double)
            .reduce((a, b) => a + b) /
            cluster.length;

        double avgLng = cluster
            .map((c) => c['lng'] as double)
            .reduce((a, b) => a + b) /
            cluster.length;

        // Compute radius
        double maxDist = 0;
        for (var c in cluster) {
          double d2 = _distance(
            LatLng(avgLat, avgLng),
            LatLng(c['lat'], c['lng']),
          );
          if (d2 > maxDist) maxDist = d2;
        }

        final double finalRadius = (maxDist + 5).clamp(10, 40);

        // Check if similar zone already exists
        final exists = _zones.any((z) =>
        (z['lat'] - avgLat).abs() < 0.0004 &&
            (z['lng'] - avgLng).abs() < 0.0004);

        if (!exists) {
          final id = _zonesRef.push().key!;

          // Generate a MUCH smaller polygon
          final polygon = _generateSmallPolygon(avgLat, avgLng, 10);  // 10 meters small

          // Save polygon to Firebase (instead of circle radius)
          await _zonesRef.child(id).set({
            "name": cluster.first['placeName'] ?? "Auto Danger Zone",
            "lat": avgLat,
            "lng": avgLng,
            "polygon": polygon
                .map((p) => {"lat": p.latitude, "lng": p.longitude})
                .toList(),
            "autoGenerated": true,
            "created_at": DateTime.now().toIso8601String(),

            // 👇 ADD THIS — store all SOS details inside the zone
            "sos_details": cluster.map((s) {
              return {
                "id": s["id"],
                "userId": s["userId"],
                "username": s["username"],
                "reason": s["reason"],
                "lat": s["lat"],
                "lng": s["lng"],
                "placeName": s["placeName"],
                "timestamp": s["timestamp"],
              };
            }).toList(),
          });
          print("🔥 Auto-danger polygon created at $avgLat, $avgLng");
        }


        processed.addAll(cluster);
      }
    }
  }

  // ======================================================
// SMALL CUSTOM POLYGON GENERATOR (adjustable meters)
// ======================================================
  List<LatLng> _generateSmallPolygon(double lat, double lng, double meterRadius) {
    const double scale = 0.000009; // degrees per meter

    return List.generate(12, (i) {
      final angle = i * 30 * math.pi / 180;
      final dx = meterRadius * scale * math.cos(angle);
      final dy = meterRadius * scale * math.sin(angle);
      return LatLng(lat + dy, lng + dx);
    });
  }


// ===============================
// ORS Isochrone Polygon Generator
// ===============================
  Future<List<LatLng>> _getORSIsochronePolygon(double lat, double lng) async {
    const orsApiKey = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjZkNTQ2YzZmZmE0ZDQ0Yzc5OWFiMTQ3Yzg2ZTllZTI5IiwiaCI6Im11cm11cjY0In0=";

    final url = Uri.parse(
        "https://api.openrouteservice.org/v2/isochrones/foot-walking");

    final body = {
      "locations": [
        [lng, lat]
      ],
      "range": [10],      // radius in meters
      "range_type": "distance",
      "units": "m"
    };

    final response = await http.post(
      url,
      headers: {
        "Authorization": orsApiKey,
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      print("ORS Isochrone Error: ${response.body}");
      return [];
    }

    final data = jsonDecode(response.body);

    final coords = data["features"][0]["geometry"]["coordinates"][0];

    List<LatLng> polygon = coords
        .map<LatLng>((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
        .toList();

    print("🔶 ORS polygon generated with ${polygon.length} points");
    return polygon;
  }


  // 💾 Save new zone (fixed)
  Future<void> _saveZone(LatLng center, String label, double radius) async {
    final id = _zonesRef.push().key!;

    await _zonesRef.child(id).set({
      'name': label.isEmpty ? 'Danger Zone' : label,
      'lat': center.latitude,
      'lng': center.longitude,
      'radius': radius,
      'autoGenerated': false,
      'created_at': DateTime.now().toIso8601String(),
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

    final List<Marker> markers = [
      // Existing manual danger zones
      ..._zones.map((z) {
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
      }),

      // 🔥 NEW: SOS Alert danger points
      ..._sosZones.map((s) {
        return Marker(
          width: 40,
          height: 40,
          point: LatLng(s['lat'], s['lng']),
          child: const Icon(
            Icons.location_history,
            color: Colors.red,
            size: 38,
          ),
        );
      }),
    ];


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
                    PolygonLayer(
                      polygons: [
                        // ======================================
                        // 🆕 ORS polygons (auto-generated danger zones)
                        // ======================================
                        ..._zones.map((z) {
                          if (z["polygon"] == null) return null;               // ⛔ skip null
                          if (z["polygon"] is! List) return null;              // ⛔ skip wrong type
                          if ((z["polygon"] as List).isEmpty) return null;     // ⛔ skip empty list

                          final List<dynamic> coords = z["polygon"];
                          final List<LatLng> polygonPoints = coords
                              .map((c) => LatLng(c["lat"], c["lng"]))
                              .toList();

                          return Polygon(
                            points: polygonPoints,
                            color: Colors.orange.withOpacity(0.25),
                            borderColor: Colors.deepOrange,
                            borderStrokeWidth: 2,
                          );
                        }).where((p) => p != null).cast<Polygon>(),

                        // ======================================
                        // Manual zones converted to circle-polygons
                        // ======================================
                        ..._zones.map((z) {
                          final center = LatLng(z['lat'], z['lng']);
                          final radius = z['radius'].toDouble();

                          final points = List.generate(12, (i) {
                            final angle = (i * 30) * 3.1415 / 180;
                            final dx = radius * 0.000005 * math.cos(angle);
                            final dy = radius * 0.000005 * math.sin(angle);
                            return LatLng(center.latitude + dy, center.longitude + dx);
                          });

                          return Polygon(
                            points: points,
                            color: Colors.orange.withOpacity(0.25),
                            borderColor: Colors.deepOrange,
                            borderStrokeWidth: 2,
                          );
                        }),

                        // ======================================
                        // Focused zone pulse
                        // ======================================
                        if (_focusedPosition != null && _focusedZoneId != null)
                          Polygon(
                            points: List.generate(12, (i) {
                              final angle = (i * 30) * 3.1415 / 180;
                              final dx = _pulseRadius * 0.000009 * math.cos(angle);
                              final dy = _pulseRadius * 0.000009 * math.sin(angle);
                              return LatLng(
                                _focusedPosition!.latitude + dy,
                                _focusedPosition!.longitude + dx,
                              );
                            }),
                            color: Colors.orangeAccent.withOpacity(0.15),
                            borderColor: Colors.orangeAccent,
                            borderStrokeWidth: 2,
                          ),
                      ],
                    ),
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

  Map<String, List<Map<String, dynamic>>> _groupSOSByPlace() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    const double maxDistanceMeters = 10; // treat <10 meters = same location

    for (var s in _sosZones) {
      final place = s['placeName'] ?? 'Unknown Area';
      final LatLng loc = LatLng(s['lat'], s['lng']);

      bool inserted = false;

      // check if there is already a group with same placeName & nearby location
      for (var key in grouped.keys) {
        final first = grouped[key]!.first;
        final LatLng firstLoc = LatLng(first['lat'], first['lng']);

        // only group if placeName matches
        if (key == place) {
          final double d = _distance(loc, firstLoc);

          if (d <= maxDistanceMeters) {
            grouped[key]!.add(s);
            inserted = true;
            break;
          }
        }
      }

      // If no existing group matched → create new group
      if (!inserted) {
        grouped.putIfAbsent(place, () => []);
        grouped[place]!.add(s);
      }
    }

    return grouped;
  }


  void _openSOSPopup(String place, List<Map<String, dynamic>> alerts) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            width: 450,

            // ⭐ LIMIT HEIGHT (prevents overflow)
            height: MediaQuery.of(context).size.height * 0.80,

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  "📍 $place",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 15),

                // ⭐ MAKE FULL CONTENT SCROLLABLE
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: alerts.map((s) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 20),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [

                              // USERNAME & TITLE
                              Text(
                                "${s['username']} - ${s['reason']}",
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // PROFILE IMAGE
                              if (s['profileImage'] != null &&
                                  s['profileImage'] != "")
                                Center(
                                  child: CircleAvatar(
                                    radius: 35,
                                    backgroundImage:
                                    NetworkImage(s['profileImage']),
                                  ),
                                ),

                              const SizedBox(height: 10),

                              // DETAILS
                              _infoRow(Icons.email, "Email", s['email']),
                              _infoRow(Icons.phone, "Phone", s['phone']),
                              _infoRow(Icons.calendar_today, "Birthdate",
                                  s['birthdate']),
                              _infoRow(Icons.home, "Address", s['address']),
                              _infoRow(Icons.flag, "Nationality",
                                  s['nationality']),

                              const SizedBox(height: 8),
                              // 🔥 SHOW CRIME TYPE (IF AVAILABLE)
                              if (s['crimeType'] != null && s['crimeType'] != "")
                                _infoRow(Icons.gavel, "Crime Type", s['crimeType']),

                              const SizedBox(height: 10),

// 🔥 SHOW PROOF (IMAGE OR VIDEO)
                              if (s['proofUrl'] != null && s['proofUrl'] != "")
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "SOS Proof:",
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 8),

                                    // IMAGE
                                    if (s['isVideo'] == false)
                                      GestureDetector(
                                        onTap: () {
                                          showDialog(
                                            context: context,
                                            builder: (_) => Dialog(
                                              child: Image.network(s['proofUrl']),
                                            ),
                                          );
                                        },
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: Image.network(
                                            s['proofUrl'],
                                            height: 180,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),

                                    // VIDEO (thumbnail only)
                                    // 🎥 VIDEO PROOF PLAYER
                                    if (s['isVideo'] == true)
                                      SizedBox(
                                        height: 220,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: FutureBuilder(
                                            future: _initializeVideoPlayer(s['proofUrl']),
                                            builder: (context, snapshot) {
                                              if (snapshot.connectionState == ConnectionState.waiting) {
                                                return const Center(child: CircularProgressIndicator());
                                              }
                                              if (snapshot.hasError) {
                                                return const Center(child: Text("Error loading video"));
                                              }

                                              return Chewie(
                                                controller: snapshot.data as ChewieController,
                                              );
                                            },
                                          ),
                                        ),
                                      ),

                                  ],
                                ),

                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.access_time,
                                      size: 16, color: Colors.black54),
                                  const SizedBox(width: 6),
                                  Text(
                                    s['timestamp'],
                                    style: const TextStyle(
                                        color: Colors.black87, fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // CLOSE BUTTON
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close"),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

// ⭐ Reusable info row widget
  Widget _infoRow(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "$label: $value",
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }



  // 📋 Right panel
  Widget _buildRightPanel() {
    final groupedSOS = _groupSOSByPlace();

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

          const Divider(height: 2),

          // CLEAN OLD ZONES BUTTON
          const SizedBox(height: 16),

          // ------------------------------
          // MANUAL ZONES LIST
          // ------------------------------
          const SizedBox(height: 8),

          const SizedBox(height: 20),

          // ------------------------------
          // SOS GROUPED SECTION
          // ------------------------------
          const Text(
            "SOS Alerts (Automatically Detected)",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          Text(
            "SOS Alerts: ${_sosZones.length}",
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          // ------------------------------
// SOS GROUPED SECTION
// ------------------------------
          Expanded(
            child: ListView(
              children: groupedSOS.entries.map((entry) {
                final place = entry.key;
                final alerts = entry.value;

                return GestureDetector(
                  onTap: () => _openSOSPopup(place, alerts),   // 👈 POPUP
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFCDD2), Color(0xFFFFEBEE)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withOpacity(0.25),
                          blurRadius: 8,
                          offset: const Offset(3, 3),
                        ),
                      ],
                    ),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // 🔴 PLACE NAME + ALERT COUNT
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                "📍 $place",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ),

                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${alerts.length} alerts",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // 🗺️ VIEW ON MAP BUTTON
                        ElevatedButton.icon(
                          onPressed: () => _goToSOSGroupCenter(alerts),
                          icon: const Icon(Icons.map, color: Colors.white),
                          label: const Text(
                            "View on Map",
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                );

              }).toList(),
            ),
          ),

        ],
      ),
    );
  }
}
