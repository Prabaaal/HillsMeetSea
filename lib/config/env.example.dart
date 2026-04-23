// THIS FILE IS A TEMPLATE — do not put real credentials here.
//
// The real lib/config/env.dart is gitignored.
//
// Recommended approach: use --dart-define at build time (no files needed):
//
//   flutter run \
//     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
//     --dart-define=SUPABASE_ANON_KEY=your_anon_key_here
//
// For Vercel, add SUPABASE_URL and SUPABASE_ANON_KEY as project environment
// variables and set the build command to:
//
//   flutter build web \
//     --dart-define=SUPABASE_URL=$SUPABASE_URL \
//     --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key-here',
  );
}
