import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';

class UploadedGuidesPopup {
  static Future<void> show(BuildContext context, DatabaseReference guidesRef) async {
    final snapshot = await guidesRef.get();
    final allGuides = snapshot.children.toList();

    // 🧩 Extract all unique categories
    final Set<String> categorySet = {};
    for (final node in allGuides) {
      final cat = node.child('category').value?.toString();
      if (cat != null && cat.isNotEmpty) categorySet.add(cat);
    }

    final List<String> categories = ['All', ...categorySet.toList()];
    String selectedCategory = 'All';

    // 🧭 Extract YouTube thumbnail
    String? extractThumbnail(String url) {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;
      if (uri.host.contains('youtube.com') && uri.queryParameters.containsKey('v')) {
        return 'https://img.youtube.com/vi/${uri.queryParameters['v']}/hqdefault.jpg';
      } else if (uri.host.contains('youtu.be')) {
        final videoId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
        return videoId != null ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg' : null;
      }
      return null;
    }

    // 🗑️ Confirm delete dialog
    void showConfirmDeleteDialog(String id) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text(
            "Delete Guide?",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
          ),
          content: const Text(
            "Are you sure you want to delete this self-defense guide?",
            style: TextStyle(color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                await guidesRef.child(id).remove();
                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("🗑️ Guide deleted successfully")),
                );
              },
              child: const Text("Delete"),
            ),
          ],
        ),
      );
    }

    // ✏️ Edit dialog
    void showEditDialog(String id, String currentTitle, String currentDesc,
        String currentCategory, DatabaseReference guideRef) {
      final TextEditingController titleCtrl =
      TextEditingController(text: currentTitle);
      final TextEditingController descCtrl =
      TextEditingController(text: currentDesc);
      String selectedEditCategory = currentCategory;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text("Edit Self-Defense Guide",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: InputDecoration(
                      labelText: "Title",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "Description",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedEditCategory,
                    items: categorySet
                        .map((cat) => DropdownMenuItem(
                      value: cat,
                      child: Text(cat),
                    ))
                        .toList(),
                    onChanged: (value) {
                      selectedEditCategory = value!;
                    },
                    decoration: InputDecoration(
                      labelText: "Category",
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text("Save Changes"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final newTitle = titleCtrl.text.trim();
                final newDesc = descCtrl.text.trim();

                if (newTitle.isEmpty || newDesc.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill all fields")),
                  );
                  return;
                }

                await guideRef.update({
                  'title': newTitle,
                  'description': newDesc,
                  'category': selectedEditCategory,
                });

                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✅ Guide updated successfully")),
                );
              },
            ),
          ],
        ),
      );
    }

    // 🪄 Main popup dialog
    showGeneralDialog(
      context: context,
      barrierLabel: "Close",
      barrierDismissible: true,
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, _, __) {
        return StatefulBuilder(
          builder: (context, setState) {
            final filteredGuides = selectedCategory == 'All'
                ? allGuides
                : allGuides.where((node) {
              final cat = node.child('category').value?.toString() ?? '';
              return cat == selectedCategory;
            }).toList();

            return Transform.scale(
              scale: Curves.easeOutBack.transform(animation.value),
              child: Opacity(
                opacity: animation.value,
                child: AlertDialog(
                  backgroundColor: const Color(0xFFF8FFF8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  title: Row(
                    children: const [
                      Icon(Icons.menu_book_rounded, color: Color(0xFF2EB872)),
                      SizedBox(width: 8),
                      Text(
                        "Uploaded Self-Defense Guides",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0E4D35),
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 600,
                    height: 500,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🔽 Category Filter Dropdown
                        DropdownButtonFormField<String>(
                          value: selectedCategory,
                          items: categories
                              .map((cat) => DropdownMenuItem(
                            value: cat,
                            child: Text(cat),
                          ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              selectedCategory = value!;
                            });
                          },
                          decoration: InputDecoration(
                            labelText: "Filter by Category",
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 🧾 Filtered Guides
                        Expanded(
                          child: filteredGuides.isEmpty
                              ? const Center(
                            child: Text(
                              "No guides found for this category.",
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 16),
                            ),
                          )
                              : ListView.builder(
                            itemCount: filteredGuides.length,
                            itemBuilder: (context, index) {
                              final node = filteredGuides[index];
                              final id = node.key!;
                              final title =
                                  node.child('title').value?.toString() ??
                                      'Untitled Guide';
                              final description = node
                                  .child('description')
                                  .value
                                  ?.toString() ??
                                  '';
                              final link =
                                  node.child('link').value?.toString() ??
                                      'No link';
                              final thumb = extractThumbnail(link);
                              final category = node
                                  .child('category')
                                  .value
                                  ?.toString() ??
                                  'Uncategorized';

                              return _HoverableGuideCard(
                                id: id,
                                title: title,
                                description: description,
                                link: link,
                                thumbnail: thumb,
                                category: category,
                                onDelete: () =>
                                    showConfirmDeleteDialog(id),
                                onEdit: () => showEditDialog(
                                    id,
                                    title,
                                    description,
                                    category,
                                    guidesRef.child(id)),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close",
                          style: TextStyle(color: Colors.grey, fontSize: 15)),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HoverableGuideCard extends StatefulWidget {
  final String id;
  final String title;
  final String description;
  final String link;
  final String? thumbnail;
  final String category;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _HoverableGuideCard({
    required this.id,
    required this.title,
    required this.description,
    required this.link,
    required this.thumbnail,
    required this.category,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<_HoverableGuideCard> createState() => _HoverableGuideCardState();
}

class _HoverableGuideCardState extends State<_HoverableGuideCard> {
  bool _hovered = false;

  Future<void> _openLink() async {
    if (widget.link != 'No link') {
      final uri = Uri.parse(widget.link);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradient = _hovered
        ? const LinearGradient(
      colors: [Color(0xFFFFF3E0), Color(0xFFC8F4E4)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    )
        : const LinearGradient(
      colors: [Color(0xFFF8FFF8), Color(0xFFEFFFFA)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // 👇 Make the entire box clickable
      child: GestureDetector(
        onTap: _openLink,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          transform: _hovered ? (Matrix4.identity()..scale(1.02)) : Matrix4.identity(),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _hovered
                    ? Colors.orangeAccent.withOpacity(0.4)
                    : Colors.green.withOpacity(0.08),
                blurRadius: _hovered ? 16 : 8,
                offset: const Offset(3, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 📸 Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: widget.thumbnail != null
                    ? AnimatedScale(
                  scale: _hovered ? 1.05 : 1.0,
                  duration: const Duration(milliseconds: 250),
                  child: Image.network(
                    widget.thumbnail!,
                    width: 130,
                    height: 85,
                    fit: BoxFit.cover,
                  ),
                )
                    : Container(
                  width: 130,
                  height: 85,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.image_not_supported_outlined,
                      color: Colors.grey, size: 30),
                ),
              ),
              const SizedBox(width: 14),

              // 📄 Text Section
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF084C41))),
                    const SizedBox(height: 4),
                    Text(widget.category,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal)),
                    const SizedBox(height: 6),
                    Text(widget.description,
                        softWrap: true,
                        style: const TextStyle(
                            fontSize: 15.5,
                            height: 1.45,
                            color: Color(0xFF2F4F4F),
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),

              // ✏️ Edit + 🗑️ Delete Buttons
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_note_rounded,
                        color: Colors.blueAccent),
                    onPressed: widget.onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Colors.redAccent),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
