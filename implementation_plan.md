# Implementation Plan - HillsMeetSea Chat App (v2)

This plan incorporates the "crucial information" from `web/Instruction.txt` to build a feature-rich, glassmorphic private chat app for India↔China communication.

## User Review Required

> [!IMPORTANT]
> - **Supabase Schema Update**: I will be adding tables for stickers and reactions, and columns for replies and status tracking.
> - **Stickers Asset Pack**: I will assume a set of default stickers in `assets/stickers/`. If you have a specific pack, let me know.
> - **TURN Credentials**: I will use the free `openrelay.metered.ca` as a default, but you should eventually update to your own `metered.ca` keys as recommended.

## Proposed Changes

### 1. Database Schema (Supabase)

#### [MODIFY] [supabase_schema.sql](file:///Users/prabalgogoi/Downloads/HillsMeetSea/bondapp/supabase_schema.sql)
- Add `status` (text) and `last_seen` (timestamptz) to `profiles`.
- Add `reply_to_id` (uuid) to `messages`.
- [NEW] Create `message_reactions` table (message_id, user_id, emoji).
- [NEW] Create `saved_stickers` table (user_id, url) for reference-based sticker collection.
- Enable Realtime for all new tables.

### 2. Service Layer Refinement

#### [MODIFY] [chat_service.dart](file:///Users/prabalgogoi/Downloads/HillsMeetSea/bondapp/lib/services/chat_service.dart)
- Implement **Supabase Presence** for online/offline status and "typing..." indicators.
- Add `sendMessage` overload to handle `reply_to_id` and `media_type` ('sticker', 'audio').
- Implement `addReaction` and `nudge` (real-time broadcast).

#### [NEW] [sticker_service.dart](file:///Users/prabalgogoi/Downloads/HillsMeetSea/bondapp/lib/services/sticker_service.dart)
- Handle "Reference-based" sticker saving (Save URL, not file).
- Manage the user's private sticker collection.

### 3. Glassmorphic UI & Components

#### [MODIFY] [glass_container.dart](file:///Users/prabalgogoi/Downloads/HillsMeetSea/bondapp/lib/widgets/glass_container.dart)
- Refine blur (sigma 40) and border (subtle 0.15 opacity) for the premium "iPhone OS" feel.

#### [MODIFY] [message_bubble.dart](file:///Users/prabalgogoi/Downloads/HillsMeetSea/bondapp/lib/widgets/message_bubble.dart)
- Support **Quoted Replies**: Show a small glassmorphic preview of the replied-to message.
- Support **Reactions**: Display a row of small emojis on the bubble edge.
- Support **Stickers**: Display as transparent WebP images (no background bubble).
- Support **Voice Notes**: Visual progress bar and play/pause button.

### 4. Screen Updates

#### [MODIFY] [chat_screen.dart](file:///Users/prabalgogoi/Downloads/HillsMeetSea/bondapp/lib/screens/chat_screen.dart)
- **Header**: Show "online" or "last seen [time]" dynamically.
- **Auto-Scroll**: Implement logic to snap to bottom on new messages.
- **Input Bar Overhaul**:
    - Add **Voice Recording** button (Tap to hold/lock).
    - Add **Sticker Picker** with "Saved" and "Default" tabs.
    - Add **Reply Preview** slot above the text field.

#### [MODIFY] [call_screen.dart](file:///Users/prabalgogoi/Downloads/HillsMeetSea/bondapp/lib/screens/call_screen.dart)
- Finalize WebRTC signaling using the `signals` table.
- Implement **TURN fallback** logic if P2P (STUN) fails.

### 5. Media & PWA Polish

#### [MODIFY] [index.html](file:///Users/prabalgogoi/Downloads/HillsMeetSea/bondapp/web/index.html)
- Implement the **Blob workaround** for file downloads to ensure Safari/Chrome "Save to device" works.

## Open Questions

- **Stickers**: Do you want me to provide a few default sticker assets, or will you add them later?
- **Nudge Sound**: Should I include a default "ping" sound for nudges?
- **E2EE**: Is standard Supabase SSL/RLS sufficient, or do you want local encryption for message content? (Instructions didn't mention E2EE, so I'll stick to RLS for now).

## Verification Plan

### Automated Tests
- `flutter test` for model serialization and real-time event parsing.
- Browser test: Verify PWA "Add to Home Screen" behavior and Web Push alerts.

### Manual Verification
1. **Chat**: Send message -> Verify auto-scroll.
2. **Reply**: Swipe on message -> Verify quoted preview appears in input bar.
3. **Stickers**: Send sticker -> Long press -> Save to collection -> Send from collection.
4. **Calls**: Initiate call -> Verify peer connection (using two browser tabs).
5. **Download**: "Save to device" on an image -> Verify file appears in downloads.
