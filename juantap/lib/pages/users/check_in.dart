import 'package:flutter/material.dart';
import 'dart:async';
import 'package:juantap/pages/users/sos_service.dart'; // ✅ for SOS alert

class CheckInPage extends StatefulWidget {
  @override
  _CheckInPageState createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  Timer? _safetyPromptTimer;
  Timer? _responseTimer; // ✅ timer for user's response timeout
  bool _isFollowUpDialogVisible = false; // ✅ prevents stacked dialogs

  void _startCheckInProcess() {
    _showActivateCheckInDialog();
  }

  void _showActivateCheckInDialog() {
    showDialog(
      context: context,
      builder: (_) => _buildModalDialog(
        image: 'assets/images/checkIn_button.png',
        title: 'Activate Check-in mode?',
        buttonText: 'Apply',
        onPressed: () {
          Navigator.pop(context);
          _showCheckInConfirmation();
        },
      ),
    );
  }

  void _showCheckInConfirmation() {
    showDialog(
      context: context,
      builder: (_) => _buildModalDialog(
        icon: Icons.check_circle,
        iconColor: Colors.green,
        title: 'Please read carefully',
        content:
        "You've successfully checked in.\nWe're actively monitoring your status for your safety.\n\nWe’ll prompt you every 5 minutes. If there’s no reply within 1 minute, we’ll alert your contacts.",
        buttonText: 'Confirm',
        onPressed: () {
          Navigator.pop(context);
          _startSafetyPromptTimer();
        },
      ),
    );
  }

  /// ✅ Show the follow-up prompt safely (one at a time)
  void _showFollowUpCheckIn() async {
    if (_isFollowUpDialogVisible) return; // prevent stacking
    _isFollowUpDialogVisible = true;

    // stop any pending SOS countdown
    _responseTimer?.cancel();

    // Show dialog
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // Start countdown for SOS alert
        _responseTimer = Timer(const Duration(minutes: 1), () async {
          // user didn’t respond within 1 minute
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
          _isFollowUpDialogVisible = false;
          await _triggerSOSAlert();
        });

        return _buildModalDialog(
          image: 'assets/images/checkIn_button.png',
          title: 'Are you safe right now?\nPlease confirm your status.',
          buttonText: 'Yes, I\'m safe',
          onPressed: () {
            // user confirmed safety
            _responseTimer?.cancel();
            if (Navigator.of(dialogContext).canPop()) {
              Navigator.of(dialogContext).pop();
            }
            _isFollowUpDialogVisible = false;
            _restartSafetyPromptTimer();
          },
        );
      },
    );

    _isFollowUpDialogVisible = false;
  }

  /// ✅ Send SOS if no response
  Future<void> _triggerSOSAlert() async {
    try {
      await SOSService.sendSosAlert(); // your existing SOS function
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

  /// ✅ Start repeating timer for follow-ups (every 5 min)
  void _startSafetyPromptTimer() {
    _safetyPromptTimer?.cancel();
    _safetyPromptTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) _showFollowUpCheckIn();
    });
  }

  /// ✅ Restart after user confirms
  void _restartSafetyPromptTimer() {
    _safetyPromptTimer?.cancel();
    _safetyPromptTimer = Timer(const Duration(minutes: 5), () {
      if (mounted) _showFollowUpCheckIn();
    });
  }

  @override
  void dispose() {
    _safetyPromptTimer?.cancel();
    _responseTimer?.cancel();
    super.dispose();
  }

  // ===================================================
  //  UI Helper for reusable modal dialogs
  // ===================================================
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
              margin: const EdgeInsets.symmetric(vertical: 10),
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
  }

  // ===================================================
  //  MAIN UI
  // ===================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      body: Center(
        child: GestureDetector(
          onTap: _startCheckInProcess,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/checkIn_button.png', height: 100),
              const SizedBox(height: 20),
              const Text('Tap to Check-In',
                  style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.black,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              const Icon(Icons.map, color: Colors.white),
              const Icon(Icons.contacts, color: Colors.white),
              GestureDetector(
                onTap: _startCheckInProcess,
                child:
                Image.asset('assets/images/checkIn_button.png', height: 50),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
