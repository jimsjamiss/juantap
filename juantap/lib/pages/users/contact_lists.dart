import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ContactListPage extends StatefulWidget {
  @override
  _ContactListPageState createState() => _ContactListPageState();
}

class _ContactListPageState extends State<ContactListPage> {
  final TextEditingController _searchController = TextEditingController();
  final DatabaseReference _contactsRef = FirebaseDatabase.instance.ref('contacts');
  final DatabaseReference _requestsRef = FirebaseDatabase.instance.ref('contact_requests');
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic> _requests = {};
  bool _isRequestTab = false;

  StreamSubscription<DatabaseEvent>? _contactListener;

  @override
  void initState() {
    super.initState();
    _startContactListener();

  }

  void _startContactListener() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _contactListener = _contactsRef.child(uid).onValue.listen((event) async {
      if (!mounted) return;
      final data = event.snapshot.value;
      final List<Map<String, dynamic>> tempResults = [];

      if (data != null) {
        final contactMap = Map<String, dynamic>.from(data as Map);

        for (final key in contactMap.keys) {
          final userSnapshot = await FirebaseDatabase.instance.ref('users/$key').get();

          if (userSnapshot.exists) {
            final userData = Map<String, dynamic>.from(userSnapshot.value as Map);

            tempResults.add({
              'key': key,
              'name': userData['username'] ?? 'Unknown',
              'phone': userData['phone'] ?? '',
              'nickname': contactMap[key]['nickname'] ?? '',
              'profileImage': userData['profileImage'] ?? '',
            });
          }
        }
      }

      setState(() => _searchResults = tempResults);
    });
  }


  void _loadRequests() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await _requestsRef.child(uid).get();

    if (snapshot.exists) {
      setState(() {
        _requests = Map<String, dynamic>.from(snapshot.value as Map);
      });
    } else {
      setState(() => _requests = {});
    }
  }

  Future<void> _acceptRequest(String senderUid, String senderUsername) async {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final uid = currentUser.uid;

    final usersRef = FirebaseDatabase.instance.ref('users');
    final senderSnapshot = await usersRef.child(senderUid).get();
    final senderProfileImage = senderSnapshot.child('profileImage').value?.toString() ?? '';
    final senderPhone = senderSnapshot.child('phone').value?.toString() ?? '';

    final receiverSnapshot = await usersRef.child(uid).get();
    final receiverUsername = receiverSnapshot.child('username').value?.toString() ?? currentUser.displayName ?? 'You';
    final receiverProfileImage = receiverSnapshot.child('profileImage').value?.toString() ?? '';
    final receiverPhone = receiverSnapshot.child('phone').value?.toString() ?? '';

    await _contactsRef.child(uid).child(senderUid).set({
      'nickname': '',
      'name': senderUsername,
      'phone': senderPhone,
      'profileImage': senderProfileImage,
    });

    await _contactsRef.child(senderUid).child(uid).set({
      'nickname': '',
      'name': receiverUsername,
      'phone': receiverPhone,
      'profileImage': receiverProfileImage,
    });

    await _requestsRef.child(uid).child(senderUid).remove();
    _loadRequests();
  }

  Future<void> _declineRequest(String senderUid) async {
    await _requestsRef.child(FirebaseAuth.instance.currentUser!.uid).child(senderUid).remove();
    _loadRequests();
  }

  @override
  void dispose() {
    _contactListener?.cancel();
    _searchController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final filteredResults = _searchResults.where((contact) {
      final query = _searchController.text.toLowerCase();
      final name = contact['name']?.toLowerCase() ?? '';
      final phone = contact['phone'] ?? '';
      return name.contains(query) || phone.contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: Colors.black87,
      floatingActionButton: !_isRequestTab
          ? FloatingActionButton(
        backgroundColor: Colors.teal,
        child: Icon(Icons.person_add),
        onPressed: () => _showAddContactModal(context),
      )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Color(0xFF26A69A),
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.arrow_back, color: Colors.black),
                      ),
                      SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          setState(() => _isRequestTab = false);
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: !_isRequestTab ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Contacts', style: TextStyle(color: !_isRequestTab ? Colors.black : Colors.white)),
                        ),
                      ),
                      SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() => _isRequestTab = true);
                          _loadRequests();
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: _isRequestTab ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Request', style: TextStyle(color: _isRequestTab ? Colors.black : Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isRequestTab
                  ? _requests.isEmpty
                  ? Center(child: Text('No pending requests', style: TextStyle(color: Colors.white54)))
                  : ListView(
                children: _requests.entries.map((entry) {
                  final senderUid = entry.key;
                  final request = Map<String, dynamic>.from(entry.value);
                  final senderUsername = request['senderUsername'];

                  return ListTile(
                    title: Text(senderUsername, style: TextStyle(color: Colors.white)),
                    subtitle: Text('wants to add you as a contact'),
                    tileColor: Color(0xFF388E8E),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.check, color: Colors.greenAccent),
                          onPressed: () => _acceptRequest(senderUid, senderUsername),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.redAccent),
                          onPressed: () => _declineRequest(senderUid),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              )
                  : filteredResults.isEmpty
                  ? Center(child: Text('No contacts found.', style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                itemCount: filteredResults.length,
                itemBuilder: (context, index) {
                  final contact = filteredResults[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: contact['profileImage'] != null && contact['profileImage'].toString().isNotEmpty
                          ? NetworkImage(contact['profileImage'])
                          : AssetImage('assets/images/user_profile.png') as ImageProvider,
                    ),
                    title: Text(contact['nickname'], style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'Full Name: ${contact['name'] ?? 'None'}\n${contact['phone']}',
                      style: TextStyle(color: Colors.white70),
                    ),
                    tileColor: Color(0xFF388E8E),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.yellow),
                          onPressed: () => _editNickname(contact['key'], contact['nickname']),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _deleteContact(contact['key']),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _editNickname(String key, String currentNickname) async {
    TextEditingController _nicknameController = TextEditingController(text: currentNickname);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Nickname'),
        content: TextField(
          controller: _nicknameController,
          decoration: InputDecoration(hintText: 'Enter nickname'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await _contactsRef.child(FirebaseAuth.instance.currentUser!.uid).child(key).update({
                'nickname': _nicknameController.text,
              });
              Navigator.pop(context);
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteContact(String key) async {
    await _contactsRef.child(FirebaseAuth.instance.currentUser!.uid).child(key).remove();
  }

  void _showAddContactModal(BuildContext context) {
    final usernameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Invite Contact'),
        content: TextField(
          controller: usernameController,
          decoration: InputDecoration(labelText: 'Enter Username'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            child: Text('Send Request'),
            onPressed: () async {
              final receiverUsername = usernameController.text.trim();
              if (receiverUsername.isEmpty) return;

              final currentUser = FirebaseAuth.instance.currentUser;
              final senderUid = currentUser!.uid;

              final usersRef = FirebaseDatabase.instance.ref('users');
              final contactRequestsRef = FirebaseDatabase.instance.ref('contact_requests');

              final usersSnapshot = await usersRef.get();
              String? receiverUid;
              String? senderUsername;

              if (usersSnapshot.exists) {
                final users = Map<String, dynamic>.from(usersSnapshot.value as Map);

                users.forEach((uid, data) {
                  final user = Map<String, dynamic>.from(data);
                  if (uid == senderUid) {
                    senderUsername = user['username'];
                  }
                  if (user['username'].toString().toLowerCase() == receiverUsername.toLowerCase()) {
                    receiverUid = uid;
                  }
                });
              }

              if (receiverUid != null && senderUsername != null) {
                await contactRequestsRef.child(receiverUid!).child(senderUid).set({
                  'status': 'pending',
                  'senderUsername': senderUsername,
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                });

                Navigator.pop(context);
                _showRequestSentModal(context, receiverUsername);
              } else {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('User Not Found'),
                    content: Text('The username "$receiverUsername" does not exist.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('OK'),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showRequestSentModal(BuildContext context, String name) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Request Sent'),
        content: Text('Your request to "$name" has been sent successfully.'),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
