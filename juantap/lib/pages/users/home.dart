import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:juantap/pages/users/check_in_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:juantap/pages/users/maps_location.dart';
import 'package:juantap/pages/users/self_defense_guide.dart';
import 'package:juantap/pages/users/sos_service.dart';
import 'package:juantap/pages/users/sos_alert_listener.dart';
import 'package:juantap/pages/users/voice_command_settings.dart';
import 'package:location/location.dart' as loc;
import 'package:vibration/vibration.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:juantap/pages/users/sos_service.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // ---- Animation (Ripple for SOS) ----
  late AnimationController _rippleController;
  late Animation<double> _rippleAnimation;
  late SosAlertListener _sosListener;
  late CheckInService _checkInService;
  // voice command ----
  late stt.SpeechToText _speech;
  bool _isVoiceCommandEnabled = false;
  bool _silentMode = false;
  String _keyword = "help";
  bool _isListening = false;
  bool _hasUnreadNotifications = false;
  StreamSubscription<DatabaseEvent>? _notifListener;

  // ---- User/Profile ----
  String _username = '';
  String? profileImageUrl;
  final _user = FirebaseAuth.instance.currentUser;

  // ---- Danger Zone handling ----
  final DatabaseReference _dangerRef =
  FirebaseDatabase.instance.ref('danger_zones');
  Map<String, dynamic> _dangerZones = {};
  bool _isDangerAlertVisible = false;
  String? _ignoredZoneId;
  DateTime? _lastDangerSnackbarTime;
  DateTime? _lastDangerPopupTime;

  // ---- Location (Location package + Geolocator stream) ----
  final loc.Location _location = loc.Location();
  bool _isPermissionGranted = false;
  LatLng? _userPosition;
  StreamSubscription<Position>? _posSub;

  // ---- Audio / vibration for alerts ----
  final AudioPlayer _dangerPlayer = AudioPlayer(); // reserved (not used below)
  AudioPlayer? player; // for SOS alerts from others

  // 🔔 Check-in prompt feedback (beep + vibration during countdown)
  AudioPlayer? _promptPlayer;
  Timer? _promptVibeTimer;

  // ---- Check-in state ----
  bool _isCheckInRunning = false;
  bool _isPromptVisible = false;
  bool _checkInActive = false; // for UI toggles/badges if needed
  Timer? _checkInTimer; // loop timer (test: every 15s)
  Timer? _responseTimer; // per-prompt timeout (15s -> auto SOS)
  Timer? _vibrationTimer; // for incoming SOS popup haptics

  // ---- SOS alerts from contacts ----
  final Set<String> _processedAlertKeys = {};

  // ---- Notifications (contact requests) ----
  List<Map<String, dynamic>> _notifications = [];
  final DatabaseReference _contactsRef =
  FirebaseDatabase.instance.ref('contacts');
  final DatabaseReference _requestsRef =
  FirebaseDatabase.instance.ref('contact_requests');

  // ---- SOS alerts (from contacts) ----
  List<Map<String, dynamic>> _recentSosAlerts = [];

  // ===================== Persistent SOS Alerts (Save/Load) ======================

  Future<void> _saveRecentSosAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedData = jsonEncode(_recentSosAlerts);
      await prefs.setString('recent_sos_alerts', encodedData);
    } catch (e) {
      debugPrint('❌ Error saving recent SOS alerts: $e');
    }
  }

  Future<void> _loadRecentSosAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString('recent_sos_alerts');
      if (savedData != null) {
        final List<dynamic> decoded = jsonDecode(savedData);
        setState(() {
          _recentSosAlerts = decoded.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading recent SOS alerts: $e');
    }
  }

  Future<void> clearNotificationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_sos_alerts');
    setState(() => _recentSosAlerts.clear());
  }

  // ---- Disposal guard ----
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _checkInService = CheckInService();
    _loadRecentSosAlerts();
    _listenToUserSosAlerts();
    _loadContactRequests();
    _speech = stt.SpeechToText();
    _loadVoiceSettings();
    _startNotificationListener();

    // Ripple
    _rippleController =
    AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
    _rippleAnimation =
        CurvedAnimation(parent: _rippleController, curve: Curves.linear);

    // Bootstrap listeners/data
    _loadUserData();
    _listenToContactRequests();
    _listenToDangerZones();
    _startLocationMonitoring();
    _initializeLocation();
    _listenToLocationChanges();
    if (!mounted) return;
    _sosListener = SosAlertListener(context: context);
    _sosListener.startListening();


  }
  void _startNotificationListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final notifRef = FirebaseDatabase.instance.ref('notifications/${currentUser.uid}');
    final sosRef = FirebaseDatabase.instance.ref('sos_alerts/${currentUser.uid}');

    // Listen for both notification and SOS alert changes
    _notifListener = notifRef.onValue.listen((event) async {
      bool hasUnread = false;

      // 🔹 Check contact-accepted notifications
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        for (final n in data.values) {
          final notif = Map<String, dynamic>.from(n);
          if ((notif['read'] == false || notif['read'] == null) &&
              (notif['type'] == 'contact_accept' || notif['type'] == 'general')) {
            hasUnread = true;
            break;
          }
        }
      }

      // 🔹 Check if any SOS alerts exist
      final sosSnap = await sosRef.get();
      if (sosSnap.exists && sosSnap.value != null) {
        final sosData = Map<String, dynamic>.from(sosSnap.value as Map);
        if (sosData.isNotEmpty) hasUnread = true;
      }

      // 🔹 Only update when the value changes (prevents false flickering)
      if (_hasUnreadNotifications != hasUnread) {
        setState(() => _hasUnreadNotifications = hasUnread);
      }
    });
  }
  // voice command starts here//
  Future<void> _loadVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isVoiceCommandEnabled = prefs.getBool("voice_command_enabled") ?? false;
    _silentMode = prefs.getBool("silent_mode") ?? false;
    _keyword = prefs.getString("voice_keyword") ?? "help";

    if (_isVoiceCommandEnabled) {
      await _startVoiceListening();
    }
  }
  Future<bool> _checkAndRequestMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }
  Future<void> _startVoiceListening() async {
    final hasPermission = await _checkAndRequestMicPermission();
    if (!hasPermission) return;

    bool available = false;
    try {
      available = await _speech.initialize(
        onError: (err) => print("🎙️ Voice error: $err"),
      );
    } catch (e) {
      print("⚠️ Speech init exception: $e");
    }

    if (!available) return;

    // ✅ <--- Paste this part right after initialization
    _speech.statusListener = (status) {
      print("🎧 Speech status: $status");
      if (status == "notListening" && _isVoiceCommandEnabled) {
        Future.delayed(const Duration(milliseconds: 300), _startVoiceListening);
      }
    };
    // ✅ End of listener

    _speech.errorListener = (error) {
      if (error.errorMsg.contains("timeout") || error.errorMsg.contains("no match")) {
        Future.delayed(const Duration(milliseconds: 300), _startVoiceListening);
      }
    };

    _isListening = true;
    _speech.listen(
      listenMode: stt.ListenMode.dictation,
      pauseFor: const Duration(seconds: 2), // faster restart
      listenFor: const Duration(minutes: 10),
      partialResults: true,
      onResult: (result) {
        final spoken = result.recognizedWords.toLowerCase();
        print("🎤 Heard: $spoken");
        if (spoken.contains(_keyword.toLowerCase())) {
          _triggerVoiceSOS();
        }
      },
    );
  }
  Future<void> _triggerVoiceSOS() async {
    await SOSService.sendSosAlert();
    if (!_silentMode && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🚨 SOS triggered by voice ($_keyword)'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }
  //voice command ends here//
  // ===================== Listen to SOS Alerts (no duplicates / no popup here) ======================
  void _listenToUserSosAlerts() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final DatabaseReference sosRef =
    FirebaseDatabase.instance.ref('sos_alerts/${currentUser.uid}');

    sosRef.onChildAdded.listen((event) async {
      if (!event.snapshot.exists) return;

      final alertData = Map<String, dynamic>.from(event.snapshot.value as Map);
      final senderId = alertData['userId'];

      // 🚫 Skip your own alert
      if (senderId == currentUser.uid) return;

      // 🚫 Avoid duplicates
      if (_processedAlertKeys.contains(event.snapshot.key)) return;
      _processedAlertKeys.add(event.snapshot.key!);

      // ❌ Removed setState & local save here — handled dynamically in notification menu
      // This method now only keeps track of which alerts were already processed.
    });
  }

  Future<void> _loadContactRequests() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final ref = FirebaseDatabase.instance.ref('contact_requests/${currentUser.uid}');
    final snapshot = await ref.get();

    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      final requests = data.values.map((value) {
        final req = Map<String, dynamic>.from(value);
        return {
          'uid': req['uid'],
          'username': req['senderUsername'] ?? 'Unknown',
        };
      }).toList();

      setState(() => _notifications = requests);
    } else {
      setState(() => _notifications = []);
    }
  }

  // ===================== Data loading ======================

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance.ref('users/${user.uid}');
    final snapshot = await ref.get();
    if (!snapshot.exists) return;

    final data = Map<String, dynamic>.from(snapshot.value as Map);
    if (_isDisposed || !mounted) return;
    setState(() {
      profileImageUrl = data['profileImage'];
      _username = data['username'] ?? '';
    });
  }

  // ===================== Contact requests ==================

  void _listenToContactRequests() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseDatabase.instance.ref('contact_requests/$uid');

    ref.onValue.listen((event) {
      if (_isDisposed || !mounted) return;

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
      newNotifs.sort(
              (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

      setState(() {
        _notifications = newNotifs;
      });
    });
  }

  Future<void> _acceptRequest(String senderUid, String senderUsername) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    await _contactsRef.child(currentUser.uid).child(senderUid).set({
      'name': senderUsername,
      'nickname': '',
    });

    await _contactsRef.child(senderUid).child(currentUser.uid).set({
      'name': currentUser.displayName ?? 'You',
      'nickname': '',
    });

    await _requestsRef.child(currentUser.uid).child(senderUid).remove();

    if (_isDisposed || !mounted) return;
    setState(() {
      _notifications.removeWhere((req) => req['uid'] == senderUid);
    });
  }

  Future<void> _declineRequest(String senderUid) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    await _requestsRef.child(currentUser.uid).child(senderUid).remove();

    if (_isDisposed || !mounted) return;
    setState(() {
      _notifications.removeWhere((req) => req['uid'] == senderUid);
    });
  }

  // ===================== Notifications (Contact Requests Only) ==================
  // ===================== Notifications (Contact Requests + Recent SOS Alerts) ======================
  void _showNotificationMenu(BuildContext context) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // 🔹 Load saved alerts (persistent local)
    await _loadRecentSosAlerts();
    List<Map<String, dynamic>> mergedSosAlerts = List.from(_recentSosAlerts);

    // 🔹 Fetch latest SOS alerts from Firebase
    final sosRef = FirebaseDatabase.instance.ref('sos_alerts/${currentUser.uid}');
    final snapshot = await sosRef.get();

    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      data.forEach((key, value) {
        final alert = Map<String, dynamic>.from(value);
        final location = (alert['location'] != null)
            ? Map<String, dynamic>.from(alert['location'])
            : {};
        final newAlert = {
          'username': alert['username'] ?? 'Unknown',
          'timestamp': (alert['timestamp'] is int)
              ? alert['timestamp']
              : (alert['timestamp'] ?? 0),
          'lat': (location['lat'] is num)
              ? (location['lat'] as num).toDouble()
              : 0.0,
          'lng': (location['lng'] is num)
              ? (location['lng'] as num).toDouble()
              : 0.0,
          'profileImage': alert['profileImage'] ?? '',
        };

        final exists = mergedSosAlerts.any((a) =>
        a['timestamp'] == newAlert['timestamp'] &&
            a['username'] == newAlert['username']);
        if (!exists) mergedSosAlerts.insert(0, newAlert);
      });
    }

    // Sort newest first
    mergedSosAlerts.sort((a, b) =>
        ((b['timestamp'] ?? 0) as int).compareTo((a['timestamp'] ?? 0) as int));

    // ✅ Save merged list locally
    setState(() => _recentSosAlerts = mergedSosAlerts);
    await _saveRecentSosAlerts();

    // 🔔 Fetch "contact accepted" notifications
    final notifRef = FirebaseDatabase.instance.ref('notifications/${currentUser.uid}');
    final notifSnapshot = await notifRef.get();

    List<Map<String, dynamic>> acceptedNotifications = [];
    if (notifSnapshot.exists) {
      final notifData = Map<String, dynamic>.from(notifSnapshot.value as Map);
      notifData.forEach((key, value) {
        final n = Map<String, dynamic>.from(value);
        acceptedNotifications.add({
          'id': key,
          'title': n['title'] ?? 'Notification',
          'message': n['message'] ?? '',
          'timestamp': (n['timestamp'] is int)
              ? n['timestamp']
              : (n['timestamp'] ?? 0),
          'read': n['read'] ?? false,
          'type': n['type'] ?? 'general',
        });
      });

      acceptedNotifications.sort((a, b) =>
          ((b['timestamp'] ?? 0) as int).compareTo((a['timestamp'] ?? 0) as int));
    }

    // 🔔 Show notification modal
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF9F9F9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) {
        final hasNoNotifications =
            _recentSosAlerts.isEmpty && acceptedNotifications.isEmpty;

        if (hasNoNotifications) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Text(
                'No notifications yet',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: ListView(
            children: [
              // 🚨 RECENT SOS ALERTS
              if (_recentSosAlerts.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: Text(
                    '🚨 Recent SOS Alerts',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
                ..._recentSosAlerts.map((alert) {
                  final timestampValue = alert['timestamp'];
                  final dateTime = (timestampValue is int && timestampValue > 0)
                      ? DateTime.fromMillisecondsSinceEpoch(timestampValue)
                      : DateTime.now();
                  final formattedTime =
                  DateFormat.yMMMd().add_jm().format(dateTime);

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade50,
                        radius: 22,
                        child: const Icon(Icons.warning_amber_rounded,
                            color: Colors.redAccent),
                      ),
                      title: Text(
                        'SOS from ${alert['username']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          formattedTime,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.map, color: Colors.green),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SosAlertListenerPage(
                                senderName: alert['username'],
                                latitude: alert['lat'] ?? 0.0,
                                longitude: alert['lng'] ?? 0.0,
                                profileImage: alert['profileImage'],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],

              // ✅ CONTACT ACCEPTED NOTIFICATIONS
              if (acceptedNotifications.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 6),
                  child: Text(
                    '👥 Contact Updates',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueAccent,
                    ),
                  ),
                ),
                ...acceptedNotifications.map((notif) {
                  final timestampValue = notif['timestamp'];
                  final dateTime = (timestampValue is int && timestampValue > 0)
                      ? DateTime.fromMillisecondsSinceEpoch(timestampValue)
                      : DateTime.now();
                  final formattedTime =
                  DateFormat.yMMMd().add_jm().format(dateTime);

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    decoration: BoxDecoration(
                      color: notif['read'] ? Colors.white : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: const Icon(Icons.check_circle,
                            color: Colors.blueAccent),
                      ),
                      title: Text(
                        notif['title'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        '${notif['message']}\n$formattedTime',
                        style:
                        const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      onTap: () async {
                        await FirebaseDatabase.instance
                            .ref('notifications/${currentUser.uid}/${notif['id']}')
                            .update({'read': true});
                        Navigator.pop(context);
                      },
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],

              // 🧹 CLEAR HISTORY
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  label: const Text(
                    "Clear Notification History",
                    style: TextStyle(color: Colors.redAccent, fontSize: 14),
                  ),
                  onPressed: () async {
                    await clearNotificationHistory();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Notification history cleared"),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  // ===================== Danger Zones =======================

  void _listenToDangerZones() {
    _dangerRef.onValue.listen((event) {
      if (!event.snapshot.exists) return;
      final data = Map<String, dynamic>.from(event.snapshot.value as Map);
      if (_isDisposed || !mounted) return;
      setState(() => _dangerZones = data);
    });
  }

  void _startLocationMonitoring() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      perm = await Geolocator.requestPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
    }

    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      _checkIfInDangerZone(pos.latitude, pos.longitude);
    });
  }

  void _checkIfInDangerZone(double lat, double lng) {
    if (_dangerZones.isEmpty) return;

    for (final zoneEntry in _dangerZones.entries) {
      final zoneId = zoneEntry.key;
      final zone = Map<String, dynamic>.from(zoneEntry.value);
      final double zLat = (zone['lat'] as num).toDouble();
      final double zLng = (zone['lng'] as num).toDouble();
      final double zRadius = (zone['radius'] as num).toDouble();
      final String zoneName = zone['name'] ?? 'Danger Zone';

      final distance = _calculateDistance(lat, lng, zLat, zLng);

      if (distance <= zRadius) {
        if (_ignoredZoneId == zoneId) return; // muted temporarily
        if (_isDangerAlertVisible) return;

        _isDangerAlertVisible = true;
        _lastDangerPopupTime = DateTime.now();

        if (_isDisposed || !mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFFFFF2F2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Column(
              children: const [
                Icon(Icons.warning_amber_rounded,
                    size: 60, color: Colors.redAccent),
                SizedBox(height: 12),
                Text(
                  '⚠️ You are inside a danger zone',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            content: Text(
              'Zone: $zoneName\n\n'
                  'You’ve entered a flagged danger zone. Stay alert and proceed with caution.\n\n'
                  'Would you like to view the map for more details?',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () {
                  _ignoredZoneId = zoneId;
                  Future.delayed(const Duration(minutes: 10),
                          () => _ignoredZoneId = null);
                  _isDangerAlertVisible = false;
                  if (mounted) Navigator.pop(context);
                },
                child:
                const Text('Ignore', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  _isDangerAlertVisible = false;
                  if (mounted) Navigator.pop(context);
                  if (mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MapsLocation(),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.map, size: 18, color: Colors.white),
                label: const Text('View Map',
                    style: TextStyle(color: Colors.white)),
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

        break;
      }
    }
  }

  // snackbar hint on home (not on map screen)
  void _checkForDangerZonesAtHome(double lat, double lng) {
    if (_dangerZones.isEmpty) return;

    final now = DateTime.now();
    if (_lastDangerSnackbarTime != null &&
        now.difference(_lastDangerSnackbarTime!).inSeconds < 10) {
      return;
    }

    for (final entry in _dangerZones.entries) {
      final zone = Map<String, dynamic>.from(entry.value);
      final zLat = (zone['lat'] as num).toDouble();
      final zLng = (zone['lng'] as num).toDouble();
      final zRadius = (zone['radius'] as num).toDouble();
      final zName = zone['name'] ?? 'Danger Zone';

      final distance = _calculateDistance(lat, lng, zLat, zLng);
      if (distance <= zRadius) {
        _lastDangerSnackbarTime = now;

        final currentRoute = ModalRoute.of(context)?.settings.name ?? '';
        if (!currentRoute.contains('maps_location') && mounted) {
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

  // ===================== Location (Location package) ========

  void _listenToLocationChanges() {
    _location.onLocationChanged.listen((newLoc) {
      if (!_isPermissionGranted ||
          newLoc.latitude == null ||
          newLoc.longitude == null) return;

      final newPos = LatLng(newLoc.latitude!, newLoc.longitude!);
      if (_isDisposed || !mounted) return;
      setState(() => _userPosition = newPos);

      _checkForDangerZonesAtHome(newPos.latitude, newPos.longitude);
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
    if (_isDisposed || !mounted) return;
    setState(() {
      _userPosition =
          LatLng(currentLocation.latitude!, currentLocation.longitude!);
      _isPermissionGranted = true;
    });
  }

  // ===================== SOS actions (self) =================

  Future<void> sendSosAlert() async {
    await SOSService.sendSosAlert();
    if (_isDisposed || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚨 SOS sent successfully'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _triggerSOSAlert(BuildContext context) async {
    try {
      await SOSService.sendSosAlert();
      if (_isDisposed || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              '🚨 No response detected. SOS alert sent to your contacts!'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error sending SOS: $e');
    }
  }

  void _confirmAndSendSOS() {
    int secondsLeft = 5;
    Timer? countdownTimer;
    bool isCancelled = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            countdownTimer ??=
                Timer.periodic(const Duration(seconds: 1), (timer) {
                  if (secondsLeft == 1) {
                    timer.cancel();
                    if (mounted) Navigator.pop(context);
                    if (!isCancelled) sendSosAlert();
                  } else {
                    setState(() => secondsLeft--);
                  }
                });

            return AlertDialog(
              title: const Text('️Do you want to Send SOS?️'),
              content: Text('Sending SOS in $secondsLeft seconds...'),
              actions: [
                TextButton(
                  onPressed: () {
                    isCancelled = true;
                    countdownTimer?.cancel();
                    if (mounted) Navigator.pop(context);
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

  // ===================== Utilities ==========================

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  // ===================== Dispose ============================

  @override
  void dispose() {
    _isDisposed = true;
    _rippleController.dispose();
    _checkInTimer?.cancel();
    _vibrationTimer?.cancel();
    _responseTimer?.cancel();
    _posSub?.cancel();
    _speech.stop();
    // stop and dispose prompt player
    _checkInService.stopCheckIn();
    _promptPlayer?.dispose();

    _dangerPlayer.dispose();
    _isCheckInRunning = false;
    _sosListener.stopListening();
    _notifListener?.cancel();
    super.dispose();
  }

  // ===================== UI ================================

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
            Image.asset('assets/images/app_logo.png', height: 26),
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
                icon: const Icon(Icons.notifications, color: Colors.white),
                onPressed: () {
                  setState(() => _hasUnreadNotifications = false); // remove dot
                  _showNotificationMenu(context);
                },
              ),
              if (_hasUnreadNotifications)
                Positioned(
                  right: 10,
                  top: 10,
                  child: AnimatedOpacity(
                    opacity: _hasUnreadNotifications ? 1 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
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
                        decoration: const InputDecoration(
                            hintText: 'Enter your name'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final txt = controller.text.trim();
                            if (txt.isNotEmpty && _user != null) {
                              await FirebaseDatabase.instance
                                  .ref('users/${_user!.uid}/username')
                                  .set(txt);
                              if (!_isDisposed && mounted) {
                                setState(() => _username = txt);
                              }
                            }
                            if (mounted) Navigator.pop(context);
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                },
                child: Text(_username, style: const TextStyle(fontSize: 18)),
              ),
              accountEmail: const Text('user@juantap.com'),
              currentAccountPicture: GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/edit_profile'),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: profileImageUrl != null
                      ? NetworkImage(profileImageUrl!)
                      : const AssetImage('assets/images/user_profile.png')
                  as ImageProvider,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle, color: Colors.white),
              title: const Text('Profile Settings',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pushNamed(context, '/edit_profile'),
            ),
            const Divider(color: Colors.white54),
            ListTile(
              leading: const Icon(Icons.shield, color: Colors.white),
              title: const Text('Self-Defense Guides',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SelfDefenseGuidePage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.mic, color: Colors.white),
              title: const Text('Voice Command Settings',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const VoiceCommandSettings()),
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
                    content:
                    const Text('Are you sure you want to log out?'),
                    actions: [
                      TextButton(
                          onPressed: () =>
                              Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(context, true),
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
                        final value =
                            (_rippleAnimation.value + index * 0.33) % 1.0;
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
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 4))
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'SOS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                    onTap: () =>
                        Navigator.pushNamed(context, '/maps_location'),
                  ),
                  BottomMenuButton(
                    imagePath: 'assets/images/checkIn_button.png',
                    label: 'Check-In',
                    onTap: () => _checkInService.startCheckInFlow(context),
                  ),
                  BottomMenuButton(
                    imagePath: 'assets/images/contact_button.png',
                    label: 'Contacts',
                    onTap: () =>
                        Navigator.pushNamed(context, '/contact_lists'),
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
    properties.add(
        DiagnosticsProperty<Timer?>('_vibrationTimer', _vibrationTimer));
  }
}

// --- Small UI helper ---

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
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
