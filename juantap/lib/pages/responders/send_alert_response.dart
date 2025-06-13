import 'package:flutter/material.dart';
import 'location_of_the_user.dart';
import 'responder.dart'; // ✅ Import the ResponderDashboard

class SendAlertResponsePage extends StatelessWidget {
  final Map<String, String> data;

  const SendAlertResponsePage({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A9D8F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A9D8F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const ResponderDashboard()),
                  (route) => false,
            );
          },
        ),
        title: const Text('Responder', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.description_outlined, color: Colors.white),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Incident Report button clicked')),
              );
            },
          )
        ],
      ),
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(16),
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
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      data['image']!,
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['name']!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(data['location']!,
                            style: const TextStyle(color: Colors.white70)),
                        const Text("# 123456789",
                            style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  Image.asset(
                    'assets/shield.png',
                    height: 40,
                    errorBuilder: (_, __, ___) =>
                    const Icon(Icons.verified_user, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _infoRow("Birthdate", "June 17, 2002"),
              _infoRow("Nationality", "Filipino"),
              _infoRow("Email Address", "TAYO@gmail.com"),
              _infoRow("Current Address", "BLOCK 4 LOT 14, Buaya, LAPU-LAPU CITY, CEBU"),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _infoMini("Time in location", data['time']!),
                  _infoMini("Reason", data['reason']!),
                  _infoMini("Date", data['date']!),
                ],
              ),
              const SizedBox(height: 16),

              // ✅ Button navigates to LocationOfUserPage
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LocationOfUserPage()),
                  );
                },
                child: Container(
                  width: double.infinity,
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  child: const Text(
                    'Send Alert Response',
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

  Widget _infoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(color: Colors.white)),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        const Divider(color: Colors.white54),
      ],
    );
  }

  Widget _infoMini(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      ],
    );
  }
}