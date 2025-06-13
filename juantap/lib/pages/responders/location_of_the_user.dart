import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LocationOfUserPage extends StatefulWidget {
  const LocationOfUserPage({super.key});

  @override
  State<LocationOfUserPage> createState() => _LocationOfUserPageState();
}

class _LocationOfUserPageState extends State<LocationOfUserPage> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();

  void _showIncidentReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/shield.png', height: 80,
                  errorBuilder: (_, __, ___) => const Icon(Icons.security, size: 60),
                ),
                const SizedBox(height: 12),
                const Text('Incident Report',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildTextField('Incident Description', 'Enter a brief description', _descriptionController),
                const SizedBox(height: 12),
                _buildTextField('Date', 'MM/DD/YYYY', _dateController),
                const SizedBox(height: 12),
                _buildTextField('Time', 'HH:MM AM/PM', _timeController),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF28A361),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: _submitIncidentReport,
                    child: const Text('Submit Incident Report'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submitIncidentReport() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final reportRef = FirebaseDatabase.instance
        .ref('responder_reports/${user.uid}')
        .push();

    await reportRef.set({
      'description': _descriptionController.text.trim(),
      'date': _dateController.text.trim(),
      'time': _timeController.text.trim(),
      'location': 'Brgy. Opao, Zone 3',
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report submitted successfully!')),
    );
  }

  static Widget _buildTextField(String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF2F2F2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text('Responder', style: TextStyle(color: Colors.white)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Location of the user',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF25C09C), Color(0xFFFF0000)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          'https://i.imgur.com/8Km9tLL.jpg',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Juan Dela Cruz',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            Text('Brgy. Opao, Umapad',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      Image.asset(
                        'assets/badge.png', height: 40,
                        errorBuilder: (_, __, ___) => const Icon(Icons.verified, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(child: Text('Map demo here')),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Use the guided route to quickly rescue the user.',
                      style: TextStyle(fontSize: 13, color: Colors.black),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Is the Incident resolved?',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: () => _showIncidentReportDialog(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF28A361),
                        ),
                        child: const Text('Yes'),
                      ),
                      ElevatedButton(
                        onPressed: () => _showIncidentReportDialog(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                        ),
                        child: const Text('No'),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}