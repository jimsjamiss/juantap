import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'responder_chat_screen.dart';

class ResponderChatList extends StatelessWidget {
  final String responderId;

  const ResponderChatList({super.key, required this.responderId});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref("chat_rooms");

    return Scaffold(
      appBar: AppBar(
        title: const Text("Messages"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),

      body: StreamBuilder(
        stream: ref.onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return const Center(child: Text("No conversations"));
          }

          final raw = Map<dynamic, dynamic>.from(
              snapshot.data!.snapshot.value as dynamic);

          /// Only chats where responderId == this responder
          final chats = raw.entries.where((e) {
            final data = Map<String, dynamic>.from(e.value);
            return data["responderId"] == responderId;
          }).map((e) {
            final room = Map<String, dynamic>.from(e.value);
            room["chatId"] = e.key;
            return room;
          }).toList()
            ..sort((a, b) =>
                (b["lastTimestamp"] ?? 0).compareTo(a["lastTimestamp"] ?? 0));

          if (chats.isEmpty) {
            return const Center(child: Text("No conversations"));
          }

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (_, i) {
              final chat = chats[i];
              final chatId = chat["chatId"];
              final userId = chat["userId"]; // the OTHER participant

              return FutureBuilder(
                future: FirebaseDatabase.instance.ref("users/$userId").get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return const ListTile(title: Text("Unknown user"));
                  }

                  final user = Map<String, dynamic>.from(snapshot.data!.value as Map);

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: (user["profileImage"] != null &&
                          user["profileImage"].toString().isNotEmpty)
                          ? NetworkImage(user["profileImage"])
                          : const AssetImage("assets/images/user_profile.png")
                      as ImageProvider,
                    ),
                    title: Text(user["username"] ?? "Unknown User"),
                    subtitle: Text(chat["lastMessage"] ?? ""),
                    trailing: Text(_format(chat["lastTimestamp"])),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ResponderChatScreen(
                            chatId: chatId,
                            responderId: responderId,
                            userInfo: user,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  String _format(ts) {
    if (ts == null) return "";
    final dt = DateTime.fromMillisecondsSinceEpoch(ts);
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }
}
