import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'location_of_the_user.dart';
import 'responder.dart';

class SendAlertResponsePage extends StatefulWidget {
  final Map<String, dynamic> data;

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

  Future<void> _fetchUserInfo() async {
    try {
      // ✅ Get userId from responder alert
      final userId = widget.data['userId']?.toString().trim();

      if (userId == null || userId.isEmpty) {
        debugPrint("❌ No userId found in alert data: ${widget.data}");
        setState(() => isLoading = false);
        return;
      }

      // ✅ Fetch user details directly from Firebase
      final userSnapshot = await FirebaseDatabase.instance.ref('users/$userId').get();

      if (userSnapshot.exists) {
        final data = Map<String, dynamic>.from(userSnapshot.value as Map);
        setState(() {
          userInfo = data;
          isLoading = false;
        });
        debugPrint("✅ User data fetched successfully for $userId");
      } else {
        debugPrint("❌ No user found for userId: $userId");
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Error fetching user info: $e");
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
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _buildUserCard(context),
    );
  }

  Widget _buildUserCard(BuildContext context) {
    final data = widget.data;
    final user = userInfo ?? {};

    return Center(
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
            // 🧍 Profile Section
            Row(
              children: [
                CircleAvatar(
                  radius: 35,
                  backgroundColor: Colors.white,
                  backgroundImage: user['profileImage'] != null
                      ? NetworkImage(user['profileImage'])
                      : const AssetImage('assets/shield.png') as ImageProvider,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user['username'] ?? 'Unknown User',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user['address'] ?? 'No address available',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Text(
                        user['phone'] ?? '',
                        style: const TextStyle(color: Colors.white70),
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

            // ℹ️ User Info
            _infoRow("Birthdate", user['birthdate'] ?? 'N/A'),
            _infoRow("Nationality", user['nationality'] ?? 'N/A'),
            _infoRow("Email Address", user['email'] ?? 'N/A'),
            _infoRow("Phone Number", user['phone'] ?? 'N/A'),
            _infoRow("Current Address", user['address'] ?? 'N/A'),

            const SizedBox(height: 12),

            // ⏱️ Alert Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _infoMini("Time", data['time'] ?? 'N/A'),
                _infoMini("Reason", data['reason'] ?? 'SOS Alert'),
                _infoMini("Date", data['date'] ?? 'N/A'),
              ],
            ),

            const SizedBox(height: 16),

            // 🚀 Send Alert Response Button
            GestureDetector(
              onTap: () async {
                try {
                  final alertData = widget.data;

                  // ✅ Extract userId from the alert data
                  final userId = alertData['userId']?.toString().trim();

                  if (userId == null || userId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("⚠️ Unable to find user ID for this alert.")),
                    );
                    return;
                  }

                  // ✅ Save responder acknowledgment (optional: mark as viewed/responded)
                  final responder = FirebaseAuth.instance.currentUser;
                  if (responder != null) {
                    await FirebaseDatabase.instance
                        .ref("responder_alerts/${alertData['alertId']}/responders/${responder.uid}")
                        .set({
                      'respondedAt': DateTime.now().toIso8601String(),
                      'responderName': responder.email ?? 'Responder',
                    });
                  }

                  // ✅ Navigate and send userId + alertId to LocationOfUserPage
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LocationOfUserPage(
                        alertId: alertData['alertId'] ?? "",
                        userId: userId, // 🔥 Add this to your LocationOfUserPage constructor
                      ),
                    ),
                  );
                } catch (e) {
                  debugPrint("❌ Error sending alert response: $e");
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Error: $e")),
                  );
                }
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
        Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12)),
      ],
    );
  }
}
