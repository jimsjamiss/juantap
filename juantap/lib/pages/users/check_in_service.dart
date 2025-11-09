import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:vibration/vibration.dart';
import 'package:intl/intl.dart';
import 'package:juantap/pages/users/sos_service.dart';

class CheckInService {
  bool _isRunning = false;
  bool _isPromptVisible = false;
  Timer? _checkInTimer;
  Timer? _responseTimer;
  Timer? _promptVibeTimer;
  AudioPlayer? _promptPlayer;

  /// ✅ Safe context checker
  bool _isContextSafe(BuildContext context) {
    return context.mounted &&
        Navigator.of(context, rootNavigator: true).context.mounted;
  }

  /// Public entry point from HomePage button
  void startCheckInFlow(BuildContext context) {
    if (!_isContextSafe(context)) return;
    _showActivateCheckInDialog(context);
  }

  // ----------------------------------------------------------
  // Step 1: Select interval
  // ----------------------------------------------------------
  void _showActivateCheckInDialog(BuildContext context) {
    int? selectedMinutes;
    String? errorMessage;

    if (!_isContextSafe(context)) return;

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
                    if (!_isContextSafe(dialogContext)) return;
                    Navigator.of(dialogContext, rootNavigator: true).pop();
                  },
                  child:
                  const Text('Cancel', style: TextStyle(color: Colors.grey)),
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
                      setState(() =>
                      errorMessage = '⚠️ Please select a time interval.');
                      return;
                    }
                    if (!_isContextSafe(dialogContext)) return;
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

  // ----------------------------------------------------------
  // Step 2: Confirmation dialog
  // ----------------------------------------------------------
  void _showCheckInConfirmation(BuildContext context, int intervalMinutes) {
    if (!_isContextSafe(context)) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFEFFEF5),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              "If you don’t respond in time, your emergency contacts will be notified.",
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          GestureDetector(
            onTap: () async {
              if (_isContextSafe(dialogContext)) {
                Navigator.of(dialogContext, rootNavigator: true).pop();
              }

              if (_isContextSafe(context)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '✅ Check-In activated every $intervalMinutes minutes'),
                    backgroundColor: Colors.green.shade700,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }

              _startSafetyPromptLoop(context, intervalMinutes);
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade800,
                borderRadius: BorderRadius.circular(30),
              ),
              child:
              const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Step 3: Start prompt loop
  // ----------------------------------------------------------
  void _startSafetyPromptLoop(BuildContext context, int intervalMinutes) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final startTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    await FirebaseDatabase.instance.ref('check_in_logs/$uid').set({
      'active': true,
      'startTime': startTime,
      'interval': intervalMinutes,
      'responses': {},
    });

    _isRunning = true;
    _isPromptVisible = false;

    Future.delayed(const Duration(seconds: 1), () {
      if (_isRunning && _isContextSafe(context)) _showSafetyPrompt(context);
    });

    _checkInTimer?.cancel();
    _checkInTimer = Timer.periodic(Duration(minutes: intervalMinutes), (t) {
      if (!_isRunning) {
        t.cancel();
        return;
      }
      if (!_isPromptVisible && _isContextSafe(context)) {
        Future.microtask(() => _showSafetyPrompt(context));
      }
    });
  }

  // ----------------------------------------------------------
  // Step 4: Safety prompt dialog
  // ----------------------------------------------------------
  Future<void> _showSafetyPrompt(BuildContext context) async {
    if (_isPromptVisible || !_isRunning || !_isContextSafe(context)) return;
    _isPromptVisible = true;

    _responseTimer?.cancel();
    _responseTimer = Timer(const Duration(seconds: 15), () async {
      await _stopPromptFeedback();
      if (_isContextSafe(context) &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _isPromptVisible = false;
      await _triggerSOSAlert(context);
    });

    await _startPromptFeedback();

    if (!_isContextSafe(context)) return;

    await showDialog(
      context: Navigator.of(context, rootNavigator: true).context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFEFFEF5),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          GestureDetector(
            onTap: () async {
              _responseTimer?.cancel();
              await _stopPromptFeedback();
              if (_isContextSafe(dialogContext)) {
                Navigator.of(dialogContext, rootNavigator: true).pop();
              }
              _isPromptVisible = false;
            },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade800,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text("Yes, I'm safe",
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );

    await _stopPromptFeedback();
    _responseTimer?.cancel();
    _isPromptVisible = false;
  }

  // ----------------------------------------------------------
  // Step 5: Feedback (sound + vibration)
  // ----------------------------------------------------------
  Future<void> _startPromptFeedback() async {
    if (await Vibration.hasVibrator() ?? false) {
      _promptVibeTimer?.cancel();
      _promptVibeTimer =
          Timer.periodic(const Duration(seconds: 2), (_) async {
            try {
              await Vibration.vibrate(duration: 350);
            } catch (_) {}
          });
    }

    try {
      _promptPlayer ??= AudioPlayer();
      await _promptPlayer!.setSource(AssetSource('audio/ring_ring.mp3'));
      await _promptPlayer!.setReleaseMode(ReleaseMode.loop);
      await _promptPlayer!.resume();
    } catch (_) {}
  }

  Future<void> _stopPromptFeedback() async {
    _promptVibeTimer?.cancel();
    _promptVibeTimer = null;
    try {
      await Vibration.cancel();
    } catch (_) {}
    try {
      await _promptPlayer?.stop();
    } catch (_) {}
  }

  // ----------------------------------------------------------
  // Step 6: Auto SOS trigger
  // ----------------------------------------------------------
  Future<void> _triggerSOSAlert(BuildContext context) async {
    if (!_isContextSafe(context)) return;
    try {
      await SOSService.sendSosAlert();
      if (_isContextSafe(context)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
            Text('🚨 No response detected. SOS alert sent to your contacts!'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error sending SOS: $e');
    }
  }

  // ----------------------------------------------------------
  // Step 7: Stop check-in manually
  // ----------------------------------------------------------
  Future<void> stopCheckIn() async {
    _checkInTimer?.cancel();
    _responseTimer?.cancel();
    await _stopPromptFeedback();

    _isRunning = false;
    _isPromptVisible = false;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseDatabase.instance.ref('check_in_logs/$uid').update({
        'active': false,
        'endTime': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      });
    }
  }
}
