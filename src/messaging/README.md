# Marketplace messaging

This module adds one-to-one customer/seller conversations, text and file attachments, timestamps, read receipts, live presence, unread counts, search, per-user conversation deletion, blocking and message reports.

## Database migration

Run **only** `src/messaging/message.sql` in the Supabase SQL Editor for this feature. It is an incremental, rerunnable migration; it does not ask you to rerun the existing authentication, homepage, seller, orders or payments migrations.

It expects the existing `profiles` and `products` tables. The migration creates the messaging tables, policies, RPC, private attachment bucket and Realtime publication entries.

## Usage

- Customers can start a conversation from a product detail page using **Message seller**.
- Sellers can open **Messages** in their seller portal and reply.
- Sellers can also start a conversation from the Customers section of their portal.
- Customers can open **Messages** from the marketplace navigation.
- Attachments are private and are opened using short-lived signed URLs. Maximum upload size is 10 MB; supported types are JPEG, PNG, WebP, PDF and plain text.
- Conversation deletion hides it only for the deleting participant.
- Blocks apply in either direction. Message reports are stored for administrator review.

## Realtime

Enable Supabase Realtime for the `messages` and `conversations` tables if the project does not already publish them. Online presence is shown while a user has the relevant conversation open.

## Security

Row Level Security limits conversation/message access to the two participants. Profile visibility is extended only to the counterpart in an existing conversation. Attachments use a private Storage bucket. Message content cannot be edited after sending; recipients can update only the read timestamp.
