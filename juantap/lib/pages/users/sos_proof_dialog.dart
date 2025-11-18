import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class SosProofDialog extends StatefulWidget {
  const SosProofDialog({super.key});

  @override
  State<SosProofDialog> createState() => _SosProofDialogState();
}

class _SosProofDialogState extends State<SosProofDialog> {
  File? _mediaFile;
  bool _isVideo = false;
  bool _uploading = false;

  String? _crimeType;

  final List<String> crimeOptions = [
    "Assault",
    "Kidnapping",
    "Robbery / Theft",
    "Harassment",
    "Domestic Violence",
    "Stalking",
    "Suspicious Person",
    "Other Emergency"
  ];

  final ImagePicker _picker = ImagePicker();

  // -------------------------------
  // Cloudinary Upload
  // -------------------------------
  Future<String?> uploadToCloudinary(File file, bool isVideo) async {
    const cloudName = "dfop0muxq";
    const uploadPreset = "juantap_images";

    final url = Uri.parse(
      "https://api.cloudinary.com/v1_1/$cloudName/${isVideo ? 'video' : 'image'}/upload",
    );

    final req = http.MultipartRequest("POST", url)
      ..fields["upload_preset"] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath("file", file.path));

    final res = await req.send();
    final body = await res.stream.bytesToString();
    final data = jsonDecode(body);

    return data["secure_url"];
  }

  // -------------------------------
  // Pick image or video
  // -------------------------------
  Future<void> pickMedia(bool isVideo) async {
    final XFile? picked = isVideo
        ? await _picker.pickVideo(source: ImageSource.camera)
        : await _picker.pickImage(source: ImageSource.camera);

    if (picked != null) {
      setState(() {
        _mediaFile = File(picked.path);
        _isVideo = isVideo;
      });
    }
  }

  // -------------------------------
  // Submit
  // -------------------------------
  Future<void> submit() async {
    if (_crimeType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select crime type")),
      );
      return;
    }

    if (_mediaFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Capture photo or video")),
      );
      return;
    }

    setState(() => _uploading = true);
    final url = await uploadToCloudinary(_mediaFile!, _isVideo);
    setState(() => _uploading = false);

    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Upload failed")),
      );
      return;
    }

    Navigator.pop(context, {
      "proofUrl": url,
      "isVideo": _isVideo,
      "crimeType": _crimeType,
    });
  }

  // -------------------------------
  // UI
  // -------------------------------
  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: _uploading
          ? const SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(color: Colors.redAccent),
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,   // 🔥 IMPORTANT FIX
          children: [
            const Text(
              "SOS Proof",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            DropdownButtonFormField<String>(
              value: _crimeType,
              decoration: const InputDecoration(
                labelText: "Crime Type",
                border: OutlineInputBorder(),
              ),
              items: crimeOptions
                  .map((c) => DropdownMenuItem(
                value: c,
                child: Text(c),
              ))
                  .toList(),
              onChanged: (v) => setState(() => _crimeType = v),
            ),

            const SizedBox(height: 15),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => pickMedia(false),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text("Photo"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => pickMedia(true),
                  icon: const Icon(Icons.videocam),
                  label: const Text("Video"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (_mediaFile != null)
              Container(
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _isVideo
                    ? const Center(
                  child: Icon(Icons.videocam,
                      size: 50, color: Colors.deepPurple),
                )
                    : ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    _mediaFile!,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                child: const Text(
                  "Send SOS With Proof",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}