import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

class SelfDefenseGuidePage extends StatefulWidget {
  const SelfDefenseGuidePage({super.key});

  @override
  State<SelfDefenseGuidePage> createState() => _SelfDefenseGuidePageState();
}

class _SelfDefenseGuidePageState extends State<SelfDefenseGuidePage> {
  bool _isLoading = true;
  List<_GuideItem> _guides = [];

  @override
  void initState() {
    super.initState();
    _loadSelfDefenseGuides();
  }

  Future<void> _loadSelfDefenseGuides() async {
    try {
      final ref = FirebaseDatabase.instance.ref('self_defense_guides');
      final snapshot = await ref.get();

      final List<_GuideItem> loaded = [];

      if (snapshot.exists) {
        for (final child in snapshot.children) {
          final raw = (child.value as Map).cast<dynamic, dynamic>();

          // Normalize fields across different writer UIs
          final title = (raw['title'] ??
              raw['name'] ??
              'Untitled')
              .toString();

          final description = (raw['description'] ?? '').toString();

          // File/PDF url may be under 'url' or 'fileurl'
          final fileUrl = (raw['url'] ?? raw['fileurl']);
          final String? safeFileUrl =
          fileUrl == null ? null : fileUrl.toString();

          // Images can be: a single 'imageurl' string or a 'images' list
          final List<String> images = [];
          if (raw['images'] is List) {
            for (final e in (raw['images'] as List)) {
              if (e is String && e.isNotEmpty) images.add(e);
            }
          }
          final singleImage = raw['imageurl'];
          if (singleImage is String && singleImage.isNotEmpty) {
            images.add(singleImage);
          }

          final uploadedAt = (raw['uploaded_at'] ?? '').toString();

          loaded.add(_GuideItem(
            title: title,
            description: description,
            uploadedAt: uploadedAt,
            fileUrl: safeFileUrl,
            images: images,
          ));
        }
      }

      setState(() {
        _guides = loaded;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load guides: $e')),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Self-Defense Guide Tips'),
        backgroundColor: const Color(0xFF2A9D8F),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _guides.isEmpty
          ? const Center(child: Text('No guides available.'))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _guides.length,
        itemBuilder: (context, i) {
          final g = _guides[i];

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: 12, horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    g.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),

                  // Optional uploaded time
                  if (g.uploadedAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Uploaded: ${g.uploadedAt}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],

                  // Optional description
                  if (g.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      g.description,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],

                  // Image gallery (horizontal)
                  if (g.images.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: g.images.length,
                        separatorBuilder: (_, __) =>
                        const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final url = g.images[idx];
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              onTap: () {
                                // open full screen preview instead of url_launcher
                                showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    insetPadding: EdgeInsets.all(16),
                                    child: InteractiveViewer(
                                      child: Image.network(
                                        url,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const Center(
                                          child: Icon(Icons.broken_image, size: 48),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Image.network(
                                url,
                                width: 120,
                                height: 96,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade300,
                                  width: 120,
                                  height: 96,
                                  alignment: Alignment.center,
                                  child: const Icon(Icons.image_not_supported),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // File/PDF open button (if present)
                  if (g.fileUrl != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () => _openUrl(g.fileUrl!),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GuideItem {
  final String title;
  final String description;
  final String uploadedAt;
  final String? fileUrl; // pdf/attachment if any
  final List<String> images; // zero or more image URLs

  _GuideItem({
    required this.title,
    required this.description,
    required this.uploadedAt,
    required this.fileUrl,
    required this.images,
  });
}