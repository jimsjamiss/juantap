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
import 'package:juantap/pages/users/self_defense_guide.dart';
import 'package:juantap/pages/users/sos_service.dart';
import 'package:juantap/pages/users/voice_command_settings.dart';
import 'dart:math';
import 'package:location/location.dart' as loc;
import 'package:google_maps_flutter/google_maps_flutter.dart'; // only if not already imported
import 'package:juantap/pages/users/maps_location.dart';





class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _rippleController;
  late Animation<double> _rippleAnimation;
  DateTime? _lastDangerSnackbarTime;
  Map<String, dynamic> _dangerZones = {}; // from Firebase
  bool _isDangerAlertVisible = false; // prevent multiple dialogs
  String? _ignoredZoneId; // ✅ remember which zone was ignored


  String _username = '';
  String? profileImageUrl;
  final _user = FirebaseAuth.instance.currentUser;
  bool _isCheckInRunning = false; // ✅ track if active

  final Set<String> _processedAlertKeys = {};
  AudioPlayer? _player;
  Timer? _responseTimer;
  Timer? _vibrationTimer;
  bool _isPromptVisible = false; // 🟢 prevents multiple dialogsbool _isPromptVisible = false; // 🟢 prevents multiple dialogs
  bool _checkInActive = false;

  DateTime? _lastDangerPopupTime; // ✅ track last popup time

  final loc.Location _location = loc.Location(); // ✅ location tracker
  bool _isPermissionGranted = false;            // ✅ permission flag
  LatLng? _userPosition;                        // ✅ user position


  // 🚨 Danger zone vars
  final DatabaseReference _dangerRef = FirebaseDatabase.instance.ref("danger_zones");
  StreamSubscription<Position>? _posSub;
  final AudioPlayer _dangerPlayer = AudioPlayer();



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
    _listenToDangerZones();   // ✅ NEW
    _startLocationMonitoring(); // ✅ NEW
    _initializeLocation();        // ✅ new
    _listenToLocationChanges();   // ✅ new



  }
  // ✅ Called when user's location updates (for home.dart only)
  void _checkForDangerZonesAtHome(double lat, double lng) {
    if (_dangerZones.isEmpty) return;

    // Avoid spam every few seconds
    final now = DateTime.now();
    if (_lastDangerSnackbarTime != null &&
        now.difference(_lastDangerSnackbarTime!).inSeconds < 10) return;

    for (var entry in _dangerZones.entries) {
      final zone = Map<String, dynamic>.from(entry.value);
      final zLat = (zone['lat'] as num).toDouble();
      final zLng = (zone['lng'] as num).toDouble();
      final zRadius = (zone['radius'] as num).toDouble();
      final zName = zone['name'] ?? 'Danger Zone';

      final distance = _calculateDistance(lat, lng, zLat, zLng);
      if (distance <= zRadius) {
        _lastDangerSnackbarTime = now;

        // ✅ Only show if NOT on maps_location
        final currentRoute = ModalRoute.of(context)?.settings.name ?? '';
        if (!currentRoute.contains('maps_location')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              backgroundColor: Colors.red.shade800,
              content: Text(
                '⚠️ You are inside $zName. Stay alert!',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        break;
      }
    }
  }

  void _listenToLocationChanges() {
    _location.onLocationChanged.listen((newLoc) {
      if (_isPermissionGranted &&
          newLoc.latitude != null &&
          newLoc.longitude != null) {
        final newPos = LatLng(newLoc.latitude!, newLoc.longitude!);
        setState(() {
          _userPosition = newPos;
        });
        _checkForDangerZonesAtHome(newPos.latitude, newPos.longitude);
      }
    });
  }


  Future<void> _initializeLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    var permissionGranted = await _location.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted) return;
    }

    final currentLocation = await _location.getLocation();
    setState(() {
      _userPosition = LatLng(currentLocation.latitude!, currentLocation.longitude!);
      _isPermissionGranted = true;
    });
  }


  AudioPlayer? player;

  void _listenToSosAlerts() {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final sosRef = FirebaseDatabase.instance.ref('sos_alerts/$currentUid');

    sosRef.onChildAdded.listen((event) async {
      if (!mounted) return;

      final alertKey = event.snapshot.key ?? '';
      if (_processedAlertKeys.contains(alertKey)) return; // ✅ already handled
      _processedAlertKeys.add(alertKey);

      // ✅ Extract alert details
      final alertData = Map<String, dynamic>.from(event.snapshot.value as Map);
      final senderId = alertData['senderId'] ?? '';
      final location = alertData['location'] ?? {};
      final lat = (location['lat'] ?? 0).toDouble();
      final lng = (location['lng'] ?? 0).toDouble();
      final timestampStr = alertData['timestamp'] ?? '';

      // ✅ Skip old alerts (>24h)
      final alertTime = DateTime.tryParse(timestampStr) ?? DateTime.now();
      if (DateTime.now().difference(alertTime).inHours >= 24) {
        debugPrint("⏰ Ignored old alert from $senderId (older than 24h)");
        return;
      }

      // ✅ Fetch sender info
      Map<String, dynamic>? senderInfo;
      if (senderId.isNotEmpty) {
        final userSnap =
        await FirebaseDatabase.instance.ref('users/$senderId').get();
        if (userSnap.exists) {
          senderInfo = Map<String, dynamic>.from(userSnap.value as Map);
        }
      }

      final username = senderInfo?['username'] ?? 'Unknown User';
      final email = senderInfo?['email'] ?? 'No email';
      final phone = senderInfo?['phone'] ?? 'No phone';
      final profileImage = senderInfo?['profileImage'];
      final address = senderInfo?['address'] ?? 'Unknown';
      final nationality = senderInfo?['nationality'] ?? '';
      final birthdate = senderInfo?['birthdate'] ?? '';

      // ✅ Start vibration + alarm
      if (await Vibration.hasVibrator() ?? false) {
        _vibrationTimer?.cancel();
        _vibrationTimer =
            Timer.periodic(const Duration(seconds: 2), (_) => Vibration.vibrate(duration: 1000));
      }

      player = AudioPlayer();
      try {
        await player!.setSource(AssetSource('audio/lingling.mp3'));
        await player!.setReleaseMode(ReleaseMode.loop);
        await player!.resume();
      } catch (e) {
        print('Audio error: $e');
      }

      // ✅ Show alert popup
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFFFFEAEA),
          title: Text('🚨 SOS Alert from $username'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (profileImage != null)
                Center(
                  child: CircleAvatar(
                    radius: 32,
                    backgroundImage: NetworkImage(profileImage),
                  ),
                ),
              const SizedBox(height: 8),
              Text('📍 Location: $lat, $lng'),
              Text('🏠 Address: $address'),
              Text('📞 Phone: $phone'),
              Text('✉️ Email: $email'),
              if (birthdate.isNotEmpty) Text('🎂 Birthdate: $birthdate'),
              if (nationality.isNotEmpty) Text('🌍 Nationality: $nationality'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                _vibrationTimer?.cancel();
                Vibration.cancel();
                await player?.stop();
                Navigator.pop(context);

                // ✅ Delete the alert from Firebase
                await sosRef.child(alertKey).remove();
                _processedAlertKeys.remove(alertKey);
              },
              child: const Text('Dismiss', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () async {
                _vibrationTimer?.cancel();
                Vibration.cancel();
                await player?.stop();
                Navigator.pop(context);

                // ✅ Remove alert after opening location
                await sosRef.child(alertKey).remove();
                _processedAlertKeys.remove(alertKey);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ViewAlertLocationPage(userId: senderId),
                  ),
                );
              },
              child: const Text('View Location',
                  style: TextStyle(color: Colors.green)),
            ),
          ],
        ),
      );
    });
  }


  // ✅ Load danger zones
  void _listenToDangerZones() {
    _dangerRef.onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        setState(() => _dangerZones = data);
      }
    });
  }

// ✅ Start monitoring user location
  void _startLocationMonitoring() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return;
    }

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((pos) {
      _checkIfInDangerZone(pos.latitude, pos.longitude);
    });
  }

// ✅ Smart danger zone detection with per-zone mute and dialog prompt
  void _checkIfInDangerZone(double lat, double lng) {
    if (_dangerZones.isEmpty) return;

    for (var zoneEntry in _dangerZones.entries) {
      final zoneId = zoneEntry.key; // unique ID from Firebase node key
      final zone = Map<String, dynamic>.from(zoneEntry.value);
      final double zLat = (zone["lat"] as num).toDouble();
      final double zLng = (zone["lng"] as num).toDouble();
      final double zRadius = (zone["radius"] as num).toDouble();
      final String zoneName = zone["name"] ?? "Danger Zone";

      final distance = _calculateDistance(lat, lng, zLat, zLng);

      if (distance <= zRadius) {
        // 🧩 If inside the same muted zone, don't show again
        if (_ignoredZoneId == zoneId) return;

        // 🧩 If a dialog is already visible, don't duplicate
        if (_isDangerAlertVisible) return;

        _isDangerAlertVisible = true;
        _lastDangerPopupTime = DateTime.now();

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFFFFF2F2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Column(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 60, color: Colors.redAccent),
                const SizedBox(height: 12),
                Text(
                  '⚠️ You are inside $zoneName',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            content: const Text(
              "You’ve entered a flagged danger zone. Stay alert and proceed with caution.\n\nWould you like to view the map for more details?",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () {
                  // 🧩 Remember this zone as ignored
                  _ignoredZoneId = zoneId;
                  Future.delayed(const Duration(minutes: 10), () {
                    _ignoredZoneId = null; // re-enable alerts for this zone after 10 minutes
                  });
                  _isDangerAlertVisible = false;
                  Navigator.pop(context);
                },
                child: const Text(
                  "Ignore",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _isDangerAlertVisible = false;
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const MapsLocation()),
                  );
                },
                icon: const Icon(Icons.map, size: 18, color: Colors.white),
                label: const Text(
                  "View Map",
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );

        break; // stop after first matching zone
      }
    }
  }


// ✅ Haversine distance
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  Future<void> _triggerSOSAlert(BuildContext context) async {
    if (context == null || !mounted) return;
    try {
      await SOSService.sendSosAlert(); // 🔔 your existing SOS sending function
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                '🚨 No response detected. SOS alert sent to your contacts!'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ Error sending SOS: $e");
    }
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

// ====================== CHECK-IN FLOW ======================

  void _startCheckInFlow(BuildContext context) {
    _showActivateCheckInDialog(context);
  }

  /// ✅ Step 1: Activate Check-In Dialog with interval selection
  void _showActivateCheckInDialog(BuildContext context) {
    int? selectedMinutes; // null until user selects
    String? errorMessage; // inline error text

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFEFFEF5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Column(
                children: [
                  Image.asset('assets/images/app_logo.png', height: 60),
                  const SizedBox(height: 12),
                  const Text(
                    'Activate Check-In Mode',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Select how often you want to confirm your safety:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  RadioListTile<int>(
                    title: const Text('Every 15 minutes'),
                    value: 15,
                    groupValue: selectedMinutes,
                    onChanged: (value) {
                      setState(() {
                        selectedMinutes = value;
                        errorMessage = null;
                      });
                    },
                  ),
                  RadioListTile<int>(
                    title: const Text('Every 30 minutes'),
                    value: 30,
                    groupValue: selectedMinutes,
                    onChanged: (value) {
                      setState(() {
                        selectedMinutes = value;
                        errorMessage = null;
                      });
                    },
                  ),
                  RadioListTile<int>(
                    title: const Text('Every 1 hour'),
                    value: 60,
                    groupValue: selectedMinutes,
                    onChanged: (value) {
                      setState(() {
                        selectedMinutes = value;
                        errorMessage = null;
                      });
                    },
                  ),
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext, rootNavigator: true).pop();
                  },
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    if (selectedMinutes == null) {
                      setState(() => errorMessage = '⚠️ Please select a time interval.');
                      return;
                    }

                    Navigator.of(dialogContext, rootNavigator: true).pop();
                    _showCheckInConfirmation(context, selectedMinutes!);
                  },
                  child: const Text('Activate'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// ✅ Step 2: Confirmation Dialog before activation (SAFE CONTEXT)
  void _showCheckInConfirmation(BuildContext context, int intervalMinutes) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFEFFEF5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: const [
            Icon(Icons.check_circle, size: 50, color: Colors.green),
            SizedBox(height: 12),
            Text(
              'Check-In Activated',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        content: Text(
          "You’ve successfully activated Check-In Mode.\n\n"
              "You’ll be prompted every $intervalMinutes minutes to confirm your safety.\n"
              "If you don’t respond within 1 minute, your emergency contacts will be notified.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          GestureDetector(
            onTap: () async {
              // ✅ Close the dialog first
              if (Navigator.of(dialogContext, rootNavigator: true).canPop()) {
                Navigator.of(dialogContext, rootNavigator: true).pop();
              }

              // ✅ Wait a bit for dialog to finish closing
              await Future.delayed(const Duration(milliseconds: 150));
              if (!mounted) return;

              // ✅ Safe context lookup
              BuildContext? safeContext;
              try {
                safeContext = Navigator.maybeOf(context)?.context;
              } catch (_) {
                safeContext = null;
              }

              if (safeContext != null && mounted) {
                ScaffoldMessenger.of(safeContext).showSnackBar(
                  SnackBar(
                    content: Text('✅ Check-In activated every $intervalMinutes minutes'),
                    backgroundColor: Colors.green.shade700,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }

              // ✅ Start check-in loop even if SnackBar skipped
              _startSafetyPromptLoop(context, intervalMinutes);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade800,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ Step 3: Start loop timer and first safety prompt
  void _startSafetyPromptLoop(BuildContext context, int intervalMinutes) async {
    if (!mounted) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final startTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    await FirebaseDatabase.instance.ref('check_in_logs/$uid').set({
      'active': true,
      'startTime': startTime,
      'interval': intervalMinutes,
      'responses': {},
    });

    setState(() => _checkInActive = true);
    _isCheckInRunning = true;

    _vibrationTimer?.cancel();
    _responseTimer?.cancel();

    final safeContext = Navigator.maybeOf(context)?.context ?? context;

    // 🟢 Show first prompt immediately
    _showSafetyPrompt(safeContext);

    // 🕒 Schedule repeating prompts
    _vibrationTimer = Timer.periodic(Duration(minutes: intervalMinutes), (t) {
      if (!mounted || !_isCheckInRunning) {
        t.cancel();
        return;
      }
      _showSafetyPrompt(safeContext);
    });
  }

  /// ✅ Step 4: Safety confirmation prompt (auto-SOS after 1 min)
  void _showSafetyPrompt(BuildContext context) async {
    if (!mounted || !_isCheckInRunning) return;
    if (_isPromptVisible) return;

    _isPromptVisible = true;
    _responseTimer?.cancel();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _responseTimer = Timer(const Duration(minutes: 1), () async {
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
          _isPromptVisible = false;
          if (mounted) await _triggerSOSAlert(context);
        });

        return AlertDialog(
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
                    _responseTimer?.cancel();
                    if (Navigator.of(dialogContext).canPop()) {
                      Navigator.of(dialogContext).pop();
                    }
                    _isPromptVisible = false;

                    if (!mounted) return;
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
                    child: const Text("Yes, I'm safe", style: TextStyle(color: Colors.white)),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    _responseTimer?.cancel();
                    await _stopCheckIn(context);
                    if (Navigator.of(dialogContext).canPop()) {
                      Navigator.of(dialogContext).pop();
                    }
                    _isPromptVisible = false;
                  },
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text("Stop Check-In", style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    _isPromptVisible = false;
  }

  List<Map<String, dynamic>> _notifications = [];

  void _listenToContactRequests() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseDatabase.instance.ref('contact_requests/$uid');

    ref.onValue.listen((event) {
      if (!event.snapshot.exists) {
        setState(() => _notifications = []);
        return;
      }

      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      final List<Map<String, dynamic>> newNotifs = [];

      data.forEach((key, value) {
        final req = Map<String, dynamic>.from(value);
        final senderUsername = req['senderUsername'] ?? 'Unknown User';
        final status = req['status'] ?? 'pending';

        if (status == 'pending') {
          newNotifs.add({
            'uid': key,
            'username': senderUsername,
            'timestamp': req['timestamp'] ?? 0,
          });
        }
      });

      // Sort newest first
      newNotifs.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

      setState(() {
        _notifications = newNotifs;
        
      });
    });
  }

  void _showNotificationMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        if (_notifications.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'No pending requests',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        }

        return ListView.builder(
          itemCount: _notifications.length,
          itemBuilder: (context, index) {
            final notif = _notifications[index];
            final username = notif['username'] ?? 'Unknown User';

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFFEFFEF5),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Icon(Icons.person, color: Colors.white),
                ),
                title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('wants to add you as a contact'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () async {
                        await _acceptRequest(notif['uid'], username);
                        Navigator.pop(context);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () async {
                        await _declineRequest(notif['uid']);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
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


  // ============================================================
// ✅ Step 5: Stop Check-In Cleanly
// ============================================================
  Future<void> _stopCheckIn(BuildContext context) async {
    _vibrationTimer?.cancel();
    _responseTimer?.cancel();
    _isCheckInRunning = false;
    _isPromptVisible = false;
    if (context == null || !mounted) return;
    setState(() => _checkInActive = false);

    final uid = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseDatabase.instance.ref('check_in_logs/$uid').update({
      'active': false,
      'endTime': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
    });
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
    return Builder(
      builder: (dialogContext) {
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
                onTap: () {
                  // ✅ Safely close this dialog using its own context
                  if (Navigator.of(dialogContext, rootNavigator: true).canPop()) {
                    Navigator.of(dialogContext, rootNavigator: true).pop();
                  }

                  // ✅ Then run the callback logic
                  onPressed();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
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
      },
    );
  }

  Future<void> sendSosAlert() async {
    await SOSService.sendSosAlert();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚨 SOS sent successfully'),
          backgroundColor: Colors.redAccent,
        ),
      );
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



  // ============================================================
// ✅ Step 6: Dispose Cleanup
// ============================================================
  @override
  void dispose() {
    _rippleController.dispose();
    _vibrationTimer?.cancel();   // ✅ stop interval loop
    _responseTimer?.cancel();    // ✅ stop SOS countdown
    _posSub?.cancel();
    _dangerPlayer.dispose();
    _isCheckInRunning = false;   // ✅ flag for cleanup
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
        backgroundColor: const Color(0xFF264653),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF2A9D8F)),
              accountName: GestureDetector(
                onTap: () {
                  final controller = TextEditingController(text: _username);
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Edit Name'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(hintText: 'Enter your name'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () async {
                            if (controller.text.trim().isNotEmpty) {
                              await FirebaseDatabase.instance.ref("users/${_user!.uid}/username").set(controller.text.trim());
                              setState(() => _username = controller.text.trim());
                            }
                            Navigator.pop(context);
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                },
                child: Text(_username, style: const TextStyle(fontSize: 18)),
              ),
              accountEmail: const Text("user@juantap.com"),
              currentAccountPicture: GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/edit_profile'),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: profileImageUrl != null
                      ? NetworkImage(profileImageUrl!)
                      : const AssetImage('assets/images/user_profile.png') as ImageProvider,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle, color: Colors.white),
              title: const Text('Profile Settings', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pushNamed(context, '/edit_profile'),
            ),
            const Divider(color: Colors.white54),

            ListTile(
              leading: const Icon(Icons.shield, color: Colors.white),
              title: const Text('Self-Defense Guides', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context); // close the drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SelfDefenseGuidePage()),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.mic, color: Colors.white),
              title: const Text('Voice Command Settings', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context); // close the drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const VoiceCommandSettings()),
                );
              },
            ),


            ListTile(
              leading: const Icon(Icons.logout, color: Colors.white),
              title: const Text('Logout', style: TextStyle(color: Colors.white)),
              onTap: () async {
                final shouldLogout = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Confirm Logout'),
                    content: const Text('Are you sure you want to log out?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Logout'),
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
