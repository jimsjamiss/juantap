import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class UploadGuideButton extends StatefulWidget {
  final DatabaseReference guidesRef;
  const UploadGuideButton({super.key, required this.guidesRef});

  @override
  State<UploadGuideButton> createState() => _UploadGuideButtonState();
}

class _UploadGuideButtonState extends State<UploadGuideButton> {
  final TextEditingController titleCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  final TextEditingController linkCtrl = TextEditingController();
  final TextEditingController newCategoryCtrl = TextEditingController();

  // 🧩 Default base categories
  final List<String> baseCategories = [
    "Women's Self-Defense",
    "Verbal & Psychological Defense",
    "Escape & Evasion"
  ];

  List<String> _categories = [];
  String selectedCategory = "Women's Self-Defense";
  bool isCustomCategory = false;

  // 🧭 Fetch all categories dynamically and ensure uniqueness
  Future<void> _loadCategories() async {
    final snapshot = await widget.guidesRef.get();
    final Set<String> categorySet = baseCategories.map((c) => c.toLowerCase()).toSet();

    for (final node in snapshot.children) {
      final cat = node.child('category').value?.toString();
      if (cat != null && cat.isNotEmpty) {
        categorySet.add(cat.toLowerCase());
      }
    }

    // 🧠 Rebuild categories with proper capitalization from original entries
    final uniqueCategories = <String>{};
    for (final lower in categorySet) {
      // Try to match original case from defaults first
      final original = baseCategories.firstWhere(
            (c) => c.toLowerCase() == lower,
        orElse: () => lower[0].toUpperCase() + lower.substring(1),
      );
      uniqueCategories.add(original);
    }

    setState(() {
      _categories = uniqueCategories.toList();
      _categories.sort(); // optional: alphabetize dropdown
    });
  }

  // 🧭 Show upload dialog
  void _showUploadGuideDialog(BuildContext context) async {
    await _loadCategories(); // load unique categories

    showGeneralDialog(
      context: context,
      barrierLabel: "Upload Guide",
      barrierDismissible: true,
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, _, __) {
        return Transform.scale(
          scale: Curves.easeOutBack.transform(animation.value),
          child: Opacity(
            opacity: animation.value,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  backgroundColor: const Color(0xFFF8FFF8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  title: Row(
                    children: const [
                      Icon(Icons.video_library_rounded,
                          color: Color(0xFF1E88E5)),
                      SizedBox(width: 8),
                      Text(
                        "Upload Self-Defense Guide",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0E4D35),
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: 400,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 🧩 Category dropdown + custom option
                          DropdownButtonFormField<String>(
                            value: isCustomCategory ? null : selectedCategory,
                            items: [
                              ..._categories.map((cat) => DropdownMenuItem(
                                value: cat,
                                child: Text(cat),
                              )),
                              const DropdownMenuItem(
                                value: "__custom__",
                                child: Row(
                                  children: [
                                    Icon(Icons.add_circle_outline_rounded,
                                        color: Colors.teal),
                                    SizedBox(width: 6),
                                    Text("Add New Category"),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == "__custom__") {
                                setDialogState(() {
                                  isCustomCategory = true;
                                  newCategoryCtrl.clear();
                                });
                              } else if (value != null) {
                                setDialogState(() {
                                  isCustomCategory = false;
                                  selectedCategory = value;
                                });
                              }
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
                          const SizedBox(height: 10),

                          // 🆕 Custom category input (only visible if chosen)
                          if (isCustomCategory)
                            TextField(
                              controller: newCategoryCtrl,
                              decoration: InputDecoration(
                                labelText: "New Category Name",
                                hintText: "e.g. Martial Arts Defense",
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),

                          // 🧾 Title
                          TextField(
                            controller: titleCtrl,
                            decoration: InputDecoration(
                              labelText: "Title",
                              hintText: "e.g. Basic Self-Defense Moves",
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 🧾 Description
                          TextField(
                            controller: descCtrl,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText: "Description",
                              hintText:
                              "Briefly describe what this guide is about...",
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 🧾 YouTube link
                          TextField(
                            controller: linkCtrl,
                            decoration: InputDecoration(
                              labelText: "YouTube Link",
                              hintText:
                              "https://www.youtube.com/watch?v=example",
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
                      child: const Text("Cancel",
                          style: TextStyle(color: Colors.grey)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final title = titleCtrl.text.trim();
                        final desc = descCtrl.text.trim();
                        final link = linkCtrl.text.trim();
                        final category = isCustomCategory
                            ? newCategoryCtrl.text.trim()
                            : selectedCategory;

                        if (title.isEmpty ||
                            desc.isEmpty ||
                            link.isEmpty ||
                            category.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Please fill in all fields.")),
                          );
                          return;
                        }

                        if (!link.contains("youtube.com") &&
                            !link.contains("youtu.be")) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    "Please enter a valid YouTube link.")),
                          );
                          return;
                        }

                        final id = widget.guidesRef.push().key!;
                        await widget.guidesRef.child(id).set({
                          'title': title,
                          'description': desc,
                          'link': link,
                          'category': category,
                          'uploaded_at': DateTime.now().toIso8601String(),
                        });

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  "✅ Guide uploaded successfully under '$category'")),
                        );
                      },
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: const Text("Upload"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF38EF7D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton.icon(
          onPressed: () => _showUploadGuideDialog(context),
          icon: const Icon(Icons.video_library_rounded, size: 20),
          label: const Text("Upload Guide"),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E88E5),
            foregroundColor: Colors.white,
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            shadowColor: Colors.black26,
            elevation: 6,
          ),
        ),
      ),
    );
  }
}
