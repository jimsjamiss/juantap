import 'package:flutter/material.dart';

class UserDetailsPage extends StatelessWidget {
  const UserDetailsPage({super.key});

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
      body: Padding(
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
                    backgroundImage: NetworkImage('https://i.imgur.com/8Km9tLL.jpg'),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Keanu Hehe',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                      SizedBox(height: 4),
                      Text('Details'),
                      Text('📞 123456789'),
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
                hintText: 'June 17, 2002',
                enabledBorder: UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Nationality', style: TextStyle(fontWeight: FontWeight.bold)),
            const TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Filipino',
                enabledBorder: UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Email Address', style: TextStyle(fontWeight: FontWeight.bold)),
            const TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'TAYO@gmail.com',
                enabledBorder: UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Current Address', style: TextStyle(fontWeight: FontWeight.bold)),
            const TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'BLOCK 4 LOT 14, Buaya, LAPU-LAPU CITY, CEBU',
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