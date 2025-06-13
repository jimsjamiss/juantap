import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'send_alert_response.dart';
import 'incident_reports.dart';
import 'package:juantap/pages/users/login.dart';


class ResponderDashboard extends StatelessWidget {
  const ResponderDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emergency Notifications',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Responder'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  File? _profileImage;
  final _nameController = TextEditingController();
  final user = FirebaseAuth.instance.currentUser;
  String _username = '';

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _profileImage = File(picked.path);
      });
    }
  }

  Future<void> _updateName() async {
    if (user != null) {
      final newName = _nameController.text.trim();
      if (newName.isNotEmpty) {
        await FirebaseDatabase.instance.ref("users/${user!.uid}/username").set(newName);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name updated successfully')));
        setState(() {
          _username = newName;
        });
        Navigator.pop(context);
      }
    }
  }

  void _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }


  void _showEditNameDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: _nameController,
          decoration: const InputDecoration(hintText: 'Enter new name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: _updateName, child: const Text('Save')),
        ],
      ),
    );
  }

  void _fetchUsername() async {
    if (user != null) {
      final snapshot = await FirebaseDatabase.instance.ref("users/${user!.uid}/username").get();
      if (snapshot.exists) {
        setState(() {
          _username = snapshot.value.toString();
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUsername();
  }

  void _showNotificationDialog(BuildContext context, Map<String, String> item) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF25C09C), Color(0xFFFF0000)],
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  item['image']!,
                  width: 90,
                  height: 90,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                item['name']!,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(item['location']!, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Time in location\n${item['time']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Text("Reason\n${item['reason']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                  Text("Date\n${item['date']}", style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SendAlertResponsePage(data: item),
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF25C09C), Color(0xFFFF0000)],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  child: const Text(
                    'Accept Alert',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> notifications = [
      {
        'name': 'Juan Dela Cruz',
        'location': 'Brgy. Opao, Umapad',
        'time': '12:04 am',
        'reason': 'no response',
        'date': '02/14/2025',
        'image': 'https://i.imgur.com/8Km9tLL.jpg'
      },
      {
        'name': 'Kai Sotto',
        'location': 'Brgy. Opao, Looc',
        'time': '01:00 am',
        'reason': 'SOS Alert',
        'date': '02/13/2025',
        'image': 'https://i.imgur.com/QCNbOAo.png'
      },
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _pickImage,
              child: CircleAvatar(
                radius: 50,
                backgroundImage: _profileImage != null
                    ? FileImage(_profileImage!)
                    : const AssetImage('assets/shield.png') as ImageProvider,
              ),
            ),
            const SizedBox(height: 10),
            Text(_username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ElevatedButton(onPressed: _showEditNameDialog, child: const Text("Edit Name")),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _logout, child: const Text("Logout")),
          ],
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Text(
                  'Emergency Notifications',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final item = notifications[index];
                      return GestureDetector(
                        onTap: () => _showNotificationDialog(context, item),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF25C09C), Color(0xFFFF0000)],
                              begin: Alignment.bottomLeft,
                              end: Alignment.topRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    item['image']!,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['name']!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(item['location']!, style: const TextStyle(color: Colors.white)),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("Time\n${item['time']}",
                                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                                          Text("Reason\n${item['reason']}",
                                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                                          Text("Date\n${item['date']}",
                                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const IncidentReportsPage()),
                );
              },
              child: const Icon(Icons.description_outlined, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}