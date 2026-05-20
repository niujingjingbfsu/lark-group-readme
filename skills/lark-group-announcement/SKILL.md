---
name: lark-group-announcement
description: Read, write, or reorder a Lark/Feishu group's announcement (docx-type). Invoke when the user asks to "把 X 写到群公告 / 改群公告 / 更新群公告 / 重排公告" or similar — both in p2p and inside the affected group. Use the chat_id from `<bridge_context>` unless the user names a specific chat.
---

# lark-group-announcement

Modern Lark group announcements are **docx documents** under the chat. The legacy `/open-apis/im/v1/chats/.../announcement` endpoint returns `[232097] Unable to operate docx type chat announcement` — use the `docx/v1` paths instead.

## Required scopes (on the bot app)

- `im:chat.announcement:read` — read
- `im:chat.announcement` — write

These **cannot be self-applied via API**. If missing, point the user to:
`https://open.feishu.cn/app/<app_id>/dev-config/permission` — they have to tick the scope and create a new app version.

## Endpoints (all `--as bot`)

```
GET    /open-apis/docx/v1/chats/{chat_id}/announcement                                      # metadata
GET    /open-apis/docx/v1/chats/{chat_id}/announcement/blocks/{block_id}/children           # list children
POST   /open-apis/docx/v1/chats/{chat_id}/announcement/blocks/{block_id}/children           # append children
DELETE /open-apis/docx/v1/chats/{chat_id}/announcement/blocks/{block_id}/children/batch_delete  # delete by index range
PATCH  /open-apis/docx/v1/chats/{chat_id}/announcement/blocks/batch_update                  # reorder / in-place edit (preferred over delete+repost)
```

**Convention**: the root `block_id` equals the `chat_id`. Pass `chat_id` wherever the parent block is needed.

## Block schema cheatsheet

| `block_type` | meaning | nested field |
|---|---|---|
| 2  | text paragraph | `text` |
| 4  | heading2 | `heading2` |
| 5  | heading3 | `heading3` |
| 12 | bullet list item | `bullet` |
| 13 | ordered list item | `ordered` |

Each container holds `{elements: [...], style: {}}`. Elements are usually `text_run`:

```json
{"text_run": {
  "content": "PRD",
  "text_element_style": {
    "link": {"url": "<URL-encoded URL>"},
    "bold": true
  }
}}
```

**The URL must be percent-encoded** (e.g. `https%3A%2F%2F...`). Plain URLs break the link.

## Workflow

1. **Pull context**: messages via `lark-cli im +chat-messages-list --chat-id <chat_id> --page-size 50 --sort desc`; any referenced docs via `lark-cli docs +fetch --doc <url>`.
2. **Draft**: organize into 讨论主题 / 沉淀产出 / 当前进展 (or whatever structure the user requested). Surface dates as bullet leads, link docs by title not raw URL.
3. **Preview as card**: send a CardKit 2.0 interactive card with the draft (use `markdown` element) plus a `✅ 发布到群公告` button carrying `{"__claude_cb": true, "action": "publish_announcement"}`. **Never push without confirmation.**
4. **Write on click**: when `[card-click] {"action":"publish_announcement"}` arrives, build blocks and POST to `.../children`.
5. **Reorder**: prefer `batch_update` with `block_move_after` over delete-all + repost — moves preserve block_ids, which keeps comments/attachments anchored. Only use delete+repost when the announcement is empty or has no anchors.
6. **Verify**: re-GET metadata; `revision_id` should bump (e.g. 1 → 2 for first write).

## Helper

`build_blocks.py` (sibling file) converts a Python list of (type, elements) tuples into the POST payload. Import and reuse it; don't re-derive URL-encoding logic.

```python
from build_blocks import heading2, para, bullet, text_run
children = [
    heading2("讨论主题"),
    para([text_run("一句话定义...")]),
    heading2("沉淀产出"),
    bullet([text_run("PRD：", bold=True), text_run("方案文档", link="https://...")]),
]
# json.dumps({"children": children, "index": -1})
```

## Sending the draft card

```bash
lark-cli im +messages-send \
  --chat-id <chat_id> --msg-type interactive \
  --content "$(cat /tmp/card.json)" --as bot
```

Card skeleton (CardKit 2.0):

```json
{
  "schema": "2.0",
  "header": {"title": {"tag": "plain_text", "content": "群公告草稿 · 请确认"}, "template": "blue"},
  "body": {"elements": [
    {"tag": "markdown", "content": "<draft markdown>"},
    {"tag": "hr"},
    {"tag": "button",
     "text": {"tag": "plain_text", "content": "✅ 发布到群公告"},
     "type": "primary",
     "behaviors": [{"type": "callback", "value": {"__claude_cb": true, "action": "publish_announcement"}}]}
  ]}
}
```

## Common errors

| code | meaning | fix |
|---|---|---|
| `232097 Unable to operate docx type` | called the legacy `im/v1` announcement endpoint | switch to `docx/v1/chats/.../announcement/...` |
| `99991672 Permission denied` with `im:chat.announcement:*` | scopes not yet on the app | direct user to `dev-config/permission` |
| `batch_update` rejects `block_move_after` | destination not in the same parent | can only reorder siblings, not move across parents |

## Anti-patterns

- **Don't** call `im/v1/chats/.../announcement` — it only works for legacy text-format announcements and almost no modern group has those.
- **Don't** delete-all + repost for reorders on announcements with comments/attachments — block_ids change and bindings break.
- **Don't** push without the user clicking confirm. Announcements are visible to every group member.
