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
  bool _isDialogOpen = false; // Prevent stacked dialogs
  Timer? _checkInTimer;
  Timer? _responseTimer;
  Timer? _promptVibeTimer;
  AudioPlayer? _promptPlayer;

  // ====== NEW: selected interval state ======
  // In TEST mode, we map every option to 10 seconds.
  // Toggle this flag to false when you want real durations.
  static const bool _TEST_INTERVALS = true;

  // Labels shown to the user
  static const List<String> _intervalLabels = ['15 mins', '30 mins', '1 hour'];

  // Under-the-hood mapping (test vs real)
  static Duration _mapLabelToDuration(String label) {
    if (_TEST_INTERVALS) {
      // -------- TESTING: FORCE ALL TO 10 SECONDS --------
      return const Duration(seconds: 10);
    } else {
      // -------- PRODUCTION DURATIONS --------
      switch (label) {
        case '15 mins':
          return const Duration(minutes: 15);
        case '30 mins':
          return const Duration(minutes: 30);
        case '1 hour':
        default:
          return const Duration(hours: 1);
      }
    }
  }

  // Keep the current selection (default to 15 mins)
  String _selectedIntervalLabel = _intervalLabels.first;
  Duration get _selectedInterval => _mapLabelToDuration(_selectedIntervalLabel);

  bool _isContextSafe(BuildContext context) => context.mounted;

  /// Entry point from HomePage
  void startCheckInFlow(BuildContext context) {
    if (!_isContextSafe(context)) return;
    _showActivateCheckInDialog(context);
  }

  // ----------------------------------------------------------
  // Step 1: Activate Check-In  (with interval selection)
  // ----------------------------------------------------------
  void _showActivateCheckInDialog(BuildContext context) {
    if (_isDialogOpen || !_isContextSafe(context)) return;
    _isDialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setStateSB) {
          return AlertDialog(
            backgroundColor: const Color(0xFFEFFEF5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                  'You’ll be prompted regularly to confirm your safety.\n\n'
                      'Select how often you want to be prompted:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: _intervalLabels.map((lbl) {
                    final bool selected = _selectedIntervalLabel == lbl;
                    return ChoiceChip(
                      label: Text(lbl),
                      selected: selected,
                      onSelected: (isSel) {
                        if (!isSel) return;
                        setStateSB(() {
                          _selectedIntervalLabel = lbl;
                        });
                      },
                      selectedColor: Colors.green.shade700,
                      labelStyle: TextStyle(
                        color: selected ? Colors.white : Colors.black87,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      ),
                      backgroundColor: Colors.white,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                // if (_TEST_INTERVALS)
                //   const Text(
                //     '⚠️ Test mode: all intervals = 10 seconds',
                //     style: TextStyle(fontSize: 12, color: Colors.redAccent),
                //     textAlign: TextAlign.center,
                //   ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: () {
                  if (_isContextSafe(dialogContext)) Navigator.pop(dialogContext);
                  _isDialogOpen = false;
                },
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (!_isContextSafe(dialogContext)) return;
                  Navigator.of(dialogContext, rootNavigator: true).pop();
                  _isDialogOpen = false;

                  await Future.delayed(const Duration(milliseconds: 300));
                  final safeContext = Navigator.of(context, rootNavigator: true).context;

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_isContextSafe(safeContext)) {
                      _showCheckInConfirmation(safeContext);
                    }
                  });
                },
                child: const Text('Activate'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ----------------------------------------------------------
  // Step 2: Confirmation
  // ----------------------------------------------------------
  void _showCheckInConfirmation(BuildContext context) {
    if (_isDialogOpen || !_isContextSafe(context)) return;
    _isDialogOpen = true;

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
          "✅ Check-In Mode is now active.\n"
              "You’ll be prompted every ${_selectedIntervalLabel.toLowerCase()}.",
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          GestureDetector(
            onTap: () async {
              if (Navigator.canPop(dialogContext)) {
                Navigator.of(dialogContext, rootNavigator: true).pop();
              }
              _isDialogOpen = false;

              await Future.delayed(const Duration(milliseconds: 200));

              if (_isContextSafe(context)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Check-In Mode Activated — interval: ${_selectedIntervalLabel.toLowerCase()}'),
                    backgroundColor: Colors.green.shade700,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }

              // Start the loop with the selected interval
              _startSafetyPromptLoop(context, _selectedInterval);

              // Show the first prompt shortly after activation (unchanged)
              Future.delayed(const Duration(seconds: 1), () {
                if (_isContextSafe(context)) {
                  _showSafetyPrompt(context);
                }
              });
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade800,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text('Confirm', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // Step 3: Start loop
  // ----------------------------------------------------------
  void _startSafetyPromptLoop(BuildContext context, Duration intervalDuration) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final startTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    await FirebaseDatabase.instance.ref('check_in_logs/$uid').set({
      'active': true,
      'startTime': startTime,
      'interval': _TEST_INTERVALS
          ? '${_selectedIntervalLabel} (TEST: ${intervalDuration.inSeconds}s)'
          : _selectedIntervalLabel,
    });

    _isRunning = true;
    _isPromptVisible = false;

    _checkInTimer?.cancel();
    _checkInTimer = Timer.periodic(intervalDuration, (t) {
      if (!_isRunning) {
        t.cancel();
        return;
      }
      if (!_isPromptVisible && !_isDialogOpen && _isContextSafe(context)) {
        _showSafetyPrompt(context);
      }
    });
  }

  // ----------------------------------------------------------
  // Step 4: Safety prompt dialog
  // ----------------------------------------------------------
  Future<void> _showSafetyPrompt(BuildContext context) async {
    if (_isPromptVisible || !_isRunning || _isDialogOpen || !_isContextSafe(context)) return;

    _isPromptVisible = true;
    _isDialogOpen = true;

    _responseTimer?.cancel();
    _responseTimer = Timer(const Duration(seconds: 10), () async {
      print("⏰ Timeout — sending SOS");
      await _stopPromptFeedback();
      if (Navigator.canPop(context)) Navigator.pop(context);

      // 🟥 Show snackbar before sending SOS
      if (_isContextSafe(context)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚨 No response detected. Sending SOS alert...'),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 3),
          ),
        );
      }

      // 🚨 Trigger SOS and stop check-in mode completely
      await _triggerSOSAlert(context);
      await stopCheckIn(); // ✅ Stop everything after SOS

      _isPromptVisible = false;
      _isDialogOpen = false;
    });

    await _startPromptFeedback();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFFEFFEF5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.only(top: 20),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
        actionsPadding: const EdgeInsets.only(bottom: 20),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ✅ “Yes, I'm Safe”
              GestureDetector(
                onTap: () async {
                  _responseTimer?.cancel();
                  await _stopPromptFeedback();
                  if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);

                  _isPromptVisible = false;
                  _isDialogOpen = false;

                  if (_isContextSafe(context)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("👍 Check-in confirmed — you're safe."),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Container(
                  alignment: Alignment.center,
                  width: 180,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade800,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    "Yes, I'm safe",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 🛑 Stop Check-In
              GestureDetector(
                onTap: () async {
                  _responseTimer?.cancel();
                  await _stopPromptFeedback();
                  if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);

                  _isPromptVisible = false;
                  _isDialogOpen = false;

                  await stopCheckIn();
                  if (_isContextSafe(context)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("🛑 Check-In Mode stopped manually."),
                        backgroundColor: Colors.redAccent,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Container(
                  alignment: Alignment.center,
                  width: 180,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.shade700,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    "Stop Check-In",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    await _stopPromptFeedback();
    _responseTimer?.cancel();
    _isPromptVisible = false;
    _isDialogOpen = false;
  }

  // ----------------------------------------------------------
  // Step 5: Sound + vibration
  // ----------------------------------------------------------
  Future<void> _startPromptFeedback() async {
    if (await Vibration.hasVibrator() ?? false) {
      _promptVibeTimer?.cancel();
      _promptVibeTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          await Vibration.vibrate(duration: 350);
        } catch (_) {}
      });
    }

    try {
      _promptPlayer ??= AudioPlayer();
      await _promptPlayer!.setSource(AssetSource('audio/check-in-alarm.mp3'));
      await _promptPlayer!.setReleaseMode(ReleaseMode.loop);
      await _promptPlayer!.resume();
    } catch (e) {
      print("⚠️ Audio start error: $e");
    }
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
  // Step 6: SOS Trigger
  // ----------------------------------------------------------
  Future<void> _triggerSOSAlert(BuildContext context) async {
    if (!_isContextSafe(context)) return;
    try {
      await SOSService.sendSosAlert();
      if (_isContextSafe(context)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🚨 SOS alert sent to your contacts!'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print("❌ SOS error: $e");
    }
  }

  // ----------------------------------------------------------
  // Step 7: Stop Check-In Manually
  // ----------------------------------------------------------
  Future<void> stopCheckIn() async {
    _checkInTimer?.cancel();
    _responseTimer?.cancel();
    await _stopPromptFeedback();

    _isRunning = false;
    _isPromptVisible = false;
    _isDialogOpen = false;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseDatabase.instance.ref('check_in_logs/$uid').update({
        'active': false,
        'endTime': DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
      });
    }
  }
}
