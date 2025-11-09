import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:location/location.dart' as loc;
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:http/http.dart' as http;

class MapsLocation extends StatefulWidget {
  /// ✅ Added optional latitude & longitude (fixes your `alert['lat']` / `alert['lng']` error)
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
  final loc.Location _location = loc.Location();
  GoogleMapController? _mapController;
  LatLng? _userPosition;
  bool _isPermissionGranted = false;

  final DatabaseReference dbRef = FirebaseDatabase.instance.ref("danger_zones");
  Map<String, dynamic> _dangerZones = {};
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  Set<Polyline> _polylines = {};

  StreamSubscription<loc.LocationData>? _locationSubscription;
  final AudioPlayer _dangerPlayer = AudioPlayer();
  Timer? _vibrationTimer;
  bool _isDangerAlertVisible = false;
  bool _followUser = true;

  final String _flaskUrl = "https://juantap.onrender.com/ml-safe-route";
  // final String _flaskUrl = "http://192.168.1.3:5000/ml-safe-route";

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _listenToDangerZones();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _dangerPlayer.dispose();
    _vibrationTimer?.cancel();
    super.dispose();
  }

  // ✅ Initialize location and live monitoring
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

  // ✅ Firebase listener for danger zones
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

    zones.forEach((id, zoneData) {
      if (zoneData is! Map) return;
      final zone = Map<String, dynamic>.from(zoneData);
      final LatLng pos = LatLng(zone["lat"], zone["lng"]);

      markers.add(Marker(
        markerId: MarkerId(id),
        position: pos,
        infoWindow: InfoWindow(title: zone["name"] ?? "Monitored Area"),
      ));

      circles.add(Circle(
        circleId: CircleId(id),
        center: pos,
        radius: (zone["radius"] as num).toDouble(),
        fillColor: Colors.orangeAccent.withOpacity(0.20),
        strokeColor: Colors.orangeAccent,
        strokeWidth: 2,
      ));
    });

    setState(() {
      _dangerZones = zones;
      _markers = markers;
      _circles = circles;
    });
  }

  // ✅ Check danger zones live while user moves
  void _checkLiveDangerZones(LatLng userPos) {
    if (_isDangerAlertVisible) return;

    for (var entry in _dangerZones.entries) {
      final zone = Map<String, dynamic>.from(entry.value);
      final LatLng center = LatLng(zone["lat"], zone["lng"]);
      final radius = (zone["radius"] as num).toDouble();
      final distance = _calculateDistance(userPos, center);

      if (distance <= radius) {
        final zoneName = zone["name"] ?? "Monitored Area";
        final message = "You’re currently in or near $zoneName. "
            "Please stay alert and be aware of your surroundings.";

        _showGentleAlert(zoneName, message,
            userPos: userPos, zoneCenter: center, zoneRadius: radius);
        break;
      }
    }
  }

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
                      icon:
                      const Icon(Icons.directions_walk, color: Colors.white),
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
                        _isDangerAlertVisible = false;
                        Navigator.pop(context);

                        // ✅ Generate safe point outside the zone
                        final safePoint =
                        _generateSafePoint(zoneCenter, zoneRadius);

                        debugPrint(
                            "🧭 Safe Point: ${safePoint.latitude}, ${safePoint.longitude}");

                        _drawFlaskSafeRoute(userPos, safePoint);
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

  Future<void> _drawFlaskSafeRoute(LatLng start, LatLng end) async {
    final body = json.encode({
      "origin": [start.longitude, start.latitude],
      "destination": [end.longitude, end.latitude],
    });

    try {
      final res = await http.post(
        Uri.parse(_flaskUrl),
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      debugPrint("📡 Flask response: ${res.statusCode}");

      if (res.statusCode == 200) {
        final data = json.decode(res.body);

        if (data["route_analysis"] != null) {
          final routePoints = <LatLng>[];
          for (final p in data["route_analysis"]) {
            routePoints.add(LatLng(p["lat"], p["lng"]));
          }

          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId("safe_route"),
                color: Colors.teal,
                width: 6,
                points: routePoints,
              ),
            };
          });

          _moveCameraToBounds(routePoints);
        } else {
          debugPrint("⚠️ No route_analysis returned from Flask");
        }
      } else {
        debugPrint("❌ Flask error: ${res.body}");
      }
    } catch (e) {
      debugPrint("Flask safe route error: $e");
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

  @override
  Widget build(BuildContext context) {
    // ✅ Added safe handling if latitude/longitude are provided from alert
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
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
        },
        circles: _circles,
        polylines: _polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onCameraMoveStarted: () => _followUser = false,
      ),
    );
  }
}
