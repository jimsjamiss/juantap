import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'incident_report_popup.dart';

class LocationOfUserPage extends StatefulWidget {
  final String alertId;
  final String userId;
  final String userName;
  final double latitude;
  final double longitude;

  const LocationOfUserPage({
    super.key,
    required this.alertId,
    required this.userId,
    required this.userName,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<LocationOfUserPage> createState() => _LocationOfUserPageState();
}

class _LocationOfUserPageState extends State<LocationOfUserPage> {
  GoogleMapController? _mapController;
  LatLng? _responderLocation;
  late LatLng _userLocation;

  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};

  Stream<Position>? _positionStream;
  String? _profileImage;
  bool _isLoadingRoute = false;
  double? _travelTimeMinutes;

  // ✅ Flask API URL
  // final String _flaskUrl = "http://192.168.1.5:5000/safe-route";
  final String _flaskUrl = "https://juantap-flask.onrender.com/safe-route";

  @override
  void initState() {
    super.initState();
    _userLocation = LatLng(widget.latitude, widget.longitude);
    _fetchUserProfile();
    _listenToResponderLocation();
  }

  Future<void> _fetchUserProfile() async {
    try {
      final snap = await FirebaseDatabase.instance.ref('users/${widget.userId}').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        setState(() {
          _profileImage = (data['profileImage'] != null && data['profileImage'].toString().isNotEmpty)
              ? data['profileImage']
              : 'https://i.imgur.com/8Km9tLL.jpg';
        });
      }
    } catch (e) {
      debugPrint("⚠️ Failed to fetch user profile: $e");
    }
  }

  void _listenToResponderLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
    );

    _positionStream!.listen((pos) {
      setState(() => _responderLocation = LatLng(pos.latitude, pos.longitude));
      _updateMap();
      _drawFlaskSafeRoute();
    });
  }

  void _updateMap() {
    if (_responderLocation == null) return;

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId("responder"),
          position: _responderLocation!,
          infoWindow: const InfoWindow(title: "Responder (You)"),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
        Marker(
          markerId: const MarkerId("user"),
          position: _userLocation,
          infoWindow: InfoWindow(title: widget.userName),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };
    });
  }

  Future<void> _drawFlaskSafeRoute() async {
    if (_responderLocation == null) return;

    setState(() {
      _isLoadingRoute = true;
      _travelTimeMinutes = null;
    });

    final body = json.encode({
      "origin": [_responderLocation!.latitude, _responderLocation!.longitude],
      "destination": [_userLocation.latitude, _userLocation.longitude],
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
          // ✅ FIX: handle reversed coordinates (lon, lat vs lat, lon)
          final route = (data["safe_route"] as List)
              .map((p) {
            final first = p[0].toDouble();
            final second = p[1].toDouble();
            // If coordinates look reversed, fix automatically
            return (first.abs() <= 90 && second.abs() >= 90)
                ? LatLng(first, second)
                : LatLng(second, first);
          })
              .toList();

          if (data["duration"] != null) {
            setState(() => _travelTimeMinutes = data["duration"] / 60);
          }

          if (route.isNotEmpty) {
            setState(() {
              _polylines = {
                Polyline(
                  polylineId: const PolylineId("safe_route"),
                  color: const Color(0xFF2ECC71),
                  width: 6,
                  points: route,
                ),
              };
              _isLoadingRoute = false;
            });
            await _fitCameraToBounds(route);
          }
        } else {
          _drawFallbackLine();
        }
      } else {
        debugPrint("❌ Flask returned ${res.statusCode}");
        _drawFallbackLine();
      }
    } catch (e) {
      debugPrint("❌ Flask route error: $e");
      _drawFallbackLine();
    }
  }

  void _drawFallbackLine() {
    if (_responderLocation == null) return;

    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId("direct_line"),
          color: Colors.redAccent,
          width: 4,
          points: [_responderLocation!, _userLocation],
        ),
      };
      _isLoadingRoute = false;
    });
  }

  Future<void> _fitCameraToBounds(List<LatLng> points) async {
    if (_mapController == null || points.isEmpty) return;

    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;

    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    await _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      60,
    ));
  }

  String _formatTravelTime(double minutes) {
    if (minutes >= 60) {
      final hrs = (minutes ~/ 60);
      final mins = (minutes % 60).round();
      return "${hrs}h ${mins}m";
    }
    return "${minutes.toStringAsFixed(0)} min";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text('Responder', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Location of the user',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF25C09C), Color(0xFF2ECC71), Color(0xFFFF6B6B)],
                  stops: [0.0, 0.7, 1.0],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: Image.network(
                          _profileImage ?? 'https://i.imgur.com/8Km9tLL.jpg',
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const Icon(Icons.person, color: Colors.white, size: 60),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.userName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            if (_travelTimeMinutes != null)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  const Icon(Icons.access_time, color: Colors.white, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatTravelTime(_travelTimeMinutes!),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Stack(
                    children: [
                      Container(
                        height: 280,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: GoogleMap(
                          initialCameraPosition:
                          CameraPosition(target: _userLocation, zoom: 15),
                          onMapCreated: (controller) => _mapController = controller,
                          markers: _markers,
                          polylines: _polylines,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                        ),
                      ),
                      if (_isLoadingRoute)
                        const Positioned.fill(
                          child: Center(
                            child: CircularProgressIndicator(color: Color(0xFF2ECC71)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Follow the green route to reach the user safely.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => IncidentReportPopup(
                          userId: widget.userId,
                          userName: widget.userName,
                          responderLocation: _responderLocation,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF28A361),
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    icon: const Icon(Icons.report, color: Colors.white),
                    label: const Text(
                      "Action Report",
                      style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
