import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config/env.dart';
import 'core/supabase_client.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';

// VAPID key for Web Push notifications — injected at build time.
const String pushVapidPublicKey =
    String.fromEnvironment('PUSH_VAPID_PUBLIC_KEY', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 40),
  );

  runApp(const HillsMeetSeaApp());
}

class HillsMeetSeaApp extends StatelessWidget {
  const HillsMeetSeaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HillsMeetSea',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = supabase.auth.currentSession;
          if (session != null) return const ChatScreen();
          return const AuthScreen();
        },
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFE8D5FF),
        secondary: Color(0xFFB8E4FF),
        surface: Color(0x0DFFFFFF),
        onPrimary: Color(0xFF1A0A2E),
        onSurface: Colors.white,
        outline: Color(0x1AFFFFFF),
      ),
      textTheme: GoogleFonts.dmSansTextTheme(
        ThemeData.dark().textTheme,
      ).copyWith(
        displayLarge: GoogleFonts.playfairDisplay(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
      ),
    );
  }
}
