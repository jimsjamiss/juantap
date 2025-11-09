import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

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

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadSettings();
  }

  /// ✅ Load saved preferences (voice command toggle, silent mode, and keyword)
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _keyword = prefs.getString("voice_keyword") ?? "help";
    _silentMode = prefs.getBool("silent_mode") ?? false;
    _isVoiceCommandEnabled = prefs.getBool("voice_command_enabled") ?? false;
    setState(() => _initializing = false);
  }

  /// ✅ Save the voice command enabled toggle
  Future<void> _saveVoiceCommandEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("voice_command_enabled", value);
    setState(() => _isVoiceCommandEnabled = value);
  }

  /// ✅ Save silent mode preference
  Future<void> _saveSilentMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("silent_mode", value);
    setState(() => _silentMode = value);
  }

  /// ✅ Save voice keyword
  Future<void> _saveKeyword(String newKeyword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("voice_keyword", newKeyword);
    setState(() => _keyword = newKeyword);
  }

  /// ✅ Ask for microphone permission before recording new keyword
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
              "Please allow microphone access in your app settings to record your keyword."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(context);
              },
              child: const Text("Open Settings"),
            ),
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

  /// ✅ Dialog for recording a new keyword
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
                Text(
                  detectedWord.isEmpty
                      ? "Press record and say your keyword"
                      : "Detected: $detectedWord",
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () async {
                    if (!isRecording) {
                      final hasPermission = await _checkAndRequestMicPermission();
                      if (!hasPermission) return;

                      bool available = await _speech.initialize();
                      if (available) {
                        setState(() => isRecording = true);
                        _speech.listen(onResult: (result) {
                          setState(() {
                            detectedWord = result.recognizedWords.toLowerCase();
                          });
                        });
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text("Speech recognition unavailable."),
                          backgroundColor: Colors.redAccent,
                        ));
                      }
                    } else {
                      await _speech.stop();
                      setState(() => isRecording = false);
                    }
                  },
                  child: Text(isRecording ? "Stop Recording" : "Record Keyword"),
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
                  if (detectedWord.isNotEmpty) _saveKeyword(detectedWord);
                  Navigator.pop(context);
                },
                child: const Text("Save"),
              ),
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
      appBar: AppBar(
        title: const Text("Voice Command Settings"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text("Enable Voice Command"),
              subtitle: const Text(
                  "Allow SOS to be triggered by saying your keyword (e.g., 'help')."),
              value: _isVoiceCommandEnabled,
              onChanged: (val) async {
                if (val) {
                  final micPermission = await _checkAndRequestMicPermission();
                  if (!micPermission) return;
                }
                await _saveVoiceCommandEnabled(val);
              },
            ),
            SwitchListTile(
              title: const Text("Silent SOS Mode"),
              subtitle: const Text(
                  "Hide confirmation popup when voice SOS is triggered."),
              value: _silentMode,
              onChanged: _saveSilentMode,
            ),
            const SizedBox(height: 20),
            Text(
              "Current Keyword: $_keyword",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _showChangeKeywordDialog,
              child: const Text("Change Keyword"),
            ),
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              "Voice command runs automatically on your Home page "
                  "when enabled. You don’t need to keep this screen open.",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
