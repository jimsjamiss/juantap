import 'package:flutter/material.dart';
import 'dart:async';

class CheckInPage extends StatefulWidget {
  @override
  _CheckInPageState createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  Timer? _safetyPromptTimer;

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
        "You've successfully checked in.\nWe're actively monitoring your status for your safety.\n\nWe’ll prompt you every 5 minutes. If there’s no reply, we’ll alert your contacts.",
        buttonText: 'Confirm',
        onPressed: () {
          Navigator.pop(context);
          _startSafetyPromptTimer();
        },
      ),
    );
  }

  void _showFollowUpCheckIn() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _buildModalDialog(
        image: 'assets/images/checkIn_button.png',
        title: 'Are you safe right now?\nPlease confirm your status.',
        buttonText: 'Yes, I\'m safe',
        onPressed: () {
          Navigator.pop(context);
          _restartSafetyPromptTimer();
        },
      ),
    );
  }

  void _startSafetyPromptTimer() {
    _safetyPromptTimer?.cancel();
    _safetyPromptTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      _showFollowUpCheckIn();
    });
  }

  void _restartSafetyPromptTimer() {
    _safetyPromptTimer?.cancel();
    _safetyPromptTimer = Timer(Duration(minutes: 5), () {
      _showFollowUpCheckIn();
    });
  }

  @override
  void dispose() {
    _safetyPromptTimer?.cancel();
    super.dispose();
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
      backgroundColor: Color(0xFFEFFEF5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        children: [
          if (icon != null)
            Icon(icon, size: 50, color: iconColor)
          else if (image != null)
            Image.asset(image, height: 60),
          SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (content != null) ...[
            SizedBox(height: 12),
            Text(
              content,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
          ],
        ],
      ),
      actions: [
        Center(
          child: GestureDetector(
            onTap: onPressed,
            child: Container(
              margin: EdgeInsets.symmetric(vertical: 10),
              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.green.shade800,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                buttonText,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        )
      ],
    );
  }

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
              SizedBox(height: 20),
              Text('Tap to Check-In', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.black,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 30, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Icon(Icons.map, color: Colors.white),
              Icon(Icons.contacts, color: Colors.white),
              GestureDetector(
                onTap: _startCheckInProcess,
                child: Image.asset('assets/images/checkIn_button.png', height: 50),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
