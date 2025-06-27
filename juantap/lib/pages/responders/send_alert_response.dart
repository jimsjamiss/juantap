import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'location_of_the_user.dart';
import 'responder.dart';

class SendAlertResponsePage extends StatefulWidget {
  final Map<String, String> data;

  const SendAlertResponsePage({super.key, required this.data});

  @override
  State<SendAlertResponsePage> createState() => _SendAlertResponsePageState();
}

class _SendAlertResponsePageState extends State<SendAlertResponsePage> {
  Map<String, dynamic>? userInfo;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUserInfo();
  }

  void _fetchUserInfo() async {
    final userId = widget.data['userId'];
    if (userId == null || userId.isEmpty) {
      debugPrint("❌ No userId provided in widget.data: ${widget.data}");
      setState(() => isLoading = false);
      return;
    }

    try {
      final snapshot = await FirebaseDatabase.instance.ref('users/$userId').get();
      if (snapshot.exists) {
        debugPrint("✅ User data found for userId: $userId");
        setState(() {
          userInfo = Map<String, dynamic>.from(snapshot.value as Map);
          isLoading = false;
        });
      } else {
        debugPrint("❌ No data found for userId: $userId");
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Error fetching user data: $e");
      setState(() => isLoading = false);
    }
  }

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
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Center(
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
                      widget.data['image'] ?? 'https://via.placeholder.com/70',
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                      const Icon(Icons.error, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.data['name'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.data['location'] ?? '',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const Text(
                          "# 123456789",
                          style: TextStyle(color: Colors.white70),
                        ),
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
              _infoRow("Birthdate", userInfo != null ? (userInfo!['birthdate'] ?? 'N/A') : 'N/A'),
              _infoRow("Nationality", userInfo != null ? (userInfo!['nationality'] ?? 'Filipino') : 'Filipino'),
              _infoRow("Email Address", userInfo != null ? (userInfo!['email'] ?? 'N/A') : 'N/A'),
              _infoRow("Phone Number", userInfo != null ? (userInfo!['phone'] ?? 'N/A') : 'N/A'),
              _infoRow("Current Address", userInfo != null ? (userInfo!['address'] ?? 'BLOCK 4 LOT 14, Buaya, LAPU-LAPU CITY, CEBU') : 'BLOCK 4 LOT 14, Buaya, LAPU-LAPU CITY, CEBU'),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _infoMini("Time", widget.data['time'] ?? ''),
                  _infoMini("Reason", widget.data['reason'] ?? ''),
                  _infoMini("Date", widget.data['date'] ?? ''),
                ],
              ),
              const SizedBox(height: 16),
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