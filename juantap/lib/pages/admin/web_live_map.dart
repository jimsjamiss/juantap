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
  });

  /// Optional initial camera center
  final double? centerLat;
  final double? centerLng;

  @override
  State<WebLiveMap> createState() => _WebLiveMapState();
}

class _WebLiveMapState extends State<WebLiveMap> {
  final DatabaseReference _zonesRef =
  FirebaseDatabase.instance.ref('danger_zones');
  final DatabaseReference _liveRef =
  FirebaseDatabase.instance.ref('live_locations');

  final MapController _mapController = MapController();

  // Keep each group separate, then combine for the layer:
  List<Marker> _dangerMarkers = <Marker>[];
  List<Marker> _userMarkers = <Marker>[];
  List<CircleMarker> _circles = <CircleMarker>[];

  List<Marker> get _allMarkers => <Marker>[
    ..._dangerMarkers,
    ..._userMarkers,
  ];

  @override
  void initState() {
    super.initState();
    _listenToDangerZones();
    _listenToLiveUsers();
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
        // _userMarkers kept as-is; layer below merges them
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
            // flutter_map >= 5 recommends setting this:
            userAgentPackageName: 'com.yourcompany.juantap_admin',
          ),
          CircleLayer(circles: _circles),
          MarkerLayer(markers: _allMarkers),
        ],
      ),
    );
  }
}
