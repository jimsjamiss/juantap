// web_live_map.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:latlong2/latlong.dart';

class WebLiveMap extends StatefulWidget {
  const WebLiveMap({
    super.key,
    this.centerLat,
    this.centerLng,
    this.markerTitle,
  });

  /// Optional initial camera center (responder report pinpoint)
  final double? centerLat;
  final double? centerLng;

  /// Optional title for the pinpoint marker
  final String? markerTitle;

  @override
  State<WebLiveMap> createState() => _WebLiveMapState();
}

class _WebLiveMapState extends State<WebLiveMap> {
  final DatabaseReference _zonesRef =
  FirebaseDatabase.instance.ref('danger_zones');
  final DatabaseReference _liveRef =
  FirebaseDatabase.instance.ref('live_locations');

  final MapController _mapController = MapController();

  // Markers & circles
  List<Marker> _dangerMarkers = <Marker>[];
  List<Marker> _userMarkers = <Marker>[];
  List<Marker> _reportMarker = <Marker>[];
  List<CircleMarker> _circles = <CircleMarker>[];

  List<Marker> get _allMarkers => <Marker>[
    ..._dangerMarkers,
    ..._userMarkers,
    ..._reportMarker,
  ];

  @override
  void initState() {
    super.initState();
    _listenToDangerZones();
    _listenToLiveUsers();
    _addReportPinIfAvailable();
  }

  void _listenToDangerZones() {
    _zonesRef.onValue.listen((event) {
      if (!mounted) return;

      if (!event.snapshot.exists) {
        setState(() {
          _dangerMarkers = [];
          _circles = [];
        });
        return;
      }

      final zones = Map<String, dynamic>.from(event.snapshot.value as Map);
      final List<Marker> dz = [];
      final List<CircleMarker> cs = [];

      zones.forEach((id, raw) {
        final z = Map<String, dynamic>.from(raw);
        final lat = (z['lat'] as num).toDouble();
        final lng = (z['lng'] as num).toDouble();
        final radius = (z['radius'] as num).toDouble();

        dz.add(
          Marker(
            width: 40,
            height: 40,
            point: LatLng(lat, lng),
            alignment: Alignment.center,
            child: const Icon(
              Icons.warning_rounded,
              color: Colors.redAccent,
              size: 36,
            ),
          ),
        );

        cs.add(
          CircleMarker(
            point: LatLng(lat, lng),
            color: Colors.red.withOpacity(0.25),
            borderStrokeWidth: 2,
            borderColor: Colors.red,
            useRadiusInMeter: true,
            radius: radius, // meters
          ),
        );
      });

      setState(() {
        _dangerMarkers = dz;
        _circles = cs;
      });
    });
  }

  void _listenToLiveUsers() {
    _liveRef.onValue.listen((event) {
      if (!mounted) return;

      if (!event.snapshot.exists) {
        setState(() => _userMarkers = []);
        return;
      }

      final users = Map<String, dynamic>.from(event.snapshot.value as Map);
      final List<Marker> um = [];

      users.forEach((id, raw) {
        final loc = Map<String, dynamic>.from(raw);
        final lat = (loc['lat'] as num).toDouble();
        final lng = (loc['lng'] as num).toDouble();

        um.add(
          Marker(
            width: 40,
            height: 40,
            point: LatLng(lat, lng),
            alignment: Alignment.center,
            child: const Icon(
              Icons.person_pin_circle,
              color: Colors.blueAccent,
              size: 38,
            ),
          ),
        );
      });

      setState(() => _userMarkers = um);
    });
  }

  // ✅ Add pinpoint marker for responder report if coordinates are available
  void _addReportPinIfAvailable() {
    if (widget.centerLat != null && widget.centerLng != null) {
      final double lat = widget.centerLat!;
      final double lng = widget.centerLng!;

      setState(() {
        _reportMarker = [
          Marker(
            width: 45,
            height: 45,
            point: LatLng(lat, lng),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.markerTitle != null && widget.markerTitle!.isNotEmpty)
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 3,
                          offset: const Offset(1, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.markerTitle!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                const Icon(
                  Icons.location_on,
                  color: Colors.green,
                  size: 42,
                ),
              ],
            ),
          ),
        ];
      });

      // Center the map automatically to that pinpoint
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(LatLng(lat, lng), 15);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: LatLng(
            widget.centerLat ?? 10.324,
            widget.centerLng ?? 123.938,
          ),
          initialZoom: 13,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.yourcompany.juantap_admin',
          ),
          if (_circles.isNotEmpty) CircleLayer(circles: _circles),
          MarkerLayer(markers: _allMarkers),
        ],
      ),
    );
  }
}
