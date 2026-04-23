import '../core/supabase_client.dart';

class StickerService {
  const StickerService();

  String get _currentUserId => supabase.auth.currentUser!.id;

  // ── Fetch user's saved sticker collection ──
  Stream<List<String>> getMyStickers() {
    return supabase
        .from('saved_stickers')
        .stream(primaryKey: ['id'])
        .eq('user_id', _currentUserId)
        .map((rows) => rows.map((e) => e['url'] as String).toList());
  }

  // ── Save a sticker URL to collection ──
  Future<void> saveSticker(String url) async {
    await supabase.from('saved_stickers').upsert(
      {'user_id': _currentUserId, 'url': url},
      onConflict: 'user_id, url',
    );
  }

  // ── Remove a sticker from collection ──
  Future<void> removeSticker(String url) async {
    await supabase
        .from('saved_stickers')
        .delete()
        .eq('user_id', _currentUserId)
        .eq('url', url);
  }
}
