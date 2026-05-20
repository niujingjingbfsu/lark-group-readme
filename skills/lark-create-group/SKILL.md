---
name: lark-create-group
description: Create a Lark/Feishu group chat, invite members, optionally seed an initial ReadMe (delegating to `lark-group-readme`). Invoke when the user asks to "拉一个群 / 建群 / 开个群 把 A、B 加进来聊 X" or similar.
---

# lark-create-group

Creates a group chat via `lark-cli im +chat-create`, invites members, sends a one-line opener, and (if the user asks) hands off to `lark-group-readme` to seed a project ReadMe.

## Required scopes (on the bot app)

- `im:chat` — create chat + invite
- `im:chat.members:create` — invite members (implicit in `im:chat`)
- (Optional, only if seeding a ReadMe) the scopes listed in `lark-group-readme/SKILL.md`

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
5. **Seed ReadMe** (if user asked for it): hand off to `lark-group-readme` (Path A) with the requested content as initial context.

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

- Don't create a group and immediately seed a long ReadMe before the members can see/dismiss invitations. If seeding, send a short opener first; the ReadMe pass can wait until members are in.
- Don't create groups silently — always echo back the group name, chat_id, and member roster so the user can sanity-check.
