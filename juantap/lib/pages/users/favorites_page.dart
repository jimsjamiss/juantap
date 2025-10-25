import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final DatabaseReference _usersRef = FirebaseDatabase.instance.ref('users');
  User? _currentUser;
  List<Map<String, dynamic>> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _listenToFavorites();
  }

  // 🔄 Listen for changes to favorites
  void _listenToFavorites() {
    if (_currentUser == null) return;

    final favRef = _usersRef.child('${_currentUser!.uid}/favorites');
    favRef.onValue.listen((event) {
      final favs = <Map<String, dynamic>>[];
      for (final fav in event.snapshot.children) {
        final data = fav.value as Map<dynamic, dynamic>?;
        if (data == null) continue;
        favs.add({
          'id': fav.key ?? '',
          'title': (data['title'] ?? '').toString(),
          'description': (data['description'] ?? '').toString(),
          'link': (data['link'] ?? '').toString(),
          'thumbnail': (data['thumbnail'] ?? '').toString(),
          'category': (data['category'] ?? '').toString(),
        });
      }

      setState(() {
        _favorites = favs;
        _isLoading = false;
      });
    });
  }

  // 🎥 Open YouTube link safely
  Future<void> _openLink(String url) async {
    if (url.isEmpty) return;
    try {
      String fixedUrl = url.trim();
      if (!fixedUrl.startsWith('http')) {
        fixedUrl = 'https://$fixedUrl';
      }
      final uri = Uri.parse(fixedUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open video: $e')),
      );
    }
  }

  // 💔 Remove from favorites
  Future<void> _removeFavorite(String id) async {
    if (_currentUser == null) return;
    await _usersRef.child('${_currentUser!.uid}/favorites/$id').remove();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFFFFA),
      appBar: AppBar(
        elevation: 6,
        shadowColor: Colors.black26,
        automaticallyImplyLeading: true,
        title: const Text(
          'My Favorite Guides',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: 0.4,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2EB872), Color(0xFF1C8873)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Color(0xFF2EB872)))
          : _favorites.isEmpty
          ? const Center(
        child: Text(
          "No favorites yet 💔\nTap the heart on a guide to add it here!",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      )
          : ListView.builder(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: _favorites.length,
        itemBuilder: (context, i) {
          final g = _favorites[i];
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _FavoriteCard(
              title: g['title'],
              description: g['description'],
              link: g['link'],
              thumbnail: g['thumbnail'],
              category: g['category'],
              onTap: () => _openLink(g['link']),
              onRemove: () => _removeFavorite(g['id']),
            ),
          );
        },
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final String title;
  final String description;
  final String link;
  final String? thumbnail;
  final String category;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _FavoriteCard({
    required this.title,
    required this.description,
    required this.link,
    required this.thumbnail,
    required this.category,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: (_) => onTap(),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFB7E2C1), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(2, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            // 🎥 Thumbnail with heart overlay
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                  child: thumbnail != null && thumbnail!.isNotEmpty
                      ? Image.network(
                    thumbnail!,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                  )
                      : Container(
                    height: 200,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.image_not_supported_outlined,
                        color: Colors.grey, size: 40),
                  ),
                ),
                // ❤️ Remove button (top of thumbnail)
                Positioned(
                  bottom: 10,
                  right: 12,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.redAccent,
                      size: 34,
                      shadows: [
                        Shadow(
                            blurRadius: 8,
                            color: Colors.black38,
                            offset: Offset(1, 2))
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // 📄 Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🧾 Title
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0E4D35),
                      height: 1.4,
                    ),
                    softWrap: true,
                  ),
                  const SizedBox(height: 8),

                  // 🏷 Category Tag
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2EB872).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      category,
                      style: const TextStyle(
                        color: Color(0xFF1C8873),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 📝 Description
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: Color(0xFF2F4F4F),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
