import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc;
import 'package:firebase_database/firebase_database.dart';
import 'package:audioplayers/audioplayers.dart'; // ✅ import

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
  DateTime? _lastPopupTime;

  final DatabaseReference dbRef = FirebaseDatabase.instance.ref("danger_zones");
  Map<String, dynamic> _dangerZones = {};

  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  Set<Polyline> _polylines = {};

  final AudioPlayer _audioPlayer = AudioPlayer(); // ✅ player
  bool _isAlertVisible = false; // ✅ flag to prevent multiple popups

  @override
  void initState() {
    super.initState();
    _initializeLocation();
    _listenToDangerZones();

    _location.onLocationChanged.listen((newLoc) {
      if (_isPermissionGranted &&
          newLoc.latitude != null &&
          newLoc.longitude != null) {
        final newPos = LatLng(newLoc.latitude!, newLoc.longitude!);
        setState(() {
          _userPosition = newPos;
        });
        _checkIfInDangerZone(newPos);
      }
    });
  }

  Future<void> _initializeLocation() async {
    bool serviceEnabled;
    loc.PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) return;
    }

    final currentLocation = await _location.getLocation();

    setState(() {
      _userPosition =
          LatLng(currentLocation.latitude!, currentLocation.longitude!);
      _isPermissionGranted = true;
    });
  }

  void _listenToDangerZones() {
    dbRef.onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        _updateDangerZones(data);
      }
    });
  }

  void _updateDangerZones(Map<String, dynamic> zones) {
    Set<Marker> markers = {};
    Set<Circle> circles = {};

    zones.forEach((id, zoneData) {
      final zone = Map<String, dynamic>.from(zoneData);
      final LatLng position = LatLng(zone["lat"], zone["lng"]);

      final Map<String, dynamic> reports =
      (zone["reports"] is Map)
          ? Map<String, dynamic>.from(zone["reports"] as Map)
          : <String, dynamic>{};

      final reportList = reports.entries.toList();

      markers.add(
        Marker(
          markerId: MarkerId(id),
          position: position,
          infoWindow: InfoWindow(
            title: zone["name"],
            snippet: "Reports: ${reportList.length}\nTap to view details",
            onTap: () {
              showModalBottomSheet(
                context: context,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (context) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(zone["name"],
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text("Total Reports: ${reportList.length}",
                            style: const TextStyle(
                                fontSize: 14, color: Colors.redAccent)),
                        const SizedBox(height: 10),
                        if (reportList.isEmpty)
                          const Text("No reports yet. Stay cautious.",
                              style: TextStyle(color: Colors.grey))
                        else
                          SizedBox(
                            height: 200,
                            child: ListView.builder(
                              itemCount: reportList.length,
                              itemBuilder: (context, index) {
                                final report = Map<String, dynamic>.from(
                                    reportList[index].value);
                                return Card(
                                  margin:
                                  const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: const Icon(Icons.warning,
                                        color: Colors.redAccent),
                                    title: Text(report["message"] ??
                                        "No message provided"),
                                    subtitle: Text(report["timestamp"] ?? ""),
                                  ),
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 15),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Close"),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      );

      circles.add(
        Circle(
          circleId: CircleId(id),
          center: position,
          radius: (zone["radius"] as num).toDouble(),
          fillColor: Colors.red.withOpacity(0.2),
          strokeColor: Colors.red,
          strokeWidth: 2,
        ),
      );
    });

    setState(() {
      _dangerZones = zones;
      _markers = markers;
      _circles = circles;
    });
  }

  void _checkIfInDangerZone(LatLng userPos) {
    for (var zoneEntry in _dangerZones.entries) {
      final zone = Map<String, dynamic>.from(zoneEntry.value);
      final zoneCenter = LatLng(zone["lat"], zone["lng"]);
      final zoneRadius = (zone["radius"] as num).toDouble();

      final distance = _calculateDistance(userPos, zoneCenter);

      if (distance <= zoneRadius) {
        // ✅ Play alarm in loop
        _playAlarm();

        // ✅ Use most recent report if available
        final reports = (zone["reports"] is Map)
            ? Map<String, dynamic>.from(zone["reports"] as Map)
            : <String, dynamic>{};
        String message = "You are inside a danger zone!";
        if (reports.isNotEmpty) {
          final lastReport = reports.entries.last.value;
          message = lastReport["message"] ?? message;
        }

        _showDangerAlert(zone["name"], message);
        _drawSafePath(userPos, zoneCenter, zoneRadius);
        break;
      } else {
        setState(() => _polylines.clear());
      }
    }
  }

  Future<void> _playAlarm() async {
    await _audioPlayer.stop(); // stop if already playing
    await _audioPlayer.play(
      AssetSource("sounds/lingling.mp3"),
      volume: 1.0,
      // ✅ loop the alarm until stopped
      mode: PlayerMode.mediaPlayer,
    );
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  double _calculateDistance(LatLng pos1, LatLng pos2) {
    const earthRadius = 6371000;
    final dLat = (pos2.latitude - pos1.latitude) * (pi / 180);
    final dLng = (pos2.longitude - pos1.longitude) * (pi / 180);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(pos1.latitude * (pi / 180)) *
            cos(pos2.latitude * (pi / 180)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  void _drawSafePath(LatLng userPos, LatLng zoneCenter, double radius) {
    final dx = userPos.latitude - zoneCenter.latitude;
    final dy = userPos.longitude - zoneCenter.longitude;

    final magnitude = sqrt(dx * dx + dy * dy);
    final unitDx = dx / magnitude;
    final unitDy = dy / magnitude;

    final escapeLat = zoneCenter.latitude + unitDx * ((radius + 30) / 111320);
    final escapeLng = zoneCenter.longitude +
        unitDy * ((radius + 30) /
            (111320 * cos(userPos.latitude * pi / 180)));

    final escapePoint = LatLng(escapeLat, escapeLng);

    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId("safe_path"),
          points: [userPos, escapePoint],
          color: Colors.green,
          width: 5,
        ),
      };
    });
  }

  void _showDangerAlert(String zoneName, String message) {
    final now = DateTime.now();
    // ✅ Only show popup if at least 30s passed since last
    if (_lastPopupTime != null &&
        now.difference(_lastPopupTime!).inSeconds < 30) {
      return;
    }
    _lastPopupTime = now;

    if (_isAlertVisible) return; // ✅ prevent multiple dialogs at same time
    _isAlertVisible = true;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("⚠️ $zoneName"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              _audioPlayer.stop(); // ✅ stop alarm
              _isAlertVisible = false; // ✅ reset flag
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }


  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("JuanTap Map"),
        backgroundColor: const Color(0xFF4B8B7A),
      ),
      body: !_isPermissionGranted || _userPosition == null
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: _userPosition!,
          zoom: 15,
        ),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: false,
        markers: _markers,
        circles: _circles,
        polylines: _polylines,
      ),
    );
  }
}