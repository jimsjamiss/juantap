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
      home: const MyHomePage(title: 'Responder'),
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
  List<Map<String, String>> recentAlerts = [];
  bool _isMounted = true;
  AudioPlayer? player;
  Timer? _vibrationTimer;

  @override
  void initState() {
    super.initState();
    _fetchResponderData();
    _listenToResponderAlerts();
  }

  @override
  void dispose() {
    _isMounted = false;
    _vibrationTimer?.cancel();
    player?.dispose();
    super.dispose();
  }

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

    if (mounted) {
      setState(() => _username = newName);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully ✅')),
      );
    }
  }

  void _showEditProfileDialog() {
    _nameController.text = _username;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
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
                TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email')),
                TextField(controller: _phoneController, decoration: const InputDecoration(labelText: 'Phone')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await _saveProfile();
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // ✅ UPDATED: Listen directly to full responder_alerts node
  void _listenToResponderAlerts() {
    final responderAlertsRef = FirebaseDatabase.instance.ref('responder_alerts');
    responderAlertsRef.onChildAdded.listen((event) async {
      if (!_isMounted || !mounted) return;
      if (!event.snapshot.exists) return;

      final alertData = Map<String, dynamic>.from(event.snapshot.value as Map);

      final timestampString = alertData['timestamp'];
      if (timestampString == null) return;

      final timestamp = DateTime.tryParse(timestampString);
      if (timestamp == null) return;

      final now = DateTime.now();
      final diff = now.difference(timestamp);
      if (diff.inHours >= 24) return;

      final username = alertData['username'] ?? 'Unknown';
      final lat = alertData['location']?['lat'] ?? 0.0;
      final lng = alertData['location']?['lng'] ?? 0.0;

      final alert = {
        'userId': alertData['userId'] ?? '',
        'name': username.toString(),
        'email': alertData['email'] ?? '',
        'phone': alertData['phone'] ?? '',
        'address': alertData['address'] ?? '',
        'nationality': alertData['nationality'] ?? '',
        'birthdate': alertData['birthdate'] ?? '',
        'profileImage': alertData['profileImage'] ?? '',
        'location': '$lat, $lng',
        'time': TimeOfDay.now().format(context),
        'reason': alertData['reason'] ?? 'SOS Alert',
        'date': now.toLocal().toString().split(' ')[0],
      };

      await _showSosPopup(context, username, lat, lng, alert);
      if (mounted) {
        setState(() => recentAlerts.add(
          alert.map((key, value) => MapEntry(key, value.toString())),
        ));

      }
    });
  }

  Future<void> _showSosPopup(
      BuildContext context,
      String username,
      double lat,
      double lng,
      Map<String, dynamic> alert,
      ) async {
    _startAlertFeedback();
    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFFFFEAEA),
          title: Text('🚨 SOS Alert from $username'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📍 Location: $lat, $lng'),
              const SizedBox(height: 8),
              if (alert['address'] != null && alert['address']!.isNotEmpty)
                Text('🏠 Address: ${alert['address']}'),
              if (alert['phone'] != null && alert['phone']!.isNotEmpty)
                Text('📞 Phone: ${alert['phone']}'),
              if (alert['email'] != null && alert['email']!.isNotEmpty)
                Text('✉️ Email: ${alert['email']}'),
              if (alert['birthdate'] != null && alert['birthdate']!.isNotEmpty)
                Text('🎂 Birthdate: ${alert['birthdate']}'),
              if (alert['nationality'] != null && alert['nationality']!.isNotEmpty)
                Text('🌍 Nationality: ${alert['nationality']}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _stopAlertFeedback();
                Navigator.of(context, rootNavigator: true).pop();
              },
              child: const Text('Dismiss', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () {
                _stopAlertFeedback();
                Navigator.of(context, rootNavigator: true).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SendAlertResponsePage(data: alert)),
                );
              },
              child: const Text('Accept', style: TextStyle(color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  void _startAlertFeedback() async {
    // Stop any previous vibration or sound loop
    _stopAlertFeedback();

    // Start vibration safely
    if (await Vibration.hasVibrator() ?? false) {
      _vibrationTimer?.cancel(); // cancel old timer
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) {
          Vibration.vibrate(duration: 800);
        }
      });
    }

    // Start sound loop
    player ??= AudioPlayer();
    try {
      await player!.setSource(AssetSource('audio/bomboclat.mp3'));
      await player!.setReleaseMode(ReleaseMode.loop);
      await player!.resume();
    } catch (e) {
      debugPrint('Audio error: $e');
    }
  }


  void _stopAlertFeedback() {
    // Stop vibration loop safely
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    Vibration.cancel();

    // Stop audio loop safely
    if (player != null) {
      player!.stop();
    }
  }


  Future<void> _logout() async {
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
    if (shouldLogout == true && mounted) {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = recentAlerts;
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2A9D8F),
      ),
      drawer: Drawer(
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
                _emailController.text.isEmpty ? "responder@juantap.com" : _emailController.text,
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
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IncidentReportsPage())),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle, color: Colors.white),
              title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const EditResponderProfilePage()));
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Emergency Notifications',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final item = notifications[index];
                  final latLng = item['location']!.split(',');
                  final lat = double.tryParse(latLng[0].trim()) ?? 0;
                  final lng = double.tryParse(latLng[1].trim()) ?? 0;

                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => SendAlertResponsePage(data: item)),
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
                          Text(item['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(item['location']!, style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 160,
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(target: LatLng(lat, lng), zoom: 14),
                              markers: {
                                Marker(markerId: MarkerId(item['name']!), position: LatLng(lat, lng)),
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
            ),
          ],
        ),
      ),
    );
  }
}
