import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ContactListsRequestsPage extends StatefulWidget {
  @override
  _ContactListsRequestsPageState createState() => _ContactListsRequestsPageState();
}

class _ContactListsRequestsPageState extends State<ContactListsRequestsPage> {
  final currentUser = FirebaseAuth.instance.currentUser;
  final DatabaseReference _requestsRef = FirebaseDatabase.instance.ref('contact_requests');
  final DatabaseReference _contactsRef = FirebaseDatabase.instance.ref('contacts');
  Map<String, dynamic> _requests = {};

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  // ✅ Loads only requests sent TO this user (receiver)
  void _loadRequests() async {
    if (currentUser == null) return;

    final snapshot = await _requestsRef.child(currentUser!.uid).get();
    if (snapshot.exists) {
      setState(() {
        _requests = Map<String, dynamic>.from(snapshot.value as Map);
      });
    } else {
      setState(() => _requests = {});
    }
  }

  // ✅ Accept request: add each other as contacts + delete the request
  Future<void> _acceptRequest(String senderUid, String senderUsername) async {
    final currentUserUid = currentUser!.uid;

    // Save contact for both users
    await _contactsRef.child(currentUserUid).child(senderUid).set({
      'name': senderUsername,
      'nickname': '',
      'timestamp': ServerValue.timestamp,
    });

    await _contactsRef.child(senderUid).child(currentUserUid).set({
      'name': currentUser!.displayName ?? 'You',
      'nickname': '',
      'timestamp': ServerValue.timestamp,
    });

    // Remove the request after acceptance
    await _requestsRef.child(currentUserUid).child(senderUid).remove();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact request accepted')),
    );

    _loadRequests();
  }

  // ✅ Decline request: simply remove it
  Future<void> _declineRequest(String senderUid) async {
    await _requestsRef.child(currentUser!.uid).child(senderUid).remove();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact request declined')),
    );
    _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: AppBar(
        backgroundColor: Colors.teal,
        title: const Text('Contact Requests'),
      ),
      body: _requests.isEmpty
          ? const Center(
        child: Text('No pending requests',
            style: TextStyle(color: Colors.white54, fontSize: 16)),
      )
          : ListView(
        children: _requests.entries.map((entry) {
          final senderUid = entry.key;
          final request = Map<String, dynamic>.from(entry.value);
          final senderUsername = request['senderUsername'] ?? 'Unknown';

          return Card(
            color: const Color(0xFF388E8E),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListTile(
              title: Text(senderUsername,
                  style: const TextStyle(color: Colors.white)),
              subtitle: const Text("wants to add you as a contact",
                  style: TextStyle(color: Colors.white70)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.greenAccent),
                    onPressed: () => _acceptRequest(senderUid, senderUsername),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.redAccent),
                    onPressed: () => _declineRequest(senderUid),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}