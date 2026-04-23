import 'package:supabase_flutter/supabase_flutter.dart';

/// Global accessor for the Supabase client.
///
/// Import this file instead of `main.dart` wherever you need the client.
/// This removes the circular dependency that previously forced every service
/// and widget to import the app entry-point.
SupabaseClient get supabase => Supabase.instance.client;
