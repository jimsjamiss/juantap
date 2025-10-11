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
  const MapsLocation({super.key});

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

  final String _flaskUrl = "https://juantap-flask.onrender.com/safe-route";

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

    // ✅ Live updates
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

      // 🔎 Check danger zones continuously
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
        infoWindow: InfoWindow(title: zone["name"] ?? "Danger Zone"),
      ));

      circles.add(Circle(
        circleId: CircleId(id),
        center: pos,
        radius: (zone["radius"] as num).toDouble(),
        fillColor: Colors.redAccent.withOpacity(0.25),
        strokeColor: Colors.redAccent,
        strokeWidth: 2,
      ));
    });

    setState(() {
      _dangerZones = zones;
      _markers = markers;
      _circles = circles;
    });
  }

  // ✅ NEW: Check danger zones live while user moves
  void _checkLiveDangerZones(LatLng userPos) {
    if (_isDangerAlertVisible) return;

    for (var entry in _dangerZones.entries) {
      final zone = Map<String, dynamic>.from(entry.value);
      final LatLng center = LatLng(zone["lat"], zone["lng"]);
      final radius = (zone["radius"] as num).toDouble();
      final distance = _calculateDistance(userPos, center);

      if (distance <= radius) {
        final zoneName = zone["name"] ?? "Danger Zone";
        final message = (zone["reports"] is Map && (zone["reports"] as Map).isNotEmpty)
            ? Map<String, dynamic>.from(zone["reports"])
            .entries
            .last
            .value["message"] ??
            "You are inside a danger zone!"
            : "You are inside a danger zone!";

        _showDangerAlert(zoneName, message,
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

  // ✅ Show danger popup inside maps
  void _showDangerAlert(
      String zoneName,
      String message, {
        required LatLng userPos,
        required LatLng zoneCenter,
        required double zoneRadius,
      }) async {
    if (_isDangerAlertVisible) return;
    _isDangerAlertVisible = true;

    if (await Vibration.hasVibrator() ?? false) {
      _vibrationTimer?.cancel();
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        Vibration.vibrate(duration: 800);
      });
    }

    // try {
    //   //await _dangerPlayer.setSource(AssetSource("audio/lingling.mp3"));
    //   await _dangerPlayer.setReleaseMode(ReleaseMode.loop);
    //   await _dangerPlayer.resume();
    // } catch (e) {
    //   debugPrint("Audio error: $e");
    // }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFEFFEF5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("⚠️ Danger Zone: $zoneName"),
        content: Text(
          "$message\n\nWould you like to navigate to a safer route outside the danger area?",
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.directions, color: Colors.white),
            label: const Text("Take Alternate Route"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              _dangerPlayer.stop();
              _vibrationTimer?.cancel();
              Vibration.cancel();
              _isDangerAlertVisible = false;
              Navigator.pop(context);

              // 🧭 Find a safe destination point outside the danger zone
              const buffer = 0.0015; // ~150m offset (tune as needed)
              final random = Random();
              final angle = random.nextDouble() * 2 * pi;

              final safeLat = zoneCenter.latitude + (zoneRadius / 111320.0 + buffer) * cos(angle);
              final safeLng = zoneCenter.longitude + (zoneRadius / (111320.0 * cos(zoneCenter.latitude * pi / 180))) * sin(angle);
              final safePoint = LatLng(safeLat, safeLng);

              // 🔁 Request Flask safe route: from current position → safe point
              _drawFlaskSafeRoute(userPos, safePoint);
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.close, color: Colors.black87),
            label: const Text("Stay Here"),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.black26),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              _dangerPlayer.stop();
              _vibrationTimer?.cancel();
              Vibration.cancel();
              _isDangerAlertVisible = false;
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // ✅ Safe route request to Flask
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

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data["safe_route"] != null) {
          final route = (data["safe_route"] as List)
              .map((p) => LatLng(p[0].toDouble(), p[1].toDouble()))
              .toList();

          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId("safe_route"),
                color: Colors.green,
                width: 6,
                points: route,
              ),
            };
          });
          _moveCameraToBounds(route);
        }
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
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("JuanTap Safe Navigation"),
        backgroundColor: Colors.redAccent.shade100,
      ),
      body: (!_isPermissionGranted || _userPosition == null)
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(target: _userPosition!, zoom: 17),
        markers: _markers,
        circles: _circles,
        polylines: _polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onCameraMoveStarted: () => _followUser = false,
      ),
    );
  }
}
