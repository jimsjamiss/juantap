import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class EditResponderProfilePage extends StatefulWidget {
  const EditResponderProfilePage({super.key});

  @override
  State<EditResponderProfilePage> createState() => _EditResponderProfilePageState();
}

class _EditResponderProfilePageState extends State<EditResponderProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();

  final _user = FirebaseAuth.instance.currentUser;
  File? _selectedImage;
  String? _profileImageUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadResponderData();
  }

  Future<void> _loadResponderData() async {
    if (_user != null) {
      final ref = FirebaseDatabase.instance.ref('users/${_user!.uid}');
      final snapshot = await ref.get();
      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);
        _nameController.text = data['username'] ?? '';
        _phoneController.text = data['phone'] ?? '';
        _emailController.text = data['email'] ?? '';
        _addressController.text = data['address'] ?? '';
        _profileImageUrl = data['profileImage'];
        setState(() {});
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Future<String?> _uploadImageToCloudinary(File image) async {
    const cloudName = 'dfop0muxq';
    const uploadPreset = 'juantap_images';

    final url = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");

    final request = http.MultipartRequest('POST', url)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(await http.MultipartFile.fromPath('file', image.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseBody = await response.stream.bytesToString();
      final responseData = json.decode(responseBody);
      return responseData['secure_url'];
    } else {
      print("Cloudinary upload failed: ${response.statusCode}");
      return null;
    }
  }

  Future<void> _saveChanges() async {
    if (_formKey.currentState!.validate() && _user != null) {
      setState(() => _isSaving = true);

      try {
        String? imageUrl = _profileImageUrl;
        if (_selectedImage != null) {
          imageUrl = await _uploadImageToCloudinary(_selectedImage!);
          setState(() {
            _profileImageUrl = imageUrl;
          });
        }

        final ref = FirebaseDatabase.instance.ref('users/${_user!.uid}');
        await ref.update({
          'username': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'address': _addressController.text.trim(),
          'profileImage': imageUrl,
          'role': 'responder',
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
        Navigator.pushReplacementNamed(context, '/responder_dashboard');
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      } finally {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF417B63),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pushReplacementNamed(context, '/responder_dashboard'),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Edit Profile',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.white,
                      backgroundImage: _selectedImage != null
                          ? FileImage(_selectedImage!)
                          : (_profileImageUrl != null
                          ? NetworkImage(_profileImageUrl!)
                          : const AssetImage('assets/shield.png')) as ImageProvider,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _pickImage,
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.add, color: Color(0xFF417B63)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Responder Information',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 12),
                _buildInputField(_nameController, 'Name'),
                _buildInputField(_phoneController, 'Phone Number', keyboardType: TextInputType.phone),
                _buildInputField(_emailController, 'Email'),
                _buildInputField(_addressController, 'Address'),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving
                        ? null
                        : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => AlertDialog(
                          title: const Text('Confirm Changes'),
                          content: const Text('Save your updated responder profile?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF417B63),
                              ),
                              child: const Text('Yes', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        _saveChanges();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF7F6D9),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller, String label,
      {bool readOnly = false, TextInputType keyboardType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        validator: (value) => value == null || value.isEmpty ? 'Enter $label' : null,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white,
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}