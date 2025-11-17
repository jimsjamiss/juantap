// ignore_for_file: use_build_context_synchronously

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'send_alert_response.dart';
import 'incident_reports.dart';
import 'package:juantap/pages/users/login.dart';
import 'package:juantap/pages/responders/edit_responder_profile.dart';

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

  bool _isMounted = true;
  bool _popupActive = false;

  AudioPlayer? _player;
  Timer? _vibrationTimer;
  Timer? _cleanupTimer;

  @override
  void initState() {
    super.initState();
    _fetchResponderData();
    _listenToResponderAlerts();
    _cleanupTimer =
        Timer.periodic(const Duration(minutes: 10), (_) => _removeExpiredAlerts());
  }

  @override
  void dispose() {
    _isMounted = false;
    _cleanupTimer?.cancel();
    _stopAlertFeedbackImmediately();
    super.dispose();
  }

  // ✅ Fetch responder info
  Future<void> _fetchResponderData() async {
    if (user == null) return;
    final ref = FirebaseDatabase.instance.ref('users/${user!.uid}');
    final snapshot = await ref.get();
    if (snapshot.exists && mounted) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      setState(() {
        _username = data['username'] ?? '';
        _emailController.text = data['email'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _profileImageUrl = data['profileImage'];
      });
    }
  }

  // ✅ Upload profile image to Cloudinary
  Future<void> _uploadProfileImage(File imageFile) async {
    const cloudName = 'YOUR_CLOUD_NAME';
    const uploadPreset = 'YOUR_UPLOAD_PRESET';
    final url = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    final response = await request.send();
    final responseData = await response.stream.bytesToString();

    if (response.statusCode == 200) {
      final uploadedUrl =
      RegExp(r'"secure_url":"([^"]+)"').firstMatch(responseData)?.group(1);
      if (uploadedUrl != null && user != null && mounted) {
        await FirebaseDatabase.instance
            .ref('users/${user!.uid}/profileImage')
            .set(uploadedUrl);
        setState(() => _profileImageUrl = uploadedUrl);
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final file = File(picked.path);
      setState(() => _profileImage = file);
      await _uploadProfileImage(file);
    }
  }

  Future<void> _saveProfile() async {
    if (user == null) return;
    final newName = _nameController.text.trim();
    final newPhone = _phoneController.text.trim();
    final newEmail = _emailController.text.trim();

    await FirebaseDatabase.instance.ref('users/${user!.uid}').update({
      'username': newName,
      'phone': newPhone,
      'email': newEmail,
      'role': 'responder',
      'profileImage': _profileImageUrl,
    });

    if (!mounted) return;
    setState(() => _username = newName);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated successfully ✅')),
    );
  }

  // 🧠 Keep this list at the top of your class:
  List<Map<String, dynamic>> _alertQueue = [];


// ✅ Listen to responder_alerts (Main listener)
  void _listenToResponderAlerts() {
    final ref = FirebaseDatabase.instance.ref('responder_alerts');

    ref.onChildAdded.listen((event) {
      if (!_isMounted || !event.snapshot.exists) return;

      final alertId = event.snapshot.key ?? 'unknown_alert';
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);

      final username = data['username'] ?? 'Unknown User';
      final userId = data['userId'] ?? '';
      final email = data['email'] ?? '';
      final phone = data['phone'] ?? '';
      final address = data['address'] ?? '';
      final birthdate = data['birthdate'] ?? '';
      final nationality = data['nationality'] ?? '';
      final profileImage = data['profileImage'] ?? '';
      final reason = data['reason'] ?? 'SOS Alert';
      final timestampStr = data['timestamp'] ?? '';

      final location = data.containsKey('location')
          ? Map<String, dynamic>.from(data['location'])
          : {};
      final lat = (location['lat'] ?? 0.0).toDouble();
      final lng = (location['lng'] ?? 0.0).toDouble();

      final timestamp = DateTime.tryParse(timestampStr);
      if (timestamp == null ||
          DateTime.now().difference(timestamp).inHours >= 10) return;

      final alert = {
        'alertId': alertId,
        'userId': userId,
        'name': username,
        'email': email,
        'phone': phone,
        'address': address,
        'birthdate': birthdate,
        'nationality': nationality,
        'profileImage': profileImage,
        'reason': reason,
        'timestamp': timestampStr,
        'location': {
          'lat': lat,
          'lng': lng,
        },
        'latitude': lat,
        'longitude': lng,

        // 🔥 NEW FIELDS
        'proofUrl': data['proofUrl'] ?? '',
        'isVideo': data['isVideo'] ?? false,
        'crimeType': data['crimeType'] ?? 'General Alert',
      };


      // Prevent duplicates
      final exists = recentAlerts.any(
            (a) => a['userId'] == userId && a['timestamp'] == timestampStr,
      );
      if (exists) return;

      setState(() => recentAlerts.add(alert));

      // 🟢 Queue this alert
      _alertQueue.add(alert);

      // If no popup is active, show the first in queue
      if (!_popupActive) {
        _showNextAlert(context);
      }
    });
  }


// ✅ Function to show next alert in queue
  void _showNextAlert(BuildContext parentContext) {
    if (_alertQueue.isEmpty || _popupActive) return;

    final alert = _alertQueue.first;
    _popupActive = true;
    _startAlertFeedback();

    final profileImage = alert['profileImage'] ?? '';
    final username = alert['name'] ?? 'Unknown User';
    final address = alert['address'] ?? '';
    final lat = alert['latitude'] ?? 0.0;
    final lng = alert['longitude'] ?? 0.0;
    final phone = alert['phone'] ?? '';
    final email = alert['email'] ?? '';
    final birthdate = alert['birthdate'] ?? '';
    final nationality = alert['nationality'] ?? '';
    final alertId = alert['alertId'];
    final userId = alert['userId'];

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
              backgroundImage: profileImage.isNotEmpty
                  ? NetworkImage(profileImage)
                  : const AssetImage('assets/shield.png') as ImageProvider,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('🚨 SOS Alert from $username')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📍 Location: $lat, $lng'),
            Text('🏠 Address: $address'),
            Text('📞 Phone: $phone'),
            Text('📧 Email: $email'),
            Text('🎂 Birthdate: $birthdate'),
            Text('🌎 Nationality: $nationality'),
            const SizedBox(height: 8),
            const Text('Please respond immediately.'),
          ],
        ),
        actions: [
          // ❌ Dismiss — show next alert
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              _stopAlertFeedbackImmediately();
              Navigator.pop(dialogContext);

              // Remove the dismissed alert
              _alertQueue.removeAt(0);

              // Allow next alert
              _popupActive = false;
              Future.delayed(const Duration(milliseconds: 200), () {
                _showNextAlert(parentContext);
              });
            },
            child: const Text('Dismiss'),
          ),

          // ✅ Accept — go to SendAlertResponsePage & clear queue
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              _stopAlertFeedbackImmediately();
              Navigator.pop(dialogContext);

              // Save acceptance
              if (user != null) {
                final responderRef = FirebaseDatabase.instance
                    .ref('responder_alerts/$alertId/responders/${user!.uid}');
                await responderRef.set({
                  'responderName': _username.isNotEmpty
                      ? _username
                      : (user!.email ?? 'Responder'),
                  'respondedAt': DateTime.now().toIso8601String(),
                });
              }

              // 🚫 Clear all pending alerts after accepting one
              _alertQueue.clear();
              _popupActive = true;

              if (parentContext.mounted) {
                await Future.delayed(const Duration(milliseconds: 200));
                Navigator.pushReplacement(
                  parentContext,
                  MaterialPageRoute(
                    builder: (_) => SendAlertResponsePage(alertData: alert),
                  ),
                );
              }
            },
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  // ✅ Feedback (sound + vibration)
  Future<void> _startAlertFeedback() async {
    await _stopAlertFeedbackImmediately();
    if (!_popupActive) return;

    if (await Vibration.hasVibrator() ?? false) {
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (_popupActive) await Vibration.vibrate(duration: 800);
      });
    }

    _player = AudioPlayer();
    try {
      await _player!.setSource(AssetSource('audio/security-alarm-1.mp3'));
      await _player!.setReleaseMode(ReleaseMode.loop);
      if (_popupActive) await _player!.resume();
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }

  Future<void> _stopAlertFeedbackImmediately() async {
    try {
      _vibrationTimer?.cancel();
      _vibrationTimer = null;
      if (await Vibration.hasVibrator() ?? false) await Vibration.cancel();
      await _player?.stop();
      await _player?.dispose();
      _player = null;
    } catch (e) {
      debugPrint('Stop feedback error: $e');
    }
  }

  void _removeExpiredAlerts() {
    final now = DateTime.now();
    setState(() {
      recentAlerts.removeWhere((a) {
        final ts = DateTime.tryParse(a['timestamp'] ?? '');
        return ts == null || now.difference(ts).inHours >= 10;
      });
    });
  }

  Future<void> _logout() async {
    await _stopAlertFeedbackImmediately();
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Logout')),
        ],
      ),
    );
    if (shouldLogout == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
      }
    }
  }

  // ✅ UI
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

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF264653),
      child: ListView(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF2A9D8F)),
            accountName: GestureDetector(
              onTap: _showEditProfileDialog,
              child: Text(_username, style: const TextStyle(fontSize: 18)),
            ),
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
                    : const AssetImage('assets/shield.png') as ImageProvider,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard, color: Colors.white),
            title: const Text('Dashboard', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.report, color: Colors.white),
            title: const Text('Incident Reports', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IncidentReportsResponder()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.account_circle, color: Colors.white),
            title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditResponderProfilePage()),
              );
            },
          ),
          const Divider(color: Colors.white54),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white),
            title: const Text('Logout', style: TextStyle(color: Colors.white)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsList() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView.builder(
        itemCount: recentAlerts.length,
        itemBuilder: (context, i) {
          final item = recentAlerts[i];
          final lat = item['location']['lat'] ?? 0.0;
          final lng = item['location']['lng'] ?? 0.0;

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
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(item['address'] ?? 'No address available'),
                  Text(item['phone'] ?? 'No phone available'),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 160,
                    child: GoogleMap(
                      initialCameraPosition:
                      CameraPosition(target: LatLng(lat, lng), zoom: 14),
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

  // ✅ Edit Profile Dialog
  void _showEditProfileDialog() {
    _nameController.text = _username;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickAndUploadImage,
                child: CircleAvatar(
                  radius: 40,
                  backgroundImage: _profileImageUrl != null
                      ? NetworkImage(_profileImageUrl!)
                      : const AssetImage('assets/shield.png') as ImageProvider,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email')),
              TextField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Phone')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await _saveProfile();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}