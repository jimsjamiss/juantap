// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

import '../users/sos_service.dart';
import 'send_alert_response.dart';
import 'incident_reports.dart';
import 'package:juantap/pages/users/login.dart';
import 'package:juantap/pages/responders/edit_responder_profile.dart';
import '../users/chat_screen.dart'; // <--- needed for redirect to chat
import '../responders/responder_chat_list.dart';



class ResponderDashboard extends StatelessWidget {
  const ResponderDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Responder Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Responder Dashboard'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}


class _MyHomePageState extends State<MyHomePage> {
  final user = FirebaseAuth.instance.currentUser;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  File? _profileImage;
  String? _profileImageUrl;
  String _username = '';

  List<Map<String, dynamic>> recentAlerts = [];
  List<Map<String, dynamic>> _alertQueue = [];

  bool _isMounted = true;
  bool _popupActive = false;

  AudioPlayer? _player;
  Timer? _vibrationTimer;
  Timer? _cleanupTimer;

  late String responderId;

  @override
  void initState() {
    super.initState();
    responderId = FirebaseAuth.instance.currentUser!.uid;

    _fetchResponderData();
    _listenToResponderAlerts();

    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 10),
          (_) => _removeExpiredAlerts(),
    );
  }

  @override
  void dispose() {
    _isMounted = false;
    _cleanupTimer?.cancel();
    _stopAlertFeedbackImmediately();
    super.dispose();
  }

  // ----------------------------------------------------------
  // FETCH RESPONDER PROFILE
  // ----------------------------------------------------------
  Future<void> _fetchResponderData() async {
    if (user == null) return;

    final ref = FirebaseDatabase.instance.ref('users/${user!.uid}');
    final snap = await ref.get();

    if (!snap.exists) return;
    if (!mounted) return;

    final data = Map<String, dynamic>.from(snap.value as Map);

    setState(() {
      _username = data['username'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      _emailController.text = data['email'] ?? '';
      _profileImageUrl = data['profileImage'];
    });
  }
  // ======================================================================
  // UI: POPUP IF OTHER RESPONDER ALREADY ACCEPTED
  // ======================================================================
  void _showAlreadyAccepted() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Alert Already Accepted"),
        content: const Text(
            "Another responder already accepted this SOS alert."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // LISTEN FOR INCOMING SOS ALERTS
  // ----------------------------------------------------------
  void _listenToResponderAlerts() {
    final ref = FirebaseDatabase.instance.ref('responder_alerts');

    ref.onChildAdded.listen((event) {
      if (!event.snapshot.exists) return;

      final alertId = event.snapshot.key;
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);

      // ignore if already accepted
      if (data['acceptedBy'] != null) return;

      final timestamp = DateTime.tryParse(data['timestamp'] ?? '');
      if (timestamp == null ||
          DateTime.now().difference(timestamp).inHours >= 10) return;

      final location = data['location'] != null
          ? Map<String, dynamic>.from(data['location'])
          : {};

      final alert = {
        'alertId': alertId,
        'userId': data['userId'],
        'name': data['username'] ?? 'Unknown',
        'address': data['address'] ?? '',
        'email': data['email'] ?? '',
        'phone': data['phone'] ?? '',
        'birthdate': data['birthdate'] ?? '',
        'nationality': data['nationality'] ?? '',
        'profileImage': data['profileImage'] ?? '',
        'timestamp': data['timestamp'],
        'latitude': (location['lat'] ?? 0.0).toDouble(),
        'longitude': (location['lng'] ?? 0.0).toDouble(),
        'crimeType': data['crimeType'] ?? 'General Alert',
        'proofUrl': data['proofUrl'] ?? '',
        'isVideo': data['isVideo'] ?? false,
      };

      // Prevent duplicates
      if (recentAlerts.any((a) =>
      a['userId'] == alert['userId'] &&
          a['timestamp'] == alert['timestamp'])) {
        return;
      }

      setState(() => recentAlerts.add(alert));

      // Add to queue
      _alertQueue.add(alert);

      // Show if no active popup
      if (!_popupActive) {
        _showNextAlert(context);
      }
    });
  }

  // ----------------------------------------------------------
  // ACCEPT ALERT (FIRST RESPONDER ONLY)
  // ----------------------------------------------------------
  Future<void> acceptAlert(String alertId, String responderId) async {
    final alertRef =
    FirebaseDatabase.instance.ref("responder_alerts/$alertId");

    final alreadyAccepted = await alertRef.child("acceptedBy").get();

    if (alreadyAccepted.value != null) {
      // Someone already accepted
      _showAlreadyAccepted();
      return;
    }

    // Accept this alert
    await alertRef.update({
      "acceptedBy": responderId,
      "acceptedAt": ServerValue.timestamp,
    });

    print("🟢 This responder accepted the alert");

    // Create chat
    final userIdSnapshot = await alertRef.child("userId").get();
    final userId = userIdSnapshot.value.toString();

    final chatId =
    await SOSService().createChatAfterSOS(userId, responderId);

    print("💬 Chat created: $chatId");

    // Navigate to chat
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatId: chatId, myId: responderId),
      ),
    );
  }

  // ----------------------------------------------------------
  // SHOW ALERTS POPUP
  // ----------------------------------------------------------
  void _showNextAlert(BuildContext parentContext) {
    if (_alertQueue.isEmpty || _popupActive) return;

    final alert = _alertQueue.first;
    _popupActive = true;

    _startAlertFeedback();

    final profileImg = alert['profileImage'] ?? '';
    final lat = alert['latitude'] ?? 0.0;
    final lng = alert['longitude'] ?? 0.0;

    showDialog(
      context: parentContext,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFFFEAEA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Row(
          children: [
            CircleAvatar(
              radius: 25,
              backgroundImage: profileImg.isNotEmpty
                  ? NetworkImage(profileImg)
                  : const AssetImage('assets/shield.png') as ImageProvider,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text("🚨 SOS Alert from ${alert['name']}"),
            )
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📍 Location: $lat, $lng'),
            Text('🏠 Address: ${alert['address']}'),
            Text('📞 Phone: ${alert['phone']}'),
            Text('📧 Email: ${alert['email']}'),
            Text('🎂 Birthdate: ${alert['birthdate']}'),
            Text('🌎 Nationality: ${alert['nationality']}'),
            const SizedBox(height: 8),
            const Text('Respond immediately.'),
          ],
        ),
        actions: [
          // DECLINE
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              _stopAlertFeedbackImmediately();
              Navigator.pop(dialogContext);

              _alertQueue.removeAt(0);
              _popupActive = false;

              Future.delayed(const Duration(milliseconds: 200), () {
                _showNextAlert(parentContext);
              });
            },
            child: const Text("Dismiss"),
          ),

          // ACCEPT
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              await acceptAlert(alert['alertId'], responderId);

              _stopAlertFeedbackImmediately();
              Navigator.pop(dialogContext);

              _alertQueue.clear();
              _popupActive = false;

              Navigator.push(
                parentContext,
                MaterialPageRoute(
                  builder: (_) => SendAlertResponsePage(alertData: alert),
                ),
              );
            },
            child: const Text("ACCEPT"),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // FEEDBACK FUNCTIONS (ALARM + VIBRATE)
  // ----------------------------------------------------------
  Future<void> _startAlertFeedback() async {
    await _stopAlertFeedbackImmediately();

    if (await Vibration.hasVibrator() ?? false) {
      _vibrationTimer =
          Timer.periodic(const Duration(seconds: 2), (_) async {
            if (_popupActive) {
              await Vibration.vibrate(duration: 800);
            }
          });
    }

    _player = AudioPlayer();
    try {
      await _player!.setSource(
        AssetSource("audio/security-alarm-1.mp3"),
      );

      await _player!.setReleaseMode(ReleaseMode.loop);

      if (_popupActive) {
        await _player!.resume();
      }
    } catch (e) {
      debugPrint("AUDIO ERROR: $e");
    }
  }

  Future<void> _stopAlertFeedbackImmediately() async {
    try {
      _vibrationTimer?.cancel();
      _vibrationTimer = null;

      if (await Vibration.hasVibrator() ?? false) {
        await Vibration.cancel();
      }

      await _player?.stop();
      await _player?.dispose();

      _player = null;
    } catch (e) {
      debugPrint("STOP FEEDBACK ERROR: $e");
    }
  }

  // ----------------------------------------------------------
  // CLEAR OLD ALERTS
  // ----------------------------------------------------------
  void _removeExpiredAlerts() {
    final now = DateTime.now();

    setState(() {
      recentAlerts.removeWhere((a) {
        final ts = DateTime.tryParse(a['timestamp'] ?? '');
        return ts == null ||
            now.difference(ts).inHours >= 10;
      });
    });
  }

  // ----------------------------------------------------------
  // LOGOUT
  // ----------------------------------------------------------
  Future<void> _logout() async {
    await _stopAlertFeedbackImmediately();

    if (!mounted) return;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (!mounted) return; // <--- IMPORTANT FIX #1

    if (shouldLogout == true) {
      await FirebaseAuth.instance.signOut();

      if (!mounted) return; // <--- IMPORTANT FIX #2

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  // ----------------------------------------------------------
  // MAIN UI
  // ----------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2A9D8F),
      ),
      drawer: _buildDrawer(),
      body: _buildAlertsList(),
    );
  }

  // ----------------------------------------------------------
  // SIDEBAR
  // ----------------------------------------------------------
  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF264653),
      child: ListView(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF2A9D8F)),
            accountName: Text(_username,
                style: const TextStyle(fontSize: 18)),
            accountEmail: Text(
              _emailController.text.isEmpty
                  ? "responder@juantap.com"
                  : _emailController.text,
            ),
            currentAccountPicture: GestureDetector(
              onTap: _pickAndUploadImage,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: _profileImageUrl != null
                    ? NetworkImage(_profileImageUrl!)
                    : const AssetImage('assets/shield.png')
                as ImageProvider,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard, color: Colors.white),
            title: const Text('Dashboard',
                style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.message, color: Colors.white),
            title: const Text('Messages', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ResponderChatList(
                    responderId: FirebaseAuth.instance.currentUser!.uid,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.report, color: Colors.white),
            title: const Text('Incident Reports',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const IncidentReportsResponder(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_circle, color: Colors.white),
            title: const Text('Edit Profile',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EditResponderProfilePage(),
                ),
              );
            },
          ),
          const Divider(color: Colors.white54),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white),
            title: const Text('Logout',
                style: TextStyle(color: Colors.white)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // ALERTS LIST UI
  // ----------------------------------------------------------
  Widget _buildAlertsList() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView.builder(
        itemCount: recentAlerts.length,
        itemBuilder: (context, i) {
          final item = recentAlerts[i];
          final lat = item['latitude'] ?? 0.0;
          final lng = item['longitude'] ?? 0.0;

          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SendAlertResponsePage(
                    alertData: item,
                  ),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEAEA),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name']!,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  Text(item['address'] ?? 'No address'),
                  Text(item['phone'] ?? 'No phone'),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 160,
                    child: GoogleMap(
                      initialCameraPosition:
                      CameraPosition(
                          target: LatLng(lat, lng), zoom: 14),
                      markers: {
                        Marker(
                          markerId: MarkerId(item['name']!),
                          position: LatLng(lat, lng),
                        ),
                      },
                      zoomControlsEnabled: false,
                      liteModeEnabled: true,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------
  // EDIT PROFILE POPUP
  // ----------------------------------------------------------
  Future<void> _pickAndUploadImage() async {
    final picked =
    await ImagePicker().pickImage(source: ImageSource.gallery);

    if (picked != null) {
      final file = File(picked.path);
      setState(() => _profileImage = file);
      await _uploadProfileImage(file);
    }
  }

  Future<void> _uploadProfileImage(File file) async {
    // TODO - replace with your Cloudinary settings
  }

  void _showEditProfileDialog() {
    _nameController.text = _username;
    _emailController.text = _emailController.text;
    _phoneController.text = _phoneController.text;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Profile"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Name",
                )),
            TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Email",
                )),
            TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: "Phone",
                )),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () async {
                await _saveProfile();
                Navigator.pop(context);
              },
              child: const Text("Save")),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (user == null) return;

    await FirebaseDatabase.instance
        .ref("users/${user!.uid}")
        .update({
      "username": _nameController.text.trim(),
      "email": _emailController.text.trim(),
      "phone": _phoneController.text.trim(),
    });

    setState(() {
      _username = _nameController.text.trim();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profile updated successfully")),
    );
  }
}
