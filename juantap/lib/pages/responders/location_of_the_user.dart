import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationOfUserPage extends StatefulWidget {
  final String alertId; // ✅ passed for SOS info
  final String userId; // ✅ passed for user profile

  const LocationOfUserPage({
    super.key,
    required this.alertId,
    required this.userId,
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

  // --- User Info ---
  String? _username;
  String? _address;
  String? _profileUrl;
  String? _email;
  String? _phone;
  String? _birthdate;
  String? _nationality;

  @override
  void initState() {
    super.initState();
    _fetchUserAndLocation();
    _listenToUserLocation();
    _listenToResponderLocation();
  }

  // ✅ Fetch both user info & SOS location
  Future<void> _fetchUserAndLocation() async {
    try {
      final alertRef =
      FirebaseDatabase.instance.ref("responder_alerts/${widget.alertId}");
      final alertSnapshot = await alertRef.get();

      if (!alertSnapshot.exists) {
        debugPrint("⚠️ No alert found for ${widget.alertId}");
        return;
      }

      final alertData = Map<String, dynamic>.from(alertSnapshot.value as Map);
      final locationMap =
      Map<String, dynamic>.from((alertData['location'] ?? {}) as Map);

      String? fetchedUserId = alertData['userId']?.toString();
      fetchedUserId ??= locationMap['userId']?.toString();
      fetchedUserId ??= widget.userId;

      final double? lat = (locationMap['lat'] as num?)?.toDouble();
      final double? lng = (locationMap['lng'] as num?)?.toDouble();

      if (lat != null && lng != null) {
        setState(() => _userLocation = LatLng(lat, lng));
      }

      if (fetchedUserId != null && fetchedUserId.isNotEmpty) {
        final userRef =
        FirebaseDatabase.instance.ref('users/$fetchedUserId');
        final userSnapshot = await userRef.get();

        if (userSnapshot.exists) {
          final userData =
          Map<String, dynamic>.from(userSnapshot.value as Map);
          setState(() {
            _username = userData['username'] ?? "Unknown User";
            _address = userData['address'] ?? "Unknown Address";
            _profileUrl =
            (userData['profileImage']?.toString().isNotEmpty ?? false)
                ? userData['profileImage'].toString()
                : "https://i.imgur.com/8Km9tLL.jpg";
          });
        } else {
          _fallbackFromAlert(alertData, locationMap);
        }
      } else {
        _fallbackFromAlert(alertData, locationMap);
      }

      _updateMap();
    } catch (e) {
      debugPrint("❌ Error fetching user & location: $e");
    }
  }

  void _fallbackFromAlert(Map<String, dynamic> alertData, Map<String, dynamic> locationMap) {
    setState(() {
      _username = alertData['username'] ?? locationMap['username'] ?? "Unknown User";
      _address = alertData['address'] ?? "Unknown Address";
      _profileUrl = "https://i.imgur.com/8Km9tLL.jpg";
    });
  }

  void _listenToUserLocation() {
    final ref = FirebaseDatabase.instance
        .ref("responder_alerts/${widget.alertId}/location");
    ref.onValue.listen((event) {
      if (!event.snapshot.exists) return;
      final location =
      Map<String, dynamic>.from(event.snapshot.value as Map);
      final lat = (location['lat'] as num?)?.toDouble();
      final lng = (location['lng'] as num?)?.toDouble();

      if (lat != null && lng != null) {
        setState(() => _userLocation = LatLng(lat, lng));
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
      setState(() => _responderLocation = LatLng(pos.latitude, pos.longitude));
      _updateMap();
    });
  }

  Future<void> _updateMap() async {
    if (_responderLocation == null || _userLocation == null) return;

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('responder'),
          position: _responderLocation!,
          infoWindow: const InfoWindow(title: 'Responder (You)'),
          icon:
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
        Marker(
          markerId: const MarkerId('user'),
          position: _userLocation!,
          infoWindow: InfoWindow(title: _username ?? 'User'),
          icon:
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      };
    });

    if (_mapController != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(
          (_responderLocation!.latitude <= _userLocation!.latitude)
              ? _responderLocation!.latitude
              : _userLocation!.latitude,
          (_responderLocation!.longitude <= _userLocation!.longitude)
              ? _responderLocation!.longitude
              : _userLocation!.longitude,
        ),
        northeast: LatLng(
          (_responderLocation!.latitude >= _userLocation!.latitude)
              ? _responderLocation!.latitude
              : _userLocation!.latitude,
          (_responderLocation!.longitude >= _userLocation!.longitude)
              ? _responderLocation!.longitude
              : _userLocation!.longitude,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
    }

    // ✅ Directions API route
    const apiKey = 'AIzaSyCnHDdDupstvWoU408P-OcsO0-UMg7mDxs';
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
        final points =
        _decodePolyline(data['routes'][0]['overview_polyline']['points']);
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
      int shift = 0, result = 0, b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return polyline;
  }

  // ✅ Submit report
  Future<void> _submitIncidentReport(String status) async {
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
      'status': status,
      'location': 'Brgy. Opao, Zone 3',
      'responderName': responderName,
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Report filed successfully!')));
  }

  // ✅ Popup Box for Report (half-screen)
  void _showReportDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.55, // half the screen
          child: Padding(
            padding: EdgeInsets.only(
              top: 20,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    "File Incident Report",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _descriptionController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: "Describe how you respond to the user in full detailed...",
                    filled: true,
                    fillColor: Colors.grey[200],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _submitIncidentReport("resolved"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF28A361),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: const Text("Resolved", style: TextStyle(color: Colors.white)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _submitIncidentReport("not resolved"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.close, color: Colors.white),
                      label:
                      const Text("Not Resolved", style: TextStyle(color: Colors.white)),
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

  // ✅ UI
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.redAccent,
        icon: const Icon(Icons.report),
        label: const Text("File Report"),
        onPressed: _showReportDialog,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Location of the user',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient:
              const LinearGradient(colors: [Color(0xFF25C09C), Color(0xFFFF0000)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        _profileUrl ?? 'https://i.imgur.com/8Km9tLL.jpg',
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                        const Icon(Icons.person, size: 50, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _username ?? 'Unknown User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _address ?? 'No address available',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
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
                    onMapCreated: (controller) => _mapController = controller,
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
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
