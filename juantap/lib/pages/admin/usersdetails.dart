import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class UserDetailsPage extends StatefulWidget {
  final String userId;
  const UserDetailsPage({super.key, required this.userId});

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage> {
  Map<dynamic, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
  }

  Future<void> _loadUserDetails() async {
    final snapshot = await FirebaseDatabase.instance.ref("users/${widget.userId}").get();
    if (snapshot.exists) {
      setState(() {
        userData = snapshot.value as Map<dynamic, dynamic>;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text('User Details', style: TextStyle(color: Colors.white)),
      ),
      body: userData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFB2F0E8), Color(0xFF7DDAC9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 40,
                    backgroundImage:
                    NetworkImage('https://i.imgur.com/8Km9tLL.jpg'),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(userData?['username'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 20)),
                      const SizedBox(height: 4),
                      const Text('Details'),
                      Text('📞 ${userData?['phone'] ?? ''}'),
                    ],
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Birthdate', style: TextStyle(fontWeight: FontWeight.bold)),
            const TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Not specified',
                enabledBorder: UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Nationality', style: TextStyle(fontWeight: FontWeight.bold)),
            const TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Not specified',
                enabledBorder: UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Email Address', style: TextStyle(fontWeight: FontWeight.bold)),
            TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: userData?['email'] ?? 'N/A',
                enabledBorder: const UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Current Address', style: TextStyle(fontWeight: FontWeight.bold)),
            const TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Not specified',
                enabledBorder: UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User approved!')),
                  );
                },
                child: const Text('Approve User'),
              ),
            )
          ],
        ),
      ),
    );
  }
}