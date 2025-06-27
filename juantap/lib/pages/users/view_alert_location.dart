import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ViewAlertLocationPage extends StatefulWidget {
  final String userId; // sender of SOS alert

  const ViewAlertLocationPage({super.key, required this.userId});

  @override
  State<ViewAlertLocationPage> createState() => _ViewAlertLocationPageState();
}

class _ViewAlertLocationPageState extends State<ViewAlertLocationPage> {
  LatLng? _currentLocation;
  late DatabaseReference _locationRef;
  late Stream<DatabaseEvent> _locationStream;

  @override
  void initState() {
    super.initState();
    _locationRef = FirebaseDatabase.instance.ref('sos_alerts/${FirebaseAuth.instance.currentUser!.uid}/${widget.userId}/location');
    _locationStream = _locationRef.onValue;

    _locationStream.listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        setState(() {
          _currentLocation = LatLng(data['lat'], data['lng']);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Live Location")),
      body: _currentLocation == null
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
        initialCameraPosition: CameraPosition(
          target: _currentLocation!,
          zoom: 16,
        ),
        markers: {
          Marker(
            markerId: MarkerId('sosSender'),
            position: _currentLocation!,
            infoWindow: const InfoWindow(title: "SOS Sender"),
          ),
        },
      ),
    );
  }
}
