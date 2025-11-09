// sos_alert_listener.dart
import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:vibration/vibration.dart';

/// ✅ SOS Alert Listener — receives alerts from friends, not self
class SosAlertListener {
  final BuildContext context;
  final Set<String> _processedAlertKeys = {};
  StreamSubscription<DatabaseEvent>? _subscription;
  Timer? _vibrationTimer;
  Timer? _cleanupTimer;
  AudioPlayer? _player;

  SosAlertListener({required this.context});

  /// Start listening for incoming SOS alerts
  void startListening() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // ✅ Listen only to this user's SOS branch
    final DatabaseReference sosRef =
    FirebaseDatabase.instance.ref('sos_alerts/${currentUser.uid}');

    // 🔁 Auto-cleanup every 10 minutes
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 10),
          (_) => _removeExpiredAlerts(sosRef),
    );

    _subscription = sosRef.onChildAdded.listen((event) async {
      final alertId = event.snapshot.key ?? '';
      if (_processedAlertKeys.contains(alertId)) return;
      _processedAlertKeys.add(alertId);

      final alertData = Map<String, dynamic>.from(event.snapshot.value as Map);

      final senderId = alertData['userId'];
      final username = alertData['username'] ?? 'Unknown User';
      final email = alertData['email'] ?? 'No email';
      final phone = alertData['phone'] ?? 'No phone';
      final address = alertData['address'] ?? 'Unknown';
      final nationality = alertData['nationality'] ?? '';
      final birthdate = alertData['birthdate'] ?? '';
      final profileImage = alertData['profileImage'];
      final recipients = List<String>.from(alertData['recipients'] ?? []);
      final location = Map<String, dynamic>.from(alertData['location'] ?? {});
      final double lat = (location['lat'] ?? 0).toDouble();
      final double lng = (location['lng'] ?? 0).toDouble();
      final timestampStr = alertData['timestamp'] ?? '';

      // 🚫 Skip if alert belongs to the same user
      if (senderId == currentUser.uid) return;

      // 🚫 Skip if recipients list exists and this user is not in it
      if (recipients.isNotEmpty && !recipients.contains(currentUser.uid)) return;

      // ⏰ Ignore expired alerts (>24h old)
      final alertTime = DateTime.tryParse(timestampStr) ?? DateTime.now();
      if (DateTime.now().difference(alertTime).inHours >= 24) {
        await sosRef.child(alertId).remove();
        _processedAlertKeys.remove(alertId);
        return;
      }

      // 🔔 Vibrate continuously
      if (await Vibration.hasVibrator() ?? false) {
        _vibrationTimer?.cancel();
        _vibrationTimer =
            Timer.periodic(const Duration(seconds: 2), (_) => Vibration.vibrate(duration: 1000));
      }

      // 🔊 Looping alert tone
      _player = AudioPlayer();
      try {
        await _player!.setSource(AssetSource('audio/random-alarm-3.mp3'));
        await _player!.setReleaseMode(ReleaseMode.loop);
        await _player!.resume();
      } catch (_) {}

      // 🚨 Popup Alert
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: Colors.white,
            title: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                      SizedBox(width: 8),
                      Text(
                        "EMERGENCY ALERT",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "🚨 SOS Triggered by $username",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (profileImage != null)
                  CircleAvatar(radius: 35, backgroundImage: NetworkImage(profileImage)),
                const SizedBox(height: 10),
                Text("📍 $address", textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text("📞 $phone", style: const TextStyle(color: Colors.black54)),
                Text("✉️ $email", style: const TextStyle(color: Colors.black54)),
                if (birthdate.isNotEmpty)
                  Text("🎂 $birthdate", style: const TextStyle(color: Colors.black54)),
                if (nationality.isNotEmpty)
                  Text("🌍 $nationality", style: const TextStyle(color: Colors.black54)),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.map, color: Colors.white),
                label: const Text("View Location"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A9D8F),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  _stopFeedback();
                  if (context.mounted) Navigator.pop(context);
                  _processedAlertKeys.remove(alertId);

                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SosAlertListenerPage(
                          senderName: username,
                          latitude: lat,
                          longitude: lng,
                          profileImage: profileImage,
                        ),
                      ),
                    );
                  }
                },
              ),
              TextButton(
                onPressed: () {
                  _stopFeedback();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text("Dismiss",
                    style: TextStyle(color: Colors.grey, fontSize: 15)),
              ),
            ],
          ),
        );
      }
    });
  }

  /// 🧹 Auto remove expired SOS (>24h)
  Future<void> _removeExpiredAlerts(DatabaseReference sosRef) async {
    final snap = await sosRef.get();
    if (!snap.exists) return;
    final now = DateTime.now();

    for (final child in snap.children) {
      final data = Map<String, dynamic>.from(child.value as Map);
      final ts = DateTime.tryParse(data['timestamp'] ?? '');
      if (ts == null || now.difference(ts).inHours >= 24) {
        await sosRef.child(child.key!).remove();
        _processedAlertKeys.remove(child.key!);
      }
    }
  }

  void _stopFeedback() async {
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    try {
      await Vibration.cancel();
      await _player?.stop();
      await _player?.dispose();
    } catch (_) {}
  }

  void stopListening() {
    _subscription?.cancel();
    _cleanupTimer?.cancel();
    _stopFeedback();
  }

  void dispose() {
    stopListening();
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////
/// ✅ Updated User-to-User Route Page (unchanged)
////////////////////////////////////////////////////////////////////////////////////////////////////
class SosAlertListenerPage extends StatefulWidget {
  final String senderName;
  final double latitude;
  final double longitude;
  final String? profileImage;

  const SosAlertListenerPage({
    required this.senderName,
    required this.latitude,
    required this.longitude,
    this.profileImage,
  });

  @override
  State<SosAlertListenerPage> createState() => _SosAlertListenerPageState();
}

class _SosAlertListenerPageState extends State<SosAlertListenerPage> {
  GoogleMapController? _mapController;
  LatLng? _userLocation;
  late LatLng _senderLocation;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  bool _isLoadingRoute = false;
  double? _travelTimeMinutes;
  double? _travelDistanceKm;
  Stream<Position>? _positionStream;

  final String _orsApiKey =
      "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjZkNTQ2YzZmZmE0ZDQ0Yzc5OWFiMTQ3Yzg2ZTllZTI5IiwiaCI6Im11cm11cjY0In0=";

  @override
  void initState() {
    super.initState();
    _senderLocation = LatLng(widget.latitude, widget.longitude);
    _listenToUserLocation();
  }

  void _listenToUserLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    );

    _positionStream!.listen((pos) {
      _userLocation = LatLng(pos.latitude, pos.longitude);
      _updateMarkers();
      _drawNavigationRoute();
      _followUser();
    });
  }

  void _updateMarkers() {
    if (_userLocation == null) return;
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId("current_user"),
          position: _userLocation!,
          infoWindow: const InfoWindow(title: "You"),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
        Marker(
          markerId: const MarkerId("sender"),
          position: _senderLocation,
          infoWindow: InfoWindow(title: widget.senderName),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };
    });
  }

  Future<void> _drawNavigationRoute() async {
    if (_userLocation == null) return;
    setState(() => _isLoadingRoute = true);

    final url =
        "https://api.openrouteservice.org/v2/directions/driving-car?api_key=$_orsApiKey&start=${_userLocation!.longitude},${_userLocation!.latitude}&end=${_senderLocation.longitude},${_senderLocation.latitude}&geometry_format=geojson";

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final route = data["features"][0];
        final coords = route["geometry"]["coordinates"];
        final summary = route["properties"]["summary"];

        final List<LatLng> routePoints = [];
        for (var c in coords) {
          routePoints.add(LatLng(c[1].toDouble(), c[0].toDouble()));
        }

        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId("user_to_user_route"),
              color: Colors.blueAccent,
              width: 6,
              points: routePoints,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
            ),
          };
          _travelTimeMinutes = (summary["duration"] ?? 0) / 60;
          _travelDistanceKm = (summary["distance"] ?? 0) / 1000;
          _isLoadingRoute = false;
        });

        await _fitCameraToRoute(routePoints);
      }
    } catch (e) {
      debugPrint("❌ Route error: $e");
    }
  }

  Future<void> _followUser() async {
    if (_mapController == null || _userLocation == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _userLocation!, zoom: 17, tilt: 45),
      ),
    );
  }

  Future<void> _fitCameraToRoute(List<LatLng> points) async {
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
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
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
        title: const Text('User-to-User Route', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Live Route to SOS Sender',
                style: TextStyle(
                    color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF25C09C), Color(0xFF2ECC71), Color(0xFFFF6B6B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundImage: widget.profileImage != null
                            ? NetworkImage(widget.profileImage!)
                            : const AssetImage('assets/images/user_profile.png') as ImageProvider,
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.senderName,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            if (_travelTimeMinutes != null && _travelDistanceKm != null)
                              Text(
                                "ETA: ${_formatTravelTime(_travelTimeMinutes!)}  •  ${_travelDistanceKm!.toStringAsFixed(2)} km away",
                                style:
                                const TextStyle(color: Colors.white, fontSize: 14),
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
                          CameraPosition(target: _senderLocation, zoom: 14),
                          onMapCreated: (controller) => _mapController = controller,
                          markers: _markers,
                          polylines: _polylines,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: true,
                          compassEnabled: true,
                        ),
                      ),
                      if (_isLoadingRoute)
                        const Positioned.fill(
                          child:
                          Center(child: CircularProgressIndicator(color: Colors.white)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Follow the blue route to reach the user in distress.',
                      style: TextStyle(fontSize: 13, color: Colors.black87),
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
