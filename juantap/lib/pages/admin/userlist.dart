import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'usersdetails.dart';

class userlist extends StatefulWidget {
  const userlist({super.key});

  @override
  State<userlist> createState() => _UserListState();
}

class _UserListState extends State<userlist> {
  List<Map<String, String>> users = [];

  @override
  void initState() {
    super.initState();
    fetchUsersFromFirebase();
  }

  Future<void> fetchUsersFromFirebase() async {
    final dbRef = FirebaseDatabase.instance.ref().child('users');
    final snapshot = await dbRef.get();
    if (snapshot.exists) {
      final Map data = snapshot.value as Map;
      final List<Map<String, String>> loadedUsers = [];

      data.forEach((key, value) {
        final user = Map<String, dynamic>.from(value);
        if (user['role'] == 'user') {
          loadedUsers.add({
            'id': key,
            'name': user['username'] ?? 'No Name',
            'phone': user['phone'] ?? 'No Number',
          });
        }
      });

      setState(() {
        users = loadedUsers;
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
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const CircleAvatar(
              radius: 20,
              backgroundImage: NetworkImage('https://i.imgur.com/XkBHY6U.png'),
            ),
            const SizedBox(width: 10),
            const Text('Hi Admin!', style: TextStyle(color: Colors.white)),
            const Spacer(),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(6),
              child: const Icon(Icons.download, color: Colors.teal),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Users List',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserDetailsPage(userId: user['id']!),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFB2EFE8), Color(0xFFC0F1EC)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.account_circle, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(user['phone']!, style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => UserDetailsPage(userId: user['id']!),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete User'),
                                  content: Text('Are you sure you want to delete ${user['name']}?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${user['name']} deleted')),
                                        );
                                      },
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}