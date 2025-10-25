import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'favorites_page.dart';

class SelfDefenseGuidePage extends StatefulWidget {
  const SelfDefenseGuidePage({super.key});

  @override
  State<SelfDefenseGuidePage> createState() => _SelfDefenseGuidePageState();
}

class _SelfDefenseGuidePageState extends State<SelfDefenseGuidePage>
    with SingleTickerProviderStateMixin {
  final DatabaseReference _guidesRef =
  FirebaseDatabase.instance.ref('self_defense_guides');
  final DatabaseReference _usersRef =
  FirebaseDatabase.instance.ref('users');

  bool _isLoading = true;
  List<Map<String, dynamic>> _guides = [];
  List<String> _categories = ['All'];
  String _selectedCategory = 'All';

  User? _currentUser;
  Set<String> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _listenToGuides();
    _listenToFavorites();
  }

  String? _extractThumbnail(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host.contains('youtube.com') && uri.queryParameters.containsKey('v')) {
      return 'https://img.youtube.com/vi/${uri.queryParameters['v']}/hqdefault.jpg';
    } else if (uri.host.contains('youtu.be')) {
      final videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      return videoId != null
          ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg'
          : null;
    }
    return null;
  }

  void _listenToGuides() {
    _guidesRef.onValue.listen((event) {
      final List<Map<String, dynamic>> loaded = [];
      final Set<String> categorySet = {};

      for (final guide in event.snapshot.children) {
        final data = guide.value as Map<dynamic, dynamic>?;
        if (data == null) continue;
        final title = (data['title'] ?? 'Untitled').toString();
        final description = (data['description'] ?? '').toString();
        final link = (data['link'] ?? '').toString();
        final category = (data['category'] ?? 'Uncategorized').toString();
        final uploadedAt = (data['uploaded_at'] ?? '').toString();

        if (category.isNotEmpty) categorySet.add(category);
        final thumb = _extractThumbnail(link);

        loaded.add({
          'id': guide.key,
          'title': title,
          'description': description,
          'link': link,
          'thumbnail': thumb,
          'category': category,
          'uploaded_at': uploadedAt,
        });
      }

      setState(() {
        _guides = loaded;
        _categories = ['All', ...categorySet.toList()];
        _isLoading = false;
      });
    });
  }

  void _listenToFavorites() {
    if (_currentUser == null) return;
    final favRef = _usersRef.child('${_currentUser!.uid}/favorites');
    favRef.onValue.listen((event) {
      final favIds = <String>{};
      for (final fav in event.snapshot.children) {
        favIds.add(fav.key ?? '');
      }
      setState(() => _favoriteIds = favIds);
    });
  }

  Future<void> _toggleFavorite(Map<String, dynamic> guideData) async {
    if (_currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to favorite guides.')),
      );
      return;
    }

    final favRef =
    _usersRef.child('${_currentUser!.uid}/favorites/${guideData['id']}');

    if (_favoriteIds.contains(guideData['id'])) {
      await favRef.remove();
    } else {
      await favRef.set({
        'title': guideData['title'],
        'description': guideData['description'],
        'link': guideData['link'],
        'thumbnail': guideData['thumbnail'],
        'category': guideData['category'],
        'uploaded_at': guideData['uploaded_at'],
      });
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedCategory == 'All'
        ? _guides
        : _guides.where((g) => g['category'] == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFEFFFFA),
      appBar: AppBar(
        elevation: 6,
        shadowColor: Colors.black26,
        automaticallyImplyLeading: true,
        title: const Text(
          'Self-Defenses',
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withOpacity(0.15),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: const BorderSide(color: Colors.white70, width: 1),
                ),
              ),
              icon: const Icon(Icons.favorite, color: Colors.white, size: 20),
              label: const Text(
                'Favorites',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  fontSize: 15,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const FavoritesPage()),
                );
              },
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2EB872)))
          : _guides.isEmpty
          ? const Center(
        child: Text(
          'No self-defense guides found.',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      )
          : Column(
        children: [
          Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: DropdownButtonFormField<String>(
              value: _selectedCategory,
              items: _categories
                  .map((cat) => DropdownMenuItem(
                value: cat,
                child: Text(cat),
              ))
                  .toList(),
              onChanged: (value) {
                setState(() => _selectedCategory = value!);
              },
              decoration: InputDecoration(
                labelText: "Filter by Category",
                filled: true,
                fillColor: Colors.white,
                labelStyle: const TextStyle(
                    color: Color(0xFF0E4D35),
                    fontWeight: FontWeight.bold),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide:
                  const BorderSide(color: Color(0xFF2EB872), width: 2),
                  borderRadius: BorderRadius.circular(14),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filtered.length,
              itemBuilder: (context, i) {
                final g = filtered[i];
                final isFav = _favoriteIds.contains(g['id']);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: _GuideCard(
                    title: g['title'],
                    description: g['description'],
                    link: g['link'],
                    thumbnail: g['thumbnail'],
                    category: g['category'],
                    isFavorite: isFav,
                    onTap: () => _openLink(g['link']),
                    onFavoriteTap: () => _toggleFavorite(g),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final String title;
  final String description;
  final String link;
  final String? thumbnail;
  final String category;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  const _GuideCard({
    required this.title,
    required this.description,
    required this.link,
    required this.thumbnail,
    required this.category,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteTap,
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
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                  child: thumbnail != null
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
                Positioned(
                  bottom: 10,
                  right: 12,
                  child: GestureDetector(
                    onTap: onFavoriteTap,
                    child: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.redAccent : Colors.white,
                      size: 34,
                      shadows: const [
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
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
