// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:location/location.dart' as loc;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:http/http.dart' as http;

import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class MapsLocation extends StatefulWidget {
  /// Optional latitude & longitude when opening from an SOS alert
  final double? latitude;
  final double? longitude;

  const MapsLocation({
    super.key,
    this.latitude,
    this.longitude,
  });

  @override
  State<MapsLocation> createState() => _MapsLocationState();
}

class _MapsLocationState extends State<MapsLocation> {
  // 🔐 Current user id (for "This is YOUR SOS alert")
  String? _currentUserId;

  // 🔥 Global SOS alerts (from only_sos_alerts)
  final List<Map<String, dynamic>> _sosAlerts = [];

  // 🗺️ Location + map
  final loc.Location _location = loc.Location();
  GoogleMapController? _mapController;
  LatLng? _userPosition;
  bool _isPermissionGranted = false;

  // ⚠️ Danger zones
  final DatabaseReference dbRef = FirebaseDatabase.instance.ref("danger_zones");
  Map<String, dynamic> _dangerZones = {};
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  Set<Polyline> _polylines = {};
  Set<Polygon> _polygons = {};

  StreamSubscription<loc.LocationData>? _locationSubscription;
  final AudioPlayer _dangerPlayer = AudioPlayer();
  Timer? _vibrationTimer;
  bool _isDangerAlertVisible = false;
  bool _followUser = true;
  DateTime? _nextAllowedAlertTime; // cooldown for danger popup

  // ✅ Your Flask ML safe-route endpoint
  final String _flaskUrl = "https://juantap.onrender.com/ml-safe-route";
  // final String _flaskUrl = "http://192.168.1.3:5000/ml-safe-route";

  @override
  void initState() {
    super.initState();
    _loadCurrentUserId();
    _initializeLocation();
    _listenToDangerZones();
    _loadSOSAlerts(); // load ALL SOS alerts for right-side button
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _dangerPlayer.dispose();
    _vibrationTimer?.cancel();
    super.dispose();
  }

  // ======================================================
  // 🕒 Timestamp Formatter (NEW)
  // ======================================================
  String _formatTimestamp(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'N/A';
    try {
      final dateTime = DateTime.parse(isoString);
      // Example format: "Nov 17, 2025 at 8:12 PM"
      return DateFormat('MMM d, yyyy h:mm a').format(dateTime.toLocal());
    } catch (e) {
      debugPrint("Failed to parse timestamp: $e");
      return isoString; // Fallback to raw string
    }
  }

  // ======================================================
  // 🔐 Load current user ID (SharedPreferences + Auth fallback)
  // ======================================================
  Future<void> _loadCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? uid = prefs.getString('uid') ?? prefs.getString('userId');

      // Fallback to FirebaseAuth if ever available
      uid = uid ?? FirebaseAuth.instance.currentUser?.uid;

      setState(() {
        _currentUserId = uid;
      });

      debugPrint("👤 Current user id in MapsLocation: $_currentUserId");
    } catch (e) {
      debugPrint("⚠️ Failed to load current user id: $e");
    }
  }

  // ======================================================
  // 🗺️ Initialize location & live updates
  // ======================================================
  Future<void> _initializeLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    var permission = await _location.hasPermission();
    if (permission == loc.PermissionStatus.denied) {
      permission = await _location.requestPermission();
      if (permission != loc.PermissionStatus.granted) return;
    }

    final current = await _location.getLocation();
    if (!mounted) return;

    setState(() {
      _userPosition = LatLng(current.latitude!, current.longitude!);
      _isPermissionGranted = true;
    });

    _locationSubscription = _location.onLocationChanged.listen((newLoc) {
      if (!mounted) return;
      if (newLoc.latitude == null || newLoc.longitude == null) return;

      final newPos = LatLng(newLoc.latitude!, newLoc.longitude!);
      setState(() => _userPosition = newPos);

      if (_followUser && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(newPos, 17),
        );
      }

      _checkLiveDangerZones(newPos);
    });
  }

  // ======================================================
  // 🎥 Video player for SOS proof
  // ======================================================
  Future<ChewieController> _initializeVideoPlayer(String url) async {
    final videoPlayerController = VideoPlayerController.network(url);
    await videoPlayerController.initialize();
    return ChewieController(
      videoPlayerController: videoPlayerController,
      autoPlay: false,
      looping: false,
      allowFullScreen: true,
      allowPlaybackSpeedChanging: true,
      aspectRatio: videoPlayerController.value.aspectRatio,
    );
  }

  // ======================================================
  // 🔺 Polygon point-in-polygon
  // ======================================================
  bool _isInsidePolygon(LatLng point, List poly) {
    int intersectCount = 0;
    for (int j = 0; j < poly.length - 1; j++) {
      final p1 = poly[j];
      final p2 = poly[j + 1];

      double lat1 = (p1["lat"] as num).toDouble();
      double lng1 = (p1["lng"] as num).toDouble();
      double lat2 = (p2["lat"] as num).toDouble();
      double lng2 = (p2["lng"] as num).toDouble();

      if (((lng1 <= point.longitude && point.longitude < lng2) ||
          (lng2 <= point.longitude && point.longitude < lng1)) &&
          (point.latitude <
              (lat2 - lat1) * (point.longitude - lng1) / (lng2 - lng1) + lat1)) {
        intersectCount++;
      }
    }
    return (intersectCount % 2) == 1;
  }

  LatLng _getPolygonCentroid(List poly) {
    double sumLat = 0;
    double sumLng = 0;
    for (var p in poly) {
      sumLat += (p["lat"] as num).toDouble();
      sumLng += (p["lng"] as num).toDouble();
    }
    return LatLng(sumLat / poly.length, sumLng / poly.length);
  }

  // ======================================================
  // Small info row
  // ======================================================
  Widget _infoRow(IconData icon, String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black54),
          const SizedBox(width: 6),
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

  // ======================================================
  // 🧾 Single SOS card (with "YOUR SOS" tag)
  // ======================================================
  Widget _buildSOSCard(Map<String, dynamic> s) {
    final bool isOwn = _currentUserId != null && s["userId"] == _currentUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOwn)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                "This is YOUR SOS alert",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: s["profileImage"] != null && s["profileImage"] != ""
                    ? NetworkImage(s["profileImage"])
                    : null,
                child: (s["profileImage"] == null || s["profileImage"] == "")
                    ? const Icon(Icons.person, size: 28)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "${s["username"] ?? "Unknown User"}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(Icons.email, "Email", s["email"]),
          _infoRow(Icons.phone, "Phone", s["phone"]),
          _infoRow(Icons.calendar_today, "Birthdate", s["birthdate"]),
          _infoRow(Icons.home, "Address", s["address"]),
          _infoRow(Icons.flag, "Nationality", s["nationality"]),
          _infoRow(Icons.gavel, "Crime Type", s["crimeType"]),
          const SizedBox(height: 10),

          // 🔥 Proof (image or video)
          if (s["proofUrl"] != null && s["proofUrl"] != "")
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "SOS Proof:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                if (s["isVideo"] == false)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      s["proofUrl"],
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (s["isVideo"] == true)
                  SizedBox(
                    height: 220,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: FutureBuilder(
                        future: _initializeVideoPlayer(s["proofUrl"]),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return const Center(child: Text("Error loading video"));
                          }
                          final chewieController = snapshot.data as ChewieController?;
                          if (chewieController == null) {
                            return const Center(child: Text("No video controller"));
                          }
                          return Chewie(controller: chewieController);
                        },
                      ),
                    ),
                  ),
              ],
            ),

          const SizedBox(height: 10),
          // Row(
          //   children: [
          //     const Icon(Icons.access_time, size: 16, color: Colors.black54),
          //     const SizedBox(width: 4),
          //     Text(
          //       s["timestamp"] ?? "",
          //       style: const TextStyle(fontSize: 13),
          //     ),
          //   ],
          // ),
          _infoRow(Icons.access_time, "Timestamp", _formatTimestamp(s["timestamp"])),
        ],
      ),
    );
  }

  // ======================================================
  // 🔥 Load ALL SOS alerts from only_sos_alerts
  // ======================================================
  void _loadSOSAlerts() {
    final sosRef = FirebaseDatabase.instance.ref('only_sos_alerts');

    sosRef.onValue.listen((event) {
      if (!event.snapshot.exists) {
        setState(() => _sosAlerts.clear());
        return;
      }

      final Map<dynamic, dynamic> users =
      Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      final List<Map<String, dynamic>> loaded = [];

      users.forEach((userId, alerts) {
        final Map<dynamic, dynamic> alertMap = Map<dynamic, dynamic>.from(alerts);
        alertMap.forEach((alertId, data) {
          final a = Map<String, dynamic>.from(data);

          if (a['location'] == null) return;
          final locMap = Map<String, dynamic>.from(a['location']);

          loaded.add({
            'id': alertId,
            'userId': userId,
            'username': a['username'] ?? 'Unknown',
            'reason': a['reason'] ?? 'SOS Alert',
            'crimeType': a['crimeType'] ?? 'Not specified',
            'proofUrl': a['proofUrl'] ?? '',
            'isVideo': a['isVideo'] ?? false,
            'address': a['address'] ?? '',
            'birthdate': a['birthdate'] ?? '',
            'email': a['email'] ?? '',
            'nationality': a['nationality'] ?? '',
            'phone': a['phone'] ?? '',
            'profileImage': a['profileImage'] ?? '',
            'lat': (locMap['lat'] as num).toDouble(),
            'lng': (locMap['lng'] as num).toDouble(),
            'placeName': locMap['placeName'] ?? 'Unknown area',
            'timestamp': a['timestamp'] ?? '',
          });
        });
      });

      setState(() {
        _sosAlerts
          ..clear()
          ..addAll(loaded);
      });

      debugPrint("📊 User-side loaded SOS alerts: ${_sosAlerts.length}");
    });
  }

  // ======================================================
  // 📡 Firebase listener for danger zones
  // ======================================================
  void _listenToDangerZones() {
    dbRef.onValue.listen((event) {
      if (!mounted) return;
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        _updateDangerZoneMarkers(data);
      }
    });
  }

  void _updateDangerZoneMarkers(Map<String, dynamic> zones) {
    final markers = <Marker>{};
    final circles = <Circle>{};
    final polygons = <Polygon>{};

    zones.forEach((id, zoneData) {
      if (zoneData is! Map) return;
      final zone = (zoneData as Map).map((key, value) {
        return MapEntry(key.toString(), value);
      });

      final double zLat = (zone["lat"] as num?)?.toDouble() ?? 0;
      final double zLng = (zone["lng"] as num?)?.toDouble() ?? 0;
      final LatLng pos = LatLng(zLat, zLng);

      // MARKER
      markers.add(
        Marker(
          markerId: MarkerId(id),
          position: pos,
          infoWindow: const InfoWindow(), // no Google default popup
          onTap: () {
            Future.delayed(const Duration(milliseconds: 80), () {
              final zoneData = _dangerZones[id];
              if (zoneData != null) {
                _showZoneInfo(Map<String, dynamic>.from(zoneData as Map));
              }
            });
          },
        ),
      );

      // CIRCLE (for non-polygon zones)
      if (zone["polygon"] == null) {
        circles.add(
          Circle(
            circleId: CircleId(id),
            center: pos,
            radius: ((zone["radius"] ?? 120) as num).toDouble(),
            fillColor: Colors.orangeAccent.withOpacity(0.25),
            strokeColor: Colors.orangeAccent,
            strokeWidth: 2,
            consumeTapEvents: true,
            onTap: () {
              Future.delayed(const Duration(milliseconds: 80), () {
                final zoneData = _dangerZones[id];
                if (zoneData != null) {
                  _showZoneInfo(Map<String, dynamic>.from(zoneData as Map));
                }
              });
            },
          ),
        );
      }

      // POLYGON
      if (zone["polygon"] != null && zone["polygon"] is List) {
        final List poly = zone["polygon"];

        // 1. Get true center
        final LatLng center = _getPolygonCentroid(poly);

        // 2. How much bigger you want the polygon (scale)
        const double scale = 5.0;

        // 3. Scale each vertex outward
        final polygonPoints = poly.map((p) {
          final vertex = LatLng(
            (p["lat"] as num).toDouble(),
            (p["lng"] as num).toDouble(),
          );
          return _inflateVertex(vertex, center, scale);
        }).toList();

        polygons.add(
          Polygon(
            polygonId: PolygonId(id),
            points: polygonPoints,
            strokeWidth: 2,
            fillColor: _getSeverityColor(zone),
            strokeColor: Colors.black.withOpacity(0.3),
          ),
        );
      }
    });

    setState(() {
      _dangerZones = zones;
      _markers = markers;
      _circles = circles;
      _polygons = polygons;
    });

    debugPrint("🧱 Updated danger zones: ${_dangerZones.length}");
  }

  // ======================================================
  // ✅ Check danger zones live
  // ======================================================
  void _checkLiveDangerZones(LatLng userPos) {
    if (_isDangerAlertVisible) return;

    for (var entry in _dangerZones.entries) {
      final zone = Map<String, dynamic>.from(entry.value);
      final double zLat = (zone["lat"] as num).toDouble();
      final double zLng = (zone["lng"] as num).toDouble();
      final LatLng center = LatLng(zLat, zLng);

      final String severity = zone["severity"] ?? "low";
      String severityText = "Monitored Area";

      if (severity == "high") {
        severityText = "⚠️ HIGH THREAT AREA ⚠️";
      } else if (severity == "medium") {
        severityText = "⚠️ MEDIUM THREAT AREA ⚠️";
      } else {
        severityText = "Low Threat Area";
      }

      // Polygon detection first
      if (zone["polygon"] != null && zone["polygon"] is List && (zone["polygon"] as List).isNotEmpty) {
        final List poly = zone["polygon"];
        if (_isInsidePolygon(userPos, poly)) {
          _triggerSmartAlert(
            zoneName: severityText,
            zone: zone,
            userPos: userPos,
            zoneCenter: center,
          );
          return;
        }
      }

      // Circle fallback detection (using admin radius)
      final double radius = ((zone["radius"] ?? 120) as num).toDouble();
      final double distance = _calculateDistance(userPos, center);

      if (distance <= radius) {
        _triggerSmartAlert(
          zoneName: severityText,
          zone: zone,
          userPos: userPos,
          zoneCenter: center,
        );
        return;
      }
    }
  }

  void _triggerSmartAlert({
    required String zoneName,
    required Map<String, dynamic> zone,
    required LatLng userPos,
    required LatLng zoneCenter,
  }) {
    // 🔥 Respect cooldown before showing popup
    if (_nextAllowedAlertTime != null && DateTime.now().isBefore(_nextAllowedAlertTime!)) {
      return;
    }
    if (_isDangerAlertVisible) return;

    final double zoneRadius = ((zone["radius"] ?? 120) as num).toDouble();
    final message = "You are entering a $zoneName.\n"
        "Stay alert and be aware of your surroundings.";

    _showGentleAlert(
      zoneName,
      message,
      userPos: userPos,
      zoneCenter: zoneCenter,
      zoneRadius: zoneRadius,
    );
  }

  // ======================================================
  // 🔺 Inflate polygon point outward
  // ======================================================
  LatLng _inflateVertex(LatLng vertex, LatLng center, double scale) {
    final newLat = center.latitude + (vertex.latitude - center.latitude) * scale;
    final newLng = center.longitude + (vertex.longitude - center.longitude) * scale;
    return LatLng(newLat, newLng);
  }

  // ======================================================
  // 📏 Distance (meters)
  // ======================================================
  double _calculateDistance(LatLng p1, LatLng p2) {
    const R = 6371000;
    final dLat = (p2.latitude - p1.latitude) * pi / 180;
    final dLon = (p2.longitude - p1.longitude) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(p1.latitude * pi / 180) *
            cos(p2.latitude * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  // ======================================================
  // 🎯 Generate safe point outside danger zone (your working version)
  // ======================================================
  LatLng _generateSafePoint(LatLng dangerCenter, double radiusMeters) {
    const double buffer = 80; // ensures it's outside the danger zone
    final double safeDistance = radiusMeters + buffer;
    final double angle = Random().nextDouble() * 2 * pi;

    final double offsetLat = (safeDistance / 111320) * cos(angle);
    final double offsetLng =
        (safeDistance / (111320 * cos(dangerCenter.latitude * pi / 180))) *
            sin(angle);

    final safePoint = LatLng(
      dangerCenter.latitude + offsetLat,
      dangerCenter.longitude + offsetLng,
    );

    debugPrint(
        "🟢 Generated safe point outside danger zone: ${safePoint.latitude}, ${safePoint.longitude}");
    return safePoint;
  }

  // ======================================================
  // 💬 Gentle alert dialog (now calling Flask reroute)
  // ======================================================
  void _showGentleAlert(
      String zoneName,
      String message, {
        required LatLng userPos,
        required LatLng zoneCenter,
        required double zoneRadius,
      }) async {
    if (_isDangerAlertVisible) return;
    _isDangerAlertVisible = true;

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 400);
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE8FFF1), Color(0xFFD3F8EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 48, color: Color(0xFF2EB872)),
                const SizedBox(height: 10),
                Text(
                  "You’re in a Monitored Area",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.teal.shade800,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF3A4A43),
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(thickness: 1.2, color: Color(0xFFB7E2C1)),
                const SizedBox(height: 10),
                const Text(
                  "Would you like to take a safer route outside this area?",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF4E6B60),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.directions_walk, color: Colors.white),
                      label: const Text("Find Safer Route"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2EB872),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        // 🔥 5-minute cooldown
                        _nextAllowedAlertTime =
                            DateTime.now().add(const Duration(minutes: 5));

                        _isDangerAlertVisible = false;
                        Navigator.pop(context);

                        // ✅ Generate safe point outside the zone using your working logic
                        final safePoint =
                        _generateSafePoint(zoneCenter, zoneRadius);

                        debugPrint(
                            "🧭 Safe Point: ${safePoint.latitude}, ${safePoint.longitude}");

                        // ✅ Call Flask ML safe route
                        _drawFlaskSafeRoute(
                          userPos,
                          safePoint,
                          zoneCenter: zoneCenter,  // 👈 pass zone center
                          radius: zoneRadius,
                        );
                      },
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF7B8F84)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        // 🔥 10-minute cooldown
                        _nextAllowedAlertTime =
                            DateTime.now().add(const Duration(minutes: 10));
                        _isDangerAlertVisible = false;
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "Stay Here",
                        style: TextStyle(
                          color: Color(0xFF4E6B60),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ======================================================
  // 🧠 Safe route using Flask ML API (your working rerouting)
  // ======================================================
  Future<void> _drawFlaskSafeRoute(
      LatLng start,
      LatLng end, {
        required LatLng zoneCenter,
        required double radius,
      }) async {
    // Ensure radius always has a value
    final double safeRadius = (radius <= 0) ? 120.0 : radius;

    final Map<String, dynamic> payload = {
      "origin": [start.longitude, start.latitude],
      "destination": [end.longitude, end.latitude],
      "danger_zone": {
        "center": [zoneCenter.longitude, zoneCenter.latitude],
        "radius": safeRadius,
      },
    };


    debugPrint("📤 FINAL PAYLOAD SENT TO FLASK: ${json.encode(payload)}"); // <--- VERY IMPORTANT FOR DEBUGGING

    try {
      final res = await http.post(
        Uri.parse(_flaskUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode(payload),
      );

      debugPrint("📡 Flask response: ${res.statusCode}");
      debugPrint("📥 Flask body: ${res.body}");

      if (res.statusCode == 200) {
        final data = json.decode(res.body);

        if (data["route_analysis"] != null) {
          final List<LatLng> pts = [];
          for (final p in data["route_analysis"]) {
            pts.add(LatLng(
              (p["lat"] as num).toDouble(),
              (p["lng"] as num).toDouble(),
            ));
          }

          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId("safe_route"),
                color: Colors.teal,
                width: 6,
                points: pts,
              ),
            };
          });

          _moveCameraToBounds(pts);
        }
      } else {
        debugPrint("❌ Flask error response: ${res.body}");
      }
    } catch (e) {
      debugPrint("❌ Error calling safe-route API: $e");
    }
  }



  Future<void> _moveCameraToBounds(List<LatLng> points) async {
    if (_mapController == null || points.isEmpty) return;

    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;

    for (var p in points) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }

    LatLngBounds bounds =
    LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  // ======================================================
  // 🎨 Severity color
  // ======================================================
  Color _getSeverityColor(Map<String, dynamic> z) {
    final severity = z["severity"] ?? "low";
    switch (severity) {
      case "high":
        return Colors.red.withOpacity(0.35);
      case "medium":
        return Colors.orange.withOpacity(0.35);
      default:
        return Colors.yellow.withOpacity(0.35);
    }
  }

  // [maps_location.dart] - Replace the entire _showZoneInfo function with this updated version

  // ======================================================
  // 🧊 Zone info popup (from danger_zones) - UPDATED
  // ======================================================
  void _showZoneInfo(Map<String, dynamic> zone) {
    // 1. Get Zone boundaries for filtering
    final double zoneLat = (zone["lat"] as num?)?.toDouble() ?? 0.0;
    final double zoneLng = (zone["lng"] as num?)?.toDouble() ?? 0.0;
    final LatLng zoneCenter = LatLng(zoneLat, zoneLng);
    final double zoneRadius = ((zone["radius"] ?? 120) as num).toDouble();
    final List poly = (zone["polygon"] ?? []) as List;
    final String zoneName = zone["name"] ?? "Danger Zone";

    // 2. Filter the global _sosAlerts list to find alerts within this zone.
    final List<Map<String, dynamic>> filteredSosAlerts = _sosAlerts.where((alert) {
      final double alertLat = alert['lat'] as double;
      final double alertLng = alert['lng'] as double;
      final LatLng alertLoc = LatLng(alertLat, alertLng);

      // Check if the alert location is inside the polygon (if one exists)
      if (poly.isNotEmpty && _isInsidePolygon(alertLoc, poly)) {
        return true;
      }

      // Check if the alert location is within the circular radius
      final double distance = _calculateDistance(alertLoc, zoneCenter);
      if (distance <= zoneRadius) {
        return true;
      }

      return false;
    }).toList();

    // The list to be displayed is now the filtered list.
    final sosList = filteredSosAlerts;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 60,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  zoneName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Severity: ${zone["severity"]?.toString().toUpperCase() ?? "UNKNOWN"}",
                  style: const TextStyle(fontSize: 16),
                ),
                // 💥 This count now reflects the filtered list, matching the other views' data source
                Text(
                  "Total SOS Reports: ${sosList.length}",
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Expanded(
                  child: sosList.isEmpty
                      ? const Center(
                    child: Text(
                      "No recent SOS alerts recorded in this area.",
                      style: TextStyle(fontSize: 15, color: Colors.black54),
                    ),
                  )
                      : ListView.builder(
                    itemCount: sosList.length,
                    itemBuilder: (context, index) {
                      // 💥 We use the complete, rich alert data directly from the filtered list.
                      final alert = sosList[index];
                      return _buildSOSCard(alert);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ======================================================
  // 📌 GROUP SOS BY PLACE (for button list)
  // ======================================================
  Map<String, List<Map<String, dynamic>>> _groupSOSByPlace() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    const double maxDistanceMeters = 10;

    for (var s in _sosAlerts) {
      final place = s['placeName'] ?? 'Unknown Area';
      final LatLng loc = LatLng(s['lat'] as double, s['lng'] as double);
      bool inserted = false;

      for (var key in grouped.keys) {
        final first = grouped[key]!.first;
        final LatLng firstLoc = LatLng(first['lat'] as double, first['lng'] as double);

        if (key == place) {
          final double d = _calculateDistance(loc, firstLoc);
          if (d <= maxDistanceMeters) {
            grouped[key]!.add(s);
            inserted = true;
            break;
          }
        }
      }

      if (!inserted) {
        grouped.putIfAbsent(place, () => []);
        grouped[place]!.add(s);
      }
    }

    return grouped;
  }

  // ======================================================
  // 🎯 Move map to center of a group
  // ======================================================
  void _goToSOSGroupCenter(List<Map<String, dynamic>> alerts) {
    if (alerts.isEmpty || _mapController == null) return;

    final double avgLat =
        alerts.map((a) => a['lat'] as double).reduce((a, b) => a + b) / alerts.length;
    final double avgLng =
        alerts.map((a) => a['lng'] as double).reduce((a, b) => a + b) / alerts.length;

    final LatLng target = LatLng(avgLat, avgLng);

    _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, 17));
  }

  // ======================================================
  // 🔍 Popup for ONE location group (all SOS there)
  // ======================================================
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
            height: MediaQuery.of(context).size.height * 0.80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "📍 $place",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 15),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: alerts.map((s) => _buildSOSCard(s)).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ======================================================
  // 🔘 OPEN ALL SOS LIST (button on right side)
  // ======================================================
  void _openAllSOSBottomSheet() {
    if (_sosAlerts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No SOS alerts detected in the system yet."),
        ),
      );
      return;
    }

    final groupedSOS = _groupSOSByPlace();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (ctx, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 60,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Nearby SOS Alerts",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      children: groupedSOS.entries.map((entry) {
                        final place = entry.key;
                        final alerts = entry.value;
                        final bool hasOwn = _currentUserId != null &&
                            alerts.any((s) => s["userId"] == _currentUserId);

                        return GestureDetector(
                          onTap: () => _openSOSPopup(place, alerts),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFFFCDD2),
                                  Color(0xFFFFEBEE),
                                ],
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
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
                                const SizedBox(height: 6),
                                if (hasOwn)
                                  const Text(
                                    "You have SOS alert(s) in this area.",
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    TextButton(
                                      onPressed: () => _openSOSPopup(place, alerts),
                                      child: const Text("View Details"),
                                    ),
                                  ],
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
          },
        );
      },
    );
  }

  // ======================================================
  // 🧱 BUILD
  // ======================================================
  @override
  Widget build(BuildContext context) {
    final LatLng initialTarget = widget.latitude != null && widget.longitude != null
        ? LatLng(widget.latitude!, widget.longitude!)
        : (_userPosition ?? const LatLng(10.3157, 123.8854));

    return Scaffold(
      appBar: AppBar(
        title: const Text("JuanTap Safe Navigation"),
        backgroundColor: Colors.teal.shade300,
      ),
      body: (!_isPermissionGranted && widget.latitude == null)
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(target: initialTarget, zoom: 17),
        markers: {
          ..._markers,
          if (widget.latitude != null && widget.longitude != null)
            Marker(
              markerId: const MarkerId('alert'),
              position: initialTarget,
              infoWindow: const InfoWindow(title: "SOS Alert Location"),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
            ),
        },
        polygons: _polygons,
        circles: _circles,
        polylines: _polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onCameraMoveStarted: () => _followUser = false,
        onTap: (_) {},
      ),
      // 🔥 Button on the right side to show ALL SOS alerts
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAllSOSBottomSheet,
        backgroundColor: Colors.redAccent,
        icon: const Icon(Icons.warning_amber_outlined),
        label: const Text(
          "SOS around you",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
