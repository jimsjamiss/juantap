import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:juantap/pages/users/sos_service.dart';

class VoiceCommandSettings extends StatefulWidget {
  const VoiceCommandSettings({super.key});

  @override
  State<VoiceCommandSettings> createState() => _VoiceCommandSettingsState();
}

class _VoiceCommandSettingsState extends State<VoiceCommandSettings> {
  bool _isVoiceCommandEnabled = false;
  bool _silentMode = false;
  String _keyword = "help";
  late stt.SpeechToText _speech;
  bool _initializing = true;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _keyword = prefs.getString("voice_keyword") ?? "help";
    _silentMode = prefs.getBool("silent_mode") ?? false;
    _isVoiceCommandEnabled = prefs.getBool("voice_command_enabled") ?? false;
    setState(() {});
    if (_isVoiceCommandEnabled) {
      await _enableVoiceListening();
    }
    _initializing = false;
    setState(() {});
  }

  Future<void> _saveVoiceCommandEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("voice_command_enabled", value);
  }

  Future<bool> _checkAndRequestMicPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    if (result.isGranted) return true;

    if (result.isPermanentlyDenied) {
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Microphone Permission Required"),
          content: const Text(
              "Please allow microphone access in your app settings to enable voice commands."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel")),
            ElevatedButton(
                onPressed: () {
                  openAppSettings();
                  Navigator.pop(context);
                },
                child: const Text("Open Settings")),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("🎤 Microphone permission denied."),
        backgroundColor: Colors.redAccent,
      ));
    }
    return false;
  }

  /// Called when the user toggles ON
  Future<void> _enableVoiceListening() async {
    final hasPermission = await _checkAndRequestMicPermission();
    if (!hasPermission) {
      setState(() => _isVoiceCommandEnabled = false);
      await _saveVoiceCommandEnabled(false);
      return;
    }

    bool available = false;
    try {
      available = await _speech.initialize(
        onError: (err) => print("⚠️ Speech error: $err"),
        onStatus: (status) {
          print("ℹ️ Speech status: $status");
          if (status == "notListening" && _isVoiceCommandEnabled) {
            // Auto-relisten if active
            Future.delayed(const Duration(seconds: 1), () {
              if (!_isListening && _isVoiceCommandEnabled) _startListening();
            });
          }
        },
      );
    } catch (e) {
      print("⚠️ Speech init exception: $e");
    }

    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("⚠️ Voice recognition not available."),
        backgroundColor: Colors.redAccent,
      ));
      setState(() => _isVoiceCommandEnabled = false);
      await _saveVoiceCommandEnabled(false);
      return;
    }

    setState(() {
      _isVoiceCommandEnabled = true;
    });
    await _saveVoiceCommandEnabled(true);
    _startListening();
  }

  void _startListening() {
    try {
      _isListening = true;

      // ✅ Start the listening session
      _speech.listen(
        listenMode: stt.ListenMode.dictation, // Option B: free-form mode
        pauseFor: const Duration(seconds: 10),
        listenFor: const Duration(minutes: 5),
        partialResults: true,
        onResult: (result) {
          final spoken = result.recognizedWords.toLowerCase();
          print("🎤 Heard: $spoken");

          if (spoken.contains(_keyword.toLowerCase())) {
            _triggerSOS();
          }
        },
      );

      // ✅ Add a watchdog to auto-restart if listening stops unexpectedly
      _speech.statusListener = (status) {
        print("ℹ️ Speech status: $status");
        if (status == "notListening" && _isVoiceCommandEnabled) {
          Future.delayed(const Duration(seconds: 1), () {
            if (_isVoiceCommandEnabled) _startListening();
          });
        }
      };

      _speech.errorListener = (error) {
        print("❌ Speech error: ${error.errorMsg}");
        if (error.errorMsg == "error_no_match" ||
            error.errorMsg == "error_speech_timeout") {
          Future.delayed(const Duration(seconds: 1), () {
            if (_isVoiceCommandEnabled) _startListening();
          });
        }
      };
    } catch (e) {
      print("⚠️ Start listen error: $e");
    }
  }

  Future<void> _disableVoiceListening() async {
    final service = FlutterBackgroundService();
    try {
      await _speech.stop();
    } catch (_) {}
    service.invoke("stopService");
    _isListening = false;
    setState(() => _isVoiceCommandEnabled = false);
    await _saveVoiceCommandEnabled(false);
  }

  Future<void> _triggerSOS() async {
    await SOSService.sendSosAlert();
    if (!_silentMode && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('🚨 SOS sent successfully by voice ($_keyword)'),
        backgroundColor: Colors.redAccent,
      ));
    }
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    }
  }

  Future<void> _saveSilentMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("silent_mode", value);
    setState(() => _silentMode = value);
  }

  Future<void> _saveKeyword(String newKeyword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("voice_keyword", newKeyword);
    setState(() => _keyword = newKeyword);
  }

  void _showChangeKeywordDialog() {
    showDialog(
      context: context,
      builder: (context) {
        bool isRecording = false;
        String detectedWord = "";
        return StatefulBuilder(builder: (context, setState) {
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
                      bool available = await _speech.initialize();
                      if (available) {
                        setState(() => isRecording = true);
                        _speech.listen(onResult: (result) {
                          setState(() {
                            detectedWord = result.recognizedWords.toLowerCase();
                          });
                        });
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
                  child: const Text("Cancel")),
              ElevatedButton(
                  onPressed: () {
                    if (detectedWord.isNotEmpty) _saveKeyword(detectedWord);
                    Navigator.pop(context);
                  },
                  child: const Text("Save")),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
              onChanged: (val) async {
                if (val) {
                  await _enableVoiceListening();
                } else {
                  await _disableVoiceListening();
                }
                setState(() {});
              },
            ),
            SwitchListTile(
              title: const Text("Silent SOS Mode"),
              subtitle: const Text(
                  "Hide on-screen confirmation when SOS is triggered"),
              value: _silentMode,
              onChanged: _saveSilentMode,
            ),
            const SizedBox(height: 20),
            Text(
              "Current Keyword: $_keyword",
              style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: _showChangeKeywordDialog,
              child: const Text("Change Keyword"),
            ),
            const SizedBox(height: 20),
            Text(
              _isVoiceCommandEnabled
                  ? (_isListening ? "🎙️ Listening..." : "🔄 Initializing...")
                  : "❌ Not listening",
              style: TextStyle(
                color: _isVoiceCommandEnabled ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
