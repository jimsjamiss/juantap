import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:juantap/pages/users/view_alert_location.dart';
import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';



class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _rippleController;
  late Animation<double> _rippleAnimation;

  String _username = '';
  String? profileImageUrl;
  final _user = FirebaseAuth.instance.currentUser;

  final Set<String> _processedAlertKeys = {};
  AudioPlayer? _player;
  Timer? _vibrationTimer;
  bool _checkInActive = false;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _rippleAnimation = CurvedAnimation(
      parent: _rippleController,
      curve: Curves.linear,
    );

    _loadUserData();
    _listenToContactRequests();
    _listenToSosAlerts();
  }
  AudioPlayer? player;

  void _listenToSosAlerts() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final sosRef = FirebaseDatabase.instance.ref('sos_alerts/$uid');

    sosRef.onChildAdded.listen((event) async {
      final locationData = event.snapshot.child('location').value;
      if (locationData == null || locationData is! Map) return;

      final data = Map<String, dynamic>.from(locationData as Map);
      final username = data['username'] ?? 'Unknown';
      final lat = (data['lat'] as num).toDouble();
      final lng = (data['lng'] as num).toDouble();
      final alertSenderId = event.snapshot.key ?? 'unknown';

      // Start custom vibration loop
      if (await Vibration.hasVibrator() ?? false) {
        _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          Vibration.vibrate(duration: 1000);
        });
      }

      // Play emergency ringtone
      player = AudioPlayer();
      try {
        await player!.setSource(AssetSource('audio/lingling.mp3'));
        await player!.setReleaseMode(ReleaseMode.loop);
        await player!.resume();
      } catch (e) {
        print('Audio error: $e');
      }

      // Show alert dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text('🚨 EMERGENCY ALERT from $username'),
          content: Text('Location: $lat, $lng'),
          actions: [
            TextButton(
              onPressed: () {
                _vibrationTimer?.cancel();
                Vibration.cancel();
                player?.stop();
                Navigator.pop(context);
              },
              child: const Text('Dismiss'),
            ),
            TextButton(
              onPressed: () {
                _vibrationTimer?.cancel();
                Vibration.cancel();
                player?.stop();
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ViewAlertLocationPage(userId: alertSenderId),
                  ),
                );
              },
              child: const Text('View Location'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final ref = FirebaseDatabase.instance.ref('users/${user.uid}');
      final snapshot = await ref.get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        setState(() {
          profileImageUrl = data['profileImage'];
          _username = data['username'] ?? '';
        });
      }
    }
  }

  void _startCheckInFlow(BuildContext context) {
    _showActivateCheckInDialog(context);
  }

  void _showActivateCheckInDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _buildModalDialog(
        image: 'assets/images/app_logo.png',
        title: 'Activate Check-in mode?',
        buttonText: 'Apply',
        onPressed: () {
          Navigator.pop(context);
          _showCheckInConfirmation(context);
        },
      ),
    );
  }
  void _showCheckInConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _buildModalDialog(
        icon: Icons.check_circle,
        iconColor: Colors.green,
        title: 'Please read carefully',
        content:
        "You’ve successfully checked in.\nWe’re actively monitoring your status.\n\nYou’ll be prompted every 1 minute. No response will trigger alerts.",
        buttonText: 'Confirm',
        onPressed: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Check-In Activated'),
              backgroundColor: Colors.green.shade700,
              duration: Duration(seconds: 3),
            ),
          );
          _startSafetyPromptLoop(context);
        },
      ),
    );
  }

  void _startSafetyPromptLoop(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final startTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    await FirebaseDatabase.instance.ref('check_in_logs/$uid').set({
      'active': true,
      'startTime': startTime,
      'responses': {},
    });

    setState(() => _checkInActive = true);

    _vibrationTimer?.cancel();
    _vibrationTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _showSafetyPrompt(context);
    });
  }

  void _showSafetyPrompt(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFEFFEF5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Image.asset('assets/images/app_logo.png', height: 60),
            const SizedBox(height: 12),
            const Text(
              'Are you safe right now?\nPlease confirm your status.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            children: [
              GestureDetector(
                onTap: () async {
                  Navigator.pop(context);
                  final uid = FirebaseAuth.instance.currentUser!.uid;
                  final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

                  await FirebaseDatabase.instance
                      .ref('check_in_logs/$uid/responses/$timestamp')
                      .set("Yes, I'm safe");
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade800,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    "Yes, I'm safe",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  await _stopCheckIn(context);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Check-In stopped'),
                      backgroundColor: Colors.red.shade700,
                      duration: Duration(seconds: 3),
                    ),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    "Stop Check-In",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
  List<Map<String, dynamic>> _notifications = [];

  void _listenToContactRequests() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    FirebaseDatabase.instance
        .ref('contact_requests/$uid')
        .onValue
        .listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final List<Map<String, dynamic>> newNotifs = [];

        data.forEach((key, value) {
          final req = Map<String, dynamic>.from(value);
          newNotifs.add({
            'uid': key,
            'username': req['senderUsername'],
          });
        });

        setState(() {
          _notifications = newNotifs;
        });
      } else {
        setState(() {
          _notifications = [];
        });
      }
    });
  }
  void _showNotificationMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ListView.builder(
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final notif = _notifications[index];
          return ListTile(
            title: Text('${notif['username']}'),
            subtitle: Text('wants to add you'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.check, color: Colors.green),
                  onPressed: () async {
                    await _acceptRequest(notif['uid'], notif['username']);
                    Navigator.pop(context);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.red),
                  onPressed: () async {
                    await _declineRequest(notif['uid']);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  final DatabaseReference _contactsRef = FirebaseDatabase.instance.ref('contacts');
  final DatabaseReference _requestsRef = FirebaseDatabase.instance.ref('contact_requests');

  Future<void> _acceptRequest(String senderUid, String senderUsername) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) return;

    // Save contact to both users
    await _contactsRef.child(currentUser.uid).child(senderUid).set({
      'name': senderUsername,
      'nickname': '',
    });

    await _contactsRef.child(senderUid).child(currentUser.uid).set({
      'name': currentUser.displayName ?? 'You',
      'nickname': '',
    });

    // Remove the request
    await _requestsRef.child(currentUser.uid).child(senderUid).remove();

    // Optionally update notifications list
    setState(() {
      _notifications.removeWhere((req) => req['uid'] == senderUid);
    });
  }

  Future<void> _declineRequest(String senderUid) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) return;

    await _requestsRef.child(currentUser.uid).child(senderUid).remove();

    setState(() {
      _notifications.removeWhere((req) => req['uid'] == senderUid);
    });
  }


  Future<void> _stopCheckIn(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _vibrationTimer?.cancel();
    setState(() => _checkInActive = false);

    await FirebaseDatabase.instance
        .ref('check_in_logs/$uid/active')
        .set(false);
  }
  Widget _buildModalDialog({
    IconData? icon,
    Color? iconColor,
    String? image,
    required String title,
    String? content,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return AlertDialog(
      backgroundColor: const Color(0xFFEFFEF5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.all(16),
      contentPadding: const EdgeInsets.only(bottom: 12, left: 24, right: 24),
      title: Column(
        children: [
          if (icon != null)
            Icon(icon, size: 50, color: iconColor)
          else if (image != null)
            Image.asset(image, height: 60),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (content != null) ...[
            const SizedBox(height: 12),
            Text(
              content,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ],
      ),
      actions: [
        Center(
          child: GestureDetector(
            onTap: onPressed,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade800,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        )
      ],
    );
  }
  Future<void> sendSosAlert() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final uid = user.uid;
      final userRef = FirebaseDatabase.instance.ref('users/$uid');
      final contactsRef = FirebaseDatabase.instance.ref('contacts/$uid');
      final sosRef = FirebaseDatabase.instance.ref('sos_alerts');
      final responderAlertRef = FirebaseDatabase.instance.ref('responder_alerts');

      final userSnapshot = await userRef.get();
      if (!userSnapshot.exists) return;

      final userData = Map<String, dynamic>.from(userSnapshot.value as Map);
      final username = userData['username'] ?? 'Unknown';

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      final contactsSnapshot = await contactsRef.get();
      if (contactsSnapshot.exists) {
        final contacts = Map<String, dynamic>.from(contactsSnapshot.value as Map);
        for (final contactId in contacts.keys) {
          await sosRef.child(contactId).child(uid).child('location').set({
            'username': username,
            'timestamp': DateTime.now().toIso8601String(),
            'lat': position.latitude,
            'lng': position.longitude,
          });
        }
      }

      // Send to responders
      final newResponderRef = FirebaseDatabase.instance.ref('responder_alerts').push();
      await newResponderRef.set({
        'location': {
          'lat': position.latitude,
          'lng': position.longitude,
          'timestamp': DateTime.now().toIso8601String(),
          'userId': uid,
          'username': username,
        }
      });


      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🚨 SOS sent successfully'), backgroundColor: Colors.redAccent),
      );
    } catch (e) {
      print('❌ Error sending SOS: $e');
    }
  }


  void _confirmAndSendSOS() {
    int secondsLeft = 5;
    late StateSetter updateState;
    Timer? countdownTimer;
    bool isCancelled = false; // <-- flag to prevent SOS if cancelled

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            updateState = setState;

            countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (timer) {
              if (secondsLeft == 1) {
                timer.cancel();
                Navigator.pop(context);

                if (!isCancelled) {
                  sendSosAlert(); // <-- Only send if not cancelled
                }
              } else {
                setState(() {
                  secondsLeft--;
                });
              }
            });

            return AlertDialog(
              title: const Text('️Do you want to Send SOS?️'),
              content: Text('Sending SOS in $secondsLeft seconds...'),
              actions: [
                TextButton(
                  onPressed: () {
                    isCancelled = true; // <-- mark as cancelled
                    countdownTimer?.cancel();
                    Navigator.pop(context); // Close dialog
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }



  @override
  void dispose() {
    _rippleController.dispose();
    _vibrationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4B8B7A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/app_logo.png',
              height: 26,
            ),
            const SizedBox(width: 8),
            const Text(
              'JUANTAP',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: 2,

              ),
            ),
          ],
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () {
                  _showNotificationMenu(context);
                },
              ),
              if (_notifications.isNotEmpty)
                Positioned(
                  right: 11,
                  top: 11,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      '${_notifications.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          )
        ],
      ),
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF4B8B7A)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: profileImageUrl != null
                        ? NetworkImage(profileImageUrl!)
                        : const AssetImage('assets/images/user_profile.png') as ImageProvider,
                  ),
                  SizedBox(height: 10),
                  Text(
                    _username,
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.account_circle_sharp, color: Colors.green),
              title: Text('Profile Settings'),
              onTap: () {
                Navigator.pushNamed(context, '/edit_profile');
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.redAccent),
              title: Text('Logout'),
              onTap: () async {
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
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Logout', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );

                if (shouldLogout == true) {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                }
              },
            ),

          ],
        ),
      ),
      backgroundColor: const Color(0xFF4B8B7A),
      body: Stack(
        children: [
          // Ripple + SOS button
          Align(
            alignment: Alignment.center,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _rippleAnimation,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: List.generate(3, (index) {
                        final value = (_rippleAnimation.value + index * 0.33) % 1.0;
                        final scale = 1 + value * 2;
                        final opacity = (1 - value).clamp(0.0, 1.0);

                        return Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.redAccent.withOpacity(0.4),
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
                ),
                GestureDetector(
                  onTap: _confirmAndSendSOS,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
                    ),
                    child: const Center(
                      child: Text('SOS', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom navigation buttons
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 60, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  BottomMenuButton(
                    imagePath: 'assets/images/map_button.png',
                    label: 'Map',
                    onTap: () => Navigator.pushNamed(context, '/maps_location'),
                  ),
                  BottomMenuButton(
                    imagePath: 'assets/images/checkIn_button.png',
                    label: 'Check-In',
                    onTap: () => _startCheckInFlow(context),
                  ),
                  BottomMenuButton(
                    imagePath: 'assets/images/contact_button.png',
                    label: 'Contacts',
                    onTap: () => Navigator.pushNamed(context, '/contact_lists'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Timer?>('_vibrationTimer', _vibrationTimer));
  }
}
// --- Custom Components ---

class TopCurveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.lineTo(0, size.height * 0.85);
    path.quadraticBezierTo(
      size.width * 0.5,
      size.height,
      size.width,
      size.height * 0.85,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class BottomMenuButton extends StatelessWidget {
  final String imagePath;
  final String label;
  final VoidCallback onTap;

  const BottomMenuButton({
    super.key,
    required this.imagePath,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Color(0xFFF7F6D9),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Image.asset(imagePath, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}


