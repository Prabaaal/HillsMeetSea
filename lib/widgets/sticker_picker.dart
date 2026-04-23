import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/sticker_service.dart';

class StickerPicker extends StatefulWidget {
  final Function(String) onStickerSelected;

  const StickerPicker({super.key, required this.onStickerSelected});

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  static const _stickerService = StickerService();

  static const _defaultEmojis = [
    '❤️',
    '😂',
    '🥺',
    '😍',
    '🤗',
    '😘',
    '🫶',
    '💕',
    '🌟',
    '🔥',
    '✨',
    '🎉',
    '💐',
    '🌈',
    '🦋',
    '🐻',
    '🍕',
    '☕',
    '🎵',
    '💤',
    '🙈',
    '🤣',
    '😊',
    '💪',
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          TabBar(
            tabs: const [Tab(text: 'Stickers'), Tab(text: 'Saved')],
            indicatorColor: const Color(0xFFB57BFF),
            labelColor: Colors.white,
            labelStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
            unselectedLabelColor: Colors.white38,
            dividerHeight: 0,
          ),
          Expanded(
            child: TabBarView(
              children: [_buildEmojiGrid(), _buildSavedStickers()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _defaultEmojis.length,
      itemBuilder: (context, index) {
        return GestureDetector(
          onTap: () =>
              widget.onStickerSelected('emoji:${_defaultEmojis[index]}'),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              _defaultEmojis[index],
              style: const TextStyle(fontSize: 28),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSavedStickers() {
    return StreamBuilder<List<String>>(
      stream: _stickerService.getMyStickers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFB57BFF)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.collections_outlined,
                      color: Colors.white24, size: 48),
                  const SizedBox(height: 16),
                  Text('No saved stickers yet',
                      style: GoogleFonts.dmSans(
                          color: Colors.white38, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Long-press a sticker in chat to save it',
                      style: GoogleFonts.dmSans(
                          color: Colors.white24, fontSize: 12)),
                ],
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final url = snapshot.data![index];
            return GestureDetector(
              onTap: () => widget.onStickerSelected(url),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
                placeholder: (_, __) => Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white24),
              ),
            );
          },
        );
      },
    );
  }
}
