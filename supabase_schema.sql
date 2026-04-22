-- ============================================
-- HillsMeetSea - Supabase Schema
-- Run this in your Supabase SQL editor
-- ============================================

-- Users table (extends Supabase auth.users)
create table public.profiles (
  id uuid references auth.users(id) on delete cascade primary key,
  name text not null,
  avatar_url text,
  status text default 'offline', -- 'online' | 'offline' | 'typing'
  last_seen timestamptz default now(),
  created_at timestamptz default now()
);

-- Messages table
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid references public.profiles(id) on delete cascade not null,
  content text,
  media_url text,
  media_type text, -- 'image' | 'voice' | 'sticker'
  reply_to_id uuid references public.messages(id) on delete set null,
  created_at timestamptz default now(),
  read_at timestamptz
);

-- Message Reactions table
create table public.message_reactions (
  id uuid primary key default gen_random_uuid(),
  message_id uuid references public.messages(id) on delete cascade not null,
  user_id uuid references public.profiles(id) on delete cascade not null,
  emoji text not null,
  created_at timestamptz default now(),
  unique(message_id, user_id, emoji)
);

-- Saved Stickers table (for sticker collection)
create table public.saved_stickers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  url text not null,
  created_at timestamptz default now(),
  unique(user_id, url)
);

-- Web Push subscriptions per device/browser
create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade not null,
  endpoint text not null unique,
  subscription jsonb not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- WebRTC signaling table (for call setup)
create table public.signals (
  id uuid primary key default gen_random_uuid(),
  from_user uuid references public.profiles(id),
  to_user uuid references public.profiles(id),
  type text not null, -- 'offer' | 'answer' | 'candidate' | 'hangup'
  data jsonb not null,
  created_at timestamptz default now()
);

-- ============================================
-- Row Level Security
-- ============================================

alter table public.profiles enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.saved_stickers enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.signals enable row level security;

-- Profiles: any authenticated user can read, only owner can update
create policy "Anyone can view profiles" on public.profiles
  for select using (auth.role() = 'authenticated');

create policy "Users can update own profile" on public.profiles
  for update using (auth.uid() = id);

create policy "Profile created on signup" on public.profiles
  for insert with check (auth.uid() = id);

-- Messages: any authenticated user can read and send
create policy "Authenticated users can read messages" on public.messages
  for select using (auth.role() = 'authenticated');

create policy "Authenticated users can send messages" on public.messages
  for insert with check (auth.uid() = sender_id);

create policy "Sender can update own message" on public.messages
  for update using (auth.uid() = sender_id);

create policy "Recipients can mark messages as read" on public.messages
  for update using (auth.role() = 'authenticated')
  with check (
    auth.role() = 'authenticated'
    and sender_id <> auth.uid()
    and read_at is not null
  );

-- Reactions: anyone authenticated can read and add
create policy "Authenticated users can read reactions" on public.message_reactions
  for select using (auth.role() = 'authenticated');

create policy "Authenticated users can add reactions" on public.message_reactions
  for insert with check (auth.uid() = user_id);

-- Saved Stickers: only owner can read and add
create policy "Users can view own stickers" on public.saved_stickers
  for select using (auth.uid() = user_id);

create policy "Users can add to own sticker collection" on public.saved_stickers
  for insert with check (auth.uid() = user_id);

-- Push subscriptions: only owner can manage own browser/device subscriptions
create policy "Users can view own push subscriptions" on public.push_subscriptions
  for select using (auth.uid() = user_id);

create policy "Users can insert own push subscriptions" on public.push_subscriptions
  for insert with check (auth.uid() = user_id);

create policy "Users can update own push subscriptions" on public.push_subscriptions
  for update using (auth.uid() = user_id);

create policy "Users can delete own push subscriptions" on public.push_subscriptions
  for delete using (auth.uid() = user_id);

-- Signals: users can read signals addressed to them
create policy "Users can read their signals" on public.signals
  for select using (auth.uid() = to_user);

create policy "Users can send signals" on public.signals
  for insert with check (auth.uid() = from_user);

create policy "Users can delete their signals" on public.signals
  for delete using (auth.uid() = from_user or auth.uid() = to_user);

-- ============================================
-- Realtime - enable for all tables
-- ============================================
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.signals;
alter publication supabase_realtime add table public.profiles;
alter publication supabase_realtime add table public.message_reactions;
alter publication supabase_realtime add table public.saved_stickers;

-- ============================================
-- Storage bucket for media
-- ============================================
-- Note: SQL cannot create buckets, but it can create policies.
-- Bucket creation should be done via dashboard OR storage API.

create policy "Authenticated users can upload media" on storage.objects
  for insert with check (auth.role() = 'authenticated' and bucket_id = 'media');

create policy "Media is publicly readable" on storage.objects
  for select using (bucket_id = 'media');

-- ============================================
-- Function: auto-create profile on signup
-- ============================================
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1))
  );
  return new;
end;
$$ language plpgsql security definer;

-- Trigger: create profile on signup
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
