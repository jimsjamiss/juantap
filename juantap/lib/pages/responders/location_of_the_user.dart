import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
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
  String? _placeName;   // ⭐ NEW FIELD
  bool _isLoadingRoute = false;
  double? _travelTimeMinutes;
  double? _travelDistanceKm;

  // OpenRouteService API Key
  final String _orsApiKey =
      "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjZkNTQ2YzZmZmE0ZDQ0Yzc5OWFiMTQ3Yzg2ZTllZTI5IiwiaCI6Im11cm11cjY0In0=";

  @override
  void initState() {
    super.initState();
    _userLocation = LatLng(widget.latitude, widget.longitude);
    _fetchUserInfo();
    _listenToResponderLocation();
  }

  String? _fetchedUserName;

  // ⭐ Fetch user profile + placeName
  Future<void> _fetchUserInfo() async {
    try {
      // Fetch user profile
      final snap =
      await FirebaseDatabase.instance.ref('users/${widget.userId}').get();
      if (snap.exists) {
        final data = Map<String, dynamic>.from(snap.value as Map);
        setState(() {
          _profileImage =
          (data['profileImage'] != null && data['profileImage'].toString().isNotEmpty)
              ? data['profileImage']
              : 'assets/images/user_profile.png';

          _fetchedUserName = data['username'] ?? widget.userName;
        });
      }

      // ⭐ Fetch placeName from responder_alerts/<alertId>/location/placeName
      final placeSnap = await FirebaseDatabase.instance
          .ref('responder_alerts/${widget.alertId}/location/placeName')
          .get();

      if (placeSnap.exists) {
        setState(() {
          _placeName = placeSnap.value.toString();
        });
      }

    } catch (e) {
      debugPrint("⚠️ Error fetching profile/placeName: $e");
    }
  }

  void _listenToResponderLocation() async {
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
      _responderLocation = LatLng(pos.latitude, pos.longitude);
      _updateMap();
      _drawNavigationRoute();
      _followResponder();
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

  // ⭐ Draw accurate Lalamove-style route
  Future<void> _drawNavigationRoute() async {
    if (_responderLocation == null) return;

    setState(() => _isLoadingRoute = true);

    final url =
        "https://api.openrouteservice.org/v2/directions/driving-car?api_key=$_orsApiKey&start=${_responderLocation!.longitude},${_responderLocation!.latitude}&end=${_userLocation.longitude},${_userLocation.latitude}&geometry_format=geojson";

    try {
      final res = await http.get(Uri.parse(url));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final route = data["features"][0];
        final coords = route["geometry"]["coordinates"];
        final summary = route["properties"]["summary"];

        final List<LatLng> routePoints = [];
        for (var c in coords) {
          final lon = c[0].toDouble();
          final lat = c[1].toDouble();
          routePoints.add(LatLng(lat, lon));
        }

        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId("navigation_route"),
              color: Colors.blueAccent,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
              points: routePoints,
            ),
          };
          _travelTimeMinutes = (summary["duration"] ?? 0) / 60;
          _travelDistanceKm = (summary["distance"] ?? 0) / 1000;
          _isLoadingRoute = false;
        });

        await _fitCameraToRoute(routePoints);
      } else {
        debugPrint("❌ ORS error: ${res.statusCode}");
        _drawFallbackLine();
      }
    } catch (e) {
      debugPrint("❌ Route error: $e");
      _drawFallbackLine();
    }
  }

  void _drawFallbackLine() {
    if (_responderLocation == null) return;
    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId("direct_line"),
          color: Colors.orangeAccent,
          width: 4,
          points: [_responderLocation!, _userLocation],
        ),
      };
      _isLoadingRoute = false;
    });
  }

  Future<void> _followResponder() async {
    if (_mapController == null || _responderLocation == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _responderLocation!,
          zoom: 17,
          bearing: 0,
          tilt: 45,
        ),
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

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
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
        title: const Text("Responder", style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Location of the user",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 16),

            Center(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.95,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF25C09C),
                        Color(0xFF2ECC71),
                        Color(0xFFFF6B6B),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(50),
                            child:
                            Image.network(
                              _profileImage ?? "",
                              width: 70,
                              height: 70,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Image.asset(
                                  'assets/images/user_profile.png',   // ⭐ DEFAULT PROFILE IMAGE
                                  width: 70,
                                  height: 70,
                                  fit: BoxFit.cover,
                                );
                              },
                            ),

                          ),
                          const SizedBox(width: 15),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _fetchedUserName ?? widget.userName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                // ⭐ NEW: placeName
                                if (_placeName != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _placeName!,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 6),

                                if (_travelTimeMinutes != null &&
                                    _travelDistanceKm != null)
                                  Text(
                                    "ETA: ${_formatTravelTime(_travelTimeMinutes!)}  •  ${_travelDistanceKm!.toStringAsFixed(2)} km away",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
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
                              initialCameraPosition: CameraPosition(
                                target: _userLocation,
                                zoom: 15,
                              ),
                              onMapCreated: (controller) =>
                              _mapController = controller,
                              markers: _markers,
                              polylines: _polylines,
                              myLocationEnabled: true,
                              myLocationButtonEnabled: true,
                              compassEnabled: true,
                            ),
                          ),
                          if (_isLoadingRoute)
                            const Positioned.fill(
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF2ECC71),
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          "Follow the blue route to reach the user, similar to navigation apps.",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ),

                      const SizedBox(height: 25),

                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IncidentReportPage(
                                userId: widget.userId,
                                userName: _fetchedUserName ?? widget.userName,
                                responderLocation: _responderLocation,
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E8449),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 50, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                          elevation: 6,
                        ),
                        icon: const Icon(Icons.report, color: Colors.white),
                        label: const Text(
                          "Action Report",
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
