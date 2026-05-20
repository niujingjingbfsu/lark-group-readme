---
name: lark-create-group
description: Create a Lark/Feishu group chat, invite members, optionally seed an initial announcement. Invoke when the user asks to "拉一个群 / 建群 / 开个群 把 A、B 加进来聊 X" or similar.
---

# lark-create-group

Creates a group chat via `lark-cli im +chat-create`, invites members, and optionally writes a starter announcement (delegating to the `lark-group-announcement` skill).

## Required scopes (on the bot app)

- `im:chat` — create chat + invite
- `im:chat.members:create` — invite members (implicit in `im:chat`)
- (Optional, only if seeding an announcement) `im:chat.announcement` + `im:chat.announcement:read`

## Workflow

1. **Gather inputs**: group name, list of members. Members can be specified by open_id (`ou_...`), email, or display name.
2. **Resolve names → open_id** if the user gave names: `lark-cli contact +search-user --query "<name>" --as bot`. If multiple matches, ask the user to disambiguate; don't guess.
3. **Create the group**:
   ```bash
   lark-cli im +chat-create \
     --name "<group name>" \
     --description "<one-line purpose>" \
     --user-ids "ou_xxx,ou_yyy" \
     --as bot
   ```
   Returned `chat_id` is what subsequent calls need.
4. **Verify membership** (optional but cheap):
   `lark-cli im chat.members --chat-id <chat_id> --as bot` — confirm members are present.
5. **Seed announcement** (if user asked for it): hand off to `lark-group-announcement` with the requested content.

## UX

- **Confirm before creating** when names are ambiguous, the member list is long (>5), or the group is cross-tenant/public.
- After creation, send the new `chat_id` and a `lark://im?chat_id=...` deep link in your reply so the user can jump in.
- If the user is already in the chat where this skill was invoked, **don't invite them to the new group as themselves** — they're already implicit.

## Common errors

| code | meaning | fix |
|---|---|---|
| `230002` (or similar) Invalid user_id | one of the open_ids is wrong / from another tenant | re-resolve via `contact +search-user` |
| `230020` Member out of app's availability | the bot isn't allowed to add that user | check the app's "可用范围" in dev-config |

## Anti-patterns

- Don't create a group and immediately spam an announcement before the members can see/dismiss invitations.
- Don't create groups silently — always echo back the group name, chat_id, and member roster so the user can sanity-check.
