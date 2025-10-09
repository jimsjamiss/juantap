import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationOfUserPage extends StatefulWidget {
  final String alertId; // ✅ we pass the alertId instead of lat/lng

  const LocationOfUserPage({
    super.key,
    required this.alertId,
  });

  @override
  State<LocationOfUserPage> createState() => _LocationOfUserPageState();
}

class _LocationOfUserPageState extends State<LocationOfUserPage> {
  final TextEditingController _descriptionController = TextEditingController();
  GoogleMapController? _mapController;
  LatLng? _responderLocation;
  LatLng? _userLocation;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  Stream<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _fetchUserLocation();       // ✅ initial fetch
    _listenToUserLocation();    // ✅ new live updates
    _listenToResponderLocation();
  }

  String? _username;
  String? _address; // optional if stored in DB

  void _fetchUserLocation() async {
    final ref = FirebaseDatabase.instance.ref("responder_alerts/${widget.alertId}/location");
    final snapshot = await ref.get();

    if (snapshot.exists) {
      final location = Map<String, dynamic>.from(snapshot.value as Map);

      final lat = (location['lat'] as num?)?.toDouble();
      final lng = (location['lng'] as num?)?.toDouble();

      setState(() {
        _userLocation = (lat != null && lng != null) ? LatLng(lat, lng) : null;
        _username = location['username'] ?? "Unknown User";
        _address  = location['address'] ?? "Unknown Address";
      });

      debugPrint("✅ User location loaded: $_userLocation ($_username)");
      _updateMap();
    } else {
      debugPrint("⚠️ No location found for alert ${widget.alertId}");
    }
  }

  // ✅ NEW: listen to live user location changes
  void _listenToUserLocation() {
    final ref = FirebaseDatabase.instance.ref("responder_alerts/${widget.alertId}/location");

    ref.onValue.listen((event) {
      if (!event.snapshot.exists) return;

      final location = Map<String, dynamic>.from(event.snapshot.value as Map);

      final lat = (location['lat'] as num?)?.toDouble();
      final lng = (location['lng'] as num?)?.toDouble();

      if (lat != null && lng != null) {
        setState(() {
          _userLocation = LatLng(lat, lng);
          _username = location['username'] ?? "Unknown User";
          _address  = location['address'] ?? "Unknown Address";
        });

        debugPrint("📍 User live location updated: $_userLocation ($_username)");
        _updateMap();
      }
    });
  }

  void _listenToResponderLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    );

    _positionStream!.listen((Position pos) {
      setState(() {
        _responderLocation = LatLng(pos.latitude, pos.longitude);
      });
      debugPrint("📍 Responder location updated: $_responderLocation");
      _updateMap();
    });
  }

  Future<void> _updateMap() async {
    if (_responderLocation == null || _userLocation == null) return;

    // Add both markers
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('responder'),
          position: _responderLocation!,
          infoWindow: const InfoWindow(title: 'Responder (You)'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
        Marker(
          markerId: const MarkerId('user'),
          position: _userLocation!,
          infoWindow: InfoWindow(title: _username ?? 'User'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };
    });

    // Fit camera bounds
    final bounds = LatLngBounds(
      southwest: LatLng(
        (_responderLocation!.latitude < _userLocation!.latitude)
            ? _responderLocation!.latitude
            : _userLocation!.latitude,
        (_responderLocation!.longitude < _userLocation!.longitude)
            ? _responderLocation!.longitude
            : _userLocation!.longitude,
      ),
      northeast: LatLng(
        (_responderLocation!.latitude > _userLocation!.latitude)
            ? _responderLocation!.latitude
            : _userLocation!.latitude,
        (_responderLocation!.longitude > _userLocation!.longitude)
            ? _responderLocation!.longitude
            : _userLocation!.longitude,
      ),
    );

    await Future.delayed(const Duration(milliseconds: 400));
    _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));

    // Call Google Directions API
    const apiKey = 'YOUR_GOOGLE_MAPS_API_KEY'; // 🔑 replace with real
    final url =
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${_responderLocation!.latitude},${_responderLocation!.longitude}'
        '&destination=${_userLocation!.latitude},${_userLocation!.longitude}'
        '&mode=driving'
        '&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      final data = json.decode(response.body);

      if (data['status'] == "OK" && data['routes'].isNotEmpty) {
        final points = _decodePolyline(
          data['routes'][0]['overview_polyline']['points'],
        );
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: points,
              width: 5,
              color: Colors.blue,
            ),
          };
        });
        debugPrint("✅ Route drawn between responder and user");
      } else {
        // fallback line if no route found
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('fallback'),
              points: [_responderLocation!, _userLocation!],
              width: 4,
              color: Colors.red,
              patterns: [PatternItem.dash(20), PatternItem.gap(10)],
            ),
          };
        });
        debugPrint("⚠️ Directions API returned no route.");
      }
    } catch (e) {
      debugPrint("❌ Directions API error: $e");
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int shift = 0, result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int deltaLat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += deltaLat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int deltaLng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += deltaLng;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }

  // --- Incident Report (unchanged) ---
  void _showIncidentReportDialog(BuildContext context, String status) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/shield.png', height: 80,
                    errorBuilder: (_, __, ___) =>
                    const Icon(Icons.security, size: 60)),
                const SizedBox(height: 12),
                const Text('Incident Report',
                    style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                _buildTextField('Incident Description',
                    'Enter a brief description', _descriptionController),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF28A361),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: () => _submitIncidentReport(status),
                    child: const Text('Submit Incident Report'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submitIncidentReport(String status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final responderUid = user.uid;
    final responderRef = FirebaseDatabase.instance.ref('users/$responderUid');
    final responderSnapshot = await responderRef.get();
    final responderData = responderSnapshot.value as Map?;
    final responderName = responderData?['username'] ?? 'Unknown';

    final now = DateTime.now();
    final formattedDate =
        '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}/${now.year}';
    final formattedTime = TimeOfDay.fromDateTime(now).format(context);

    final reportRef =
    FirebaseDatabase.instance.ref('responder_reports/$responderUid').push();

    await reportRef.set({
      'description': _descriptionController.text.trim(),
      'date': formattedDate,
      'time': formattedTime,
      'timestamp': now.toIso8601String(),
      'status': status,
      'location': 'Brgy. Opao, Zone 3',
      'responderName': responderName,
      'latitude': _responderLocation?.latitude,
      'longitude': _responderLocation?.longitude,
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report submitted successfully!')),
    );
  }

  static Widget _buildTextField(
      String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF2F2F2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  // --- UI stays the same ---
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Location of the user',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF25C09C), Color(0xFFFF0000)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            'https://i.imgur.com/8Km9tLL.jpg',
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _username ?? 'Loading...',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                _address ?? 'Fetching location...',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),

                        Image.asset(
                          'assets/badge.png',
                          height: 40,
                          errorBuilder: (_, __, ___) =>
                          const Icon(Icons.verified, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16)),
                      child: GoogleMap(
                        initialCameraPosition: const CameraPosition(
                            target: LatLng(10.3157, 123.8854), zoom: 14),
                        onMapCreated: (controller) =>
                        _mapController = controller,
                        markers: _markers,
                        polylines: _polylines,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Use the guided route to quickly rescue the user.',
                        style: TextStyle(fontSize: 13, color: Colors.black),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Is the Incident resolved?',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: () =>
                              _showIncidentReportDialog(context, "resolved"),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF28A361)),
                          child: const Text('Yes'),
                        ),
                        ElevatedButton(
                          onPressed: () => _showIncidentReportDialog(
                              context, "not resolved"),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade400),
                          child: const Text('No'),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ]),
      ),
    );
  }
}