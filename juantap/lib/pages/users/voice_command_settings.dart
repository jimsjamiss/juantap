import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juantap/pages/users/sos_service.dart';

class VoiceCommandSettings extends StatefulWidget {
  const VoiceCommandSettings({super.key});

  @override
  State<VoiceCommandSettings> createState() => _VoiceCommandSettingsState();
}

class _VoiceCommandSettingsState extends State<VoiceCommandSettings> {
  bool _isVoiceCommandEnabled = false;
  bool _silentMode = false; // Silent SOS mode
  String _keyword = "help"; // default keyword
  late stt.SpeechToText _speech;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadKeyword();
  }

  /// Load keyword & silent mode
  Future<void> _loadKeyword() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _keyword = prefs.getString("voice_keyword") ?? "help";
      _silentMode = prefs.getBool("silent_mode") ?? false;
    });
  }

  /// Save keyword
  Future<void> _saveKeyword(String newKeyword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("voice_keyword", newKeyword);
    setState(() {
      _keyword = newKeyword;
    });
  }

  /// Save silent mode
  Future<void> _saveSilentMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("silent_mode", value);
    setState(() {
      _silentMode = value;
    });
  }

  /// Toggle voice command
  Future<void> _toggleVoiceCommand(bool value) async {
    setState(() {
      _isVoiceCommandEnabled = value;
    });

    final service = FlutterBackgroundService();

    if (_isVoiceCommandEnabled) {
      try {
        bool available = await _speech.initialize(
          onError: (err) => print("⚠️ Speech error: $err"),
          onStatus: (status) => print("ℹ️ Speech status: $status"),
        );
        if (available) {
          // service.startService(); // ❌ disable background for now (avoid crash)
          _startListening();
        } else {
          print("⚠️ Speech recognition not available (permission denied?)");
          setState(() => _isVoiceCommandEnabled = false);
        }
      } catch (e) {
        print("⚠️ Exception initializing speech: $e");
        setState(() => _isVoiceCommandEnabled = false);
      }
    } else {
      try {
        await _speech.stop();
      } catch (_) {}
      service.invoke("stopService");
    }
  }

  /// Start listening for keyword
  void _startListening() {
    try {
      _speech.listen(
        onResult: (result) {
          String spoken = result.recognizedWords.toLowerCase();
          print("🎤 Heard: $spoken");

          if (spoken.contains(_keyword.toLowerCase())) {
            _triggerSOS();
          }
        },
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
      );
    } catch (e) {
      print("⚠️ Error starting listening: $e");
    }
  }

  /// SOS Trigger
  Future<void> _triggerSOS() async {
    await SOSService.sendSosAlert();

    if (!_silentMode && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🚨 SOS sent successfully by voice ($_keyword)'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }

    print("🚨 SOS TRIGGERED by keyword: $_keyword (silentMode=$_silentMode)");

    // 👉 Navigate to HomePage after SOS is triggered
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/home', // Make sure this route is registered in your MaterialApp routes
            (route) => false, // Clear backstack so it goes directly to home
      );
    }
  }

  /// Record keyword
  void _showChangeKeywordDialog() {
    showDialog(
      context: context,
      builder: (context) {
        bool isRecording = false;
        String detectedWord = "";
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Set Voice Keyword"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(detectedWord.isEmpty
                      ? "Press record and say your keyword"
                      : "Detected: $detectedWord"),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () async {
                      if (!isRecording) {
                        try {
                          bool available = await _speech.initialize();
                          if (available) {
                            setState(() => isRecording = true);
                            _speech.listen(onResult: (result) {
                              setState(() {
                                detectedWord =
                                    result.recognizedWords.toLowerCase();
                              });
                            });
                          }
                        } catch (e) {
                          print("⚠️ Error recording keyword: $e");
                        }
                      } else {
                        await _speech.stop();
                        setState(() => isRecording = false);
                      }
                    },
                    child: Text(
                        isRecording ? "Stop Recording" : "Record Keyword"),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (detectedWord.isNotEmpty) {
                      _saveKeyword(detectedWord);
                    }
                    Navigator.pop(context);
                  },
                  child: const Text("Save"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Voice Command Settings")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text("Enable Voice Command"),
              value: _isVoiceCommandEnabled,
              onChanged: _toggleVoiceCommand,
            ),
            SwitchListTile(
              title: const Text("Silent SOS Mode"),
              subtitle: const Text(
                  "Hide on-screen confirmation when SOS is triggered"),
              value: _silentMode,
              onChanged: _saveSilentMode,
            ),
            const SizedBox(height: 20),
            Text("Current Keyword: $_keyword",
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            ElevatedButton(
              onPressed: _showChangeKeywordDialog,
              child: const Text("Change Keyword"),
            ),
            const SizedBox(height: 20),
            Text(
              _isVoiceCommandEnabled ? "Listening..." : "Not listening",
              style: TextStyle(
                color: _isVoiceCommandEnabled ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            )
          ],
        ),
      ),
    );
  }
}