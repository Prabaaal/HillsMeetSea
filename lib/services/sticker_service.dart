import '../main.dart';

class StickerService {
  String get currentUserId => supabase.auth.currentUser!.id;

  // ── Fetch user's saved sticker collection ──
  Stream<List<String>> getMyStickers() {
    return supabase
        .from('saved_stickers')
        .stream(primaryKey: ['id'])
        .eq('user_id', currentUserId)
        .map((rows) => rows.map((e) => e['url'] as String).toList());
  }

  // ── Save a sticker URL to collection ──
  Future<void> saveSticker(String url) async {
    await supabase.from('saved_stickers').upsert({
      'user_id': currentUserId,
      'url': url,
    }, onConflict: 'user_id, url');
  }

  // ── Remove a sticker from collection ──
  Future<void> removeSticker(String url) async {
    await supabase
        .from('saved_stickers')
        .delete()
        .eq('user_id', currentUserId)
        .eq('url', url);
  }
}
