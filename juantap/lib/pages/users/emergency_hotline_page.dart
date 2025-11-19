import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class EmergencyHotlinePage extends StatefulWidget {
  const EmergencyHotlinePage({super.key});

  @override
  State<EmergencyHotlinePage> createState() => _EmergencyHotlinePageState();
}

class _EmergencyHotlinePageState extends State<EmergencyHotlinePage> {
  String _city = "Loading...";
  LatLng? _userPosition;
  List<Map<String, dynamic>> _hotlines = [];

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _loadCityAndHotlines();
  }
  final Map<String, String> policeHotlines = {
    "mandaue city police office": "344-3364",
    "mandaue police station 1": "344-3364",
    "cebu city police office": "166",
    "lapu-lapu city police office": "340-0221",
    "police station 1": "344-3364",
    "police station": "344-3364",
  };

  //fetch police locations from mapbox api
  Future<List<Map<String, dynamic>>> fetchPoliceStationsFromMapbox(
      double lat, double lng) async {
    const mapboxToken = "pk.eyJ1IjoianVhbnRhcDIwMjUiLCJhIjoiY21pNXduMGU0MDU5bDJqcTJjaDZ1NmpoNyJ9.HC8c-9rabvkbUG5lvXh52Q";

    final url =
        "https://api.mapbox.com/geocoding/v5/mapbox.places/police station.json"
        "?proximity=$lng,$lat"
        "&types=poi"
        "&limit=10"
        "&access_token=$mapboxToken";

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final List features = data["features"];

    return features.map((item) {
      return {
        "name": item["text"] ?? "",
        "address": item["place_name"] ?? "",
        "lat": item["center"][1],
        "lng": item["center"][0],
      };
    }).toList();
  }


  Future<void> _loadCityAndHotlines() async {
    try {
      final args = ModalRoute.of(context)!.settings.arguments;

      _userPosition = args is LatLng ? args : const LatLng(10.3157, 123.8854);

      final placemarks = await placemarkFromCoordinates(
        _userPosition!.latitude,
        _userPosition!.longitude,
      );

      final place = placemarks.first;
      final city = place.locality ?? "Unknown";

      // === GET MAPBOX POLICE STATIONS ===
      final mapboxStations = await fetchPoliceStationsFromMapbox(
        _userPosition!.latitude,
        _userPosition!.longitude,
      );

      // === MATCH CONTACT NUMBERS ===
      List<Map<String, dynamic>> finalHotlines = [];

      for (var s in mapboxStations) {
        String name = s["name"].toString().toLowerCase();
        String hotline = "911"; // default

        policeHotlines.forEach((key, value) {
          if (name.contains(key)) {
            hotline = value;
          }
        });

        finalHotlines.add({
          "title": s["name"],
          "number": hotline,
          "lat": s["lat"],
          "lng": s["lng"],
        });
      }

      setState(() {
        _city = city;
        _hotlines = finalHotlines.isEmpty ? _nationalHotlines : finalHotlines;
      });

      _generateMarkers();
    } catch (e) {
      setState(() {
        _city = "Unknown";
        _hotlines = _nationalHotlines;
      });

      _generateMarkers();
    }
  }

  // National fallback hotlines (no location)
  final List<Map<String, dynamic>> _nationalHotlines = [
    {
      "title": "Philippine National Police (PNP)",
      "number": "911",
      "lat": 14.5995,
      "lng": 120.9842
    },
    {
      "title": "Bureau of Fire Protection (BFP)",
      "number": "160",
      "lat": 14.5995,
      "lng": 120.9842
    },
  ];

  // City-based hotlines with sample coordinates
  List<Map<String, dynamic>> _getHotlinesForCity(String city) {
    city = city.toLowerCase();

    if (city.contains("mandaue")) {
      return [
        {
          "title": "Mandaue Command Center",
          "number": "344-4747",
          "lat": 10.3235,
          "lng": 123.9231
        },
        {
          "title": "Mandaue Police Station",
          "number": "344-3364",
          "lat": 10.3278,
          "lng": 123.9414
        },
        {
          "title": "Mandaue Fire Station",
          "number": "344-4747",
          "lat": 10.3242,
          "lng": 123.9292
        },
      ];
    }

    if (city.contains("cebu")) {
      return [
        {
          "title": "Cebu City Police",
          "number": "166",
          "lat": 10.3102,
          "lng": 123.8911
        },
        {
          "title": "Cebu City Fire Station",
          "number": "160",
          "lat": 10.2981,
          "lng": 123.9017
        },
        {
          "title": "Cebu Disaster Office",
          "number": "401-0200",
          "lat": 10.3118,
          "lng": 123.8983
        },
      ];
    }

    return _nationalHotlines;
  }

  void _generateMarkers() {
    _markers.clear();

    if (_userPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId("user_location"),
          position: _userPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: "You Are Here"),
        ),
      );
    }

    for (var hotline in _hotlines) {
      _markers.add(
        Marker(
          markerId: MarkerId(hotline["title"]),
          position: LatLng(hotline["lat"], hotline["lng"]),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: hotline["title"],
            snippet: hotline["number"],
            onTap: () => _callNumber(hotline["number"]),
          ),
        ),
      );
    }

    setState(() {});
  }

  // Call hotline
  Future<void> _callNumber(String number) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: number);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Emergency Hotlines"),
        backgroundColor: const Color(0xFF4B8B7A),
      ),

      body: Column(
        children: [
          // USER'S LOCATION LABEL
          Container(
            padding: const EdgeInsets.all(16),
            child: Text(
              "📍 Current Location",
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // ===================== MAP =====================
          Expanded(
            flex: 2,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _userPosition ?? const LatLng(10.3157, 123.8854),
                zoom: 13,
              ),
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (controller) {
                _mapController = controller;
              },
            ),
          ),

          // ===================== LIST OF HOTLINES =====================
          Expanded(
            flex: 3,
            child: ListView(
              children: _hotlines.map((h) {
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    leading:
                    const Icon(Icons.phone, color: Colors.redAccent),
                    title: Text(h["title"]),
                    subtitle: Text(h["number"]),
                    trailing: IconButton(
                      icon: const Icon(Icons.call, color: Colors.green),
                      onPressed: () => _callNumber(h["number"]),
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
