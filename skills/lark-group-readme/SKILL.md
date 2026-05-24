---
name: lark-group-readme
description: Maintain a "ReadMe" tab for a Lark/Feishu group — a living project document attached as a chat tab that consolidates decisions, deliverables, current status, and todos from group discussion. Invoke when the user asks to "建/挂/创建 ReadMe", "把 X 写到 ReadMe", "整理群讨论到 ReadMe", "更新 ReadMe", or when responding to the daily cron card. Use the chat_id from `<bridge_context>` unless the user names a specific chat.
---

# lark-group-readme

Every group's **ReadMe** is **a single Lark docx attached as a `doc`-type chat tab** named `ReadMe`. The chat_tab points to the docx URL; the docx holds the content. `doc` type renders the document **inline inside the Feishu client** (not as an external link). Group members get `edit` permission via a chat-level permission grant.

## ⚠️ Hard rule: verify before reporting success

`lark-cli docs +create` and `docs +update --mode overwrite` **both return `ok: true` even when the markdown payload is empty** (e.g., piped from a missing or empty file). Returning success ≠ content was written.

After **every** create or update, you **must**:

1. Write the draft markdown to a file on disk (`/tmp/draft.md` for create, `/tmp/new.md` for update) — using the Write tool, not just kept in card content.
2. Assert the file is non-empty (`[ -s /tmp/draft.md ]`) before piping it into lark-cli.
3. After the call, `docs +fetch` the doc and **inspect the body** — confirm your headings/bullets actually appear, not just the title.
4. If the fetch shows an empty body: **rollback** (delete the docx for create, or re-publish the previous content for update) and tell the user the operation failed. Do **not** report success.

External users have hit "CC says it wrote everything but the doc is blank" precisely because earlier versions of this skill skipped these guards. The steps below bake them in.

## Required scopes (on the bot app)

- `im:chat` — list / create / delete chat tabs, fetch chat info
- `docx:document` — create / read / update the docx
- `drive:drive` (or `drive:file:upload` + `drive:drive`) — grant chat-level permission to the docx

If any are missing, point the user to `https://open.feishu.cn/app/<app_id>/dev-config/permission` — they tick the scope and publish a new app version.

## ReadMe target structure

```markdown
# {群名 / 项目名}

> 一句话说清这个项目要解决什么问题

## 当前状态
- 卡在哪 / 谁在跟 / 下一个 deadline

## 关键决策
- 决策 N（YYYY-MM-DD 定）：简述 + 缘由
- 推翻了 X：缘由

## 产出物
- PRD: [link]
- 设计稿: [link]

## 待办
- [ ] @张三：本周内出 v2 demo
- [ ] @李四：联调环境
```

Sections are optional — leave out what's empty. Use Lark-flavored Markdown (same as `docs +create / +update --markdown`).

## Three paths

### Path A — First-time creation

Trigger: user explicitly says "给这群建个 ReadMe" / "建个 ReadMe" in the affected group, or names the chat in p2p.

1. **Confirm no existing ReadMe tab**:
   ```bash
   lark-cli api GET /open-apis/im/v1/chats/<chat_id>/chat_tabs/list_tabs --as bot
   ```
   If a tab with `tab_name == "ReadMe"` exists, switch to Path B.

2. **Gather context**:
   - Recent messages: `lark-cli im +chat-messages-list --chat-id <chat_id> --page-size 50 --sort desc --as bot`
   - Chat name + description: `lark-cli api GET /open-apis/im/v1/chats/<chat_id> --as bot`
   - For docs referenced in messages by URL, optionally fetch titles: `lark-cli docs +fetch --doc <url> --as bot`

3. **Draft markdown** per the target structure (sections optional — leave out if no signal). **Use the Write tool to save the draft to `/tmp/draft.md`.** Do NOT keep the markdown only in your reasoning or only in card content — step 5a pipes from this file. If the file is missing or empty, the docx will be created blank but the API still returns `ok: true`.

4. **Preview card** with the draft (embed the same markdown you wrote to `/tmp/draft.md`) + a confirm button carrying `{"__claude_cb": true, "action": "create_readme"}`. **Never create the docx before confirm.**

5. **On click — execute three steps in order**:

   **5a. Create the docx & verify content was actually written**:
   ```bash
   # 1. Refuse to proceed if the draft is missing/empty.
   [ -s /tmp/draft.md ] || { echo "ERROR: /tmp/draft.md missing or empty — go back to step 3 and write the draft."; exit 1; }

   # 2. Create the docx.
   create_resp=$(cat /tmp/draft.md | lark-cli docs +create --title "<群名> · ReadMe" --markdown - --as bot)
   doc_id=$(echo "$create_resp" | jq -r '.data.doc_id')
   echo "Created doc_id=$doc_id"

   # 3. Fetch-verify: the body must contain your draft's headings/bullets, not just the title.
   lark-cli docs +fetch --doc "$doc_id" --format pretty --as bot | tee /tmp/created-readme.txt | head -40

   # 4. If the fetched body has no real content (e.g. only the title line), rollback and abort.
   if [ "$(wc -l < /tmp/created-readme.txt)" -lt 5 ]; then
     lark-cli api DELETE /open-apis/drive/v1/files/$doc_id --params '{"type":"docx"}' --as bot
     echo "ERROR: docx was created blank, rolled back. Report failure to the user — do NOT continue to 5b."
     exit 1
   fi
   ```
   Notes:
   - `lark-cli docs +create` accepts empty/missing markdown and returns `ok: true` — the assertion in step 1 + the fetch-verify in step 3 are the guards. Skipping either reproduces the "CC says created but doc is blank" failure mode.
   - `--markdown @/path` rejects absolute paths — pipe via stdin (`--markdown -`) instead.

   **5b. Grant chat-level edit permission**:
   ```bash
   lark-cli api POST /open-apis/drive/v1/permissions/<doc_id>/members \
     --params '{"type":"docx","need_notification":"false"}' \
     --data '{"member_type":"openchat","member_id":"<chat_id>","perm":"edit","perm_type":"container"}' \
     --as bot
   ```
   Without this, members will see the tab but can't open the docx.

   **5c. Attach as chat tab** (use `doc` type — renders inline in client):
   ```bash
   lark-cli api POST /open-apis/im/v1/chats/<chat_id>/chat_tabs --as bot \
     --data '{"chat_tabs":[{"tab_name":"ReadMe","tab_type":"doc","tab_content":{"doc":"https://www.feishu.cn/docx/<doc_id>"}}]}'
   ```
   **Critical**: `tab_content.doc` is a **plain URL string**, NOT a nested object like `{"url":"..."}` or `{"doc_token":"..."}` — those shapes both error with `9499 Invalid parameter type in json: doc`.
   The response contains the full tab list. Capture all `tab_id`s for step 5d.

   **5d. Move ReadMe to the 2nd position** (right after the built-in `message` tab):
   From the 5c response, build a `tab_ids` array in this order: `[<message tab_id>, <new ReadMe tab_id>, <every other tab_id in their original order>]`.
   ```bash
   lark-cli api POST /open-apis/im/v1/chats/<chat_id>/chat_tabs/sort_tabs --as bot \
     --data '{"tab_ids":["<message>","<ReadMe>","<files_resources>","<doc_list>","..."]}'
   ```
   The `message` tab is built-in and always first; ReadMe sits at position 2 so it's the first non-built-in surface users see.

   **Rollback**: if 5b/5c/5d fails after 5a succeeded, delete the orphan docx:
   ```bash
   lark-cli api DELETE /open-apis/drive/v1/files/<doc_id> --params '{"type":"docx"}' --as bot
   ```

6. **Reply in chat**: confirm creation, return the docx URL, mention "进群点 ReadMe 标签就能看到"。

### Path B — Update an existing ReadMe (smart-merge)

Trigger: "把 X 写到 ReadMe", "更新 ReadMe", "把上周聊的整理进 ReadMe", or user clicks the daily cron card's "看草稿" button.

1. **Locate existing ReadMe**:
   ```bash
   lark-cli api GET /open-apis/im/v1/chats/<chat_id>/chat_tabs/list_tabs --as bot
   ```
   Find tab where `tab_name == "ReadMe"`. Extract `tab_content.url` → parse doc_id from the trailing path segment (`https://www.feishu.cn/docx/<doc_id>`).
   - **Tab not found** → reply: "这个群还没 ReadMe，要不要先建一份？" Do NOT auto-create.

2. **Fetch current content and save for rollback**:
   ```bash
   lark-cli docs +fetch --doc <doc_id> --format pretty --as bot | tee /tmp/readme-before.md
   ```
   Keep `/tmp/readme-before.md` around — if the publish in step 6 silently produces an empty doc, you'll re-publish this as rollback.

3. **Fetch new discussion context** (same as Path A step 2).

4. **Smart-merge**: regenerate the full markdown.
   - Preserve existing structure and content
   - Integrate new info into the right sections (decisions append, superseded decisions get a strikethrough or supersession note, deliverables added, completed todos checked off)
   - When in doubt about whether to replace vs preserve, **preserve** — the user 审 diff 时再决定
   - **Use the Write tool to save the merged markdown to `/tmp/new.md`.** Step 6 pipes from this file; missing/empty file → blank doc + false success.

5. **Preview card** with:
   - Top markdown block: `## 这次改了什么` with a brief diff summary (✏️ 新增 / ✏️ 修改 / ✓ 完成的待办)
   - Second markdown block: full new content (same as `/tmp/new.md`)
   - Button: `{"__claude_cb": true, "action": "publish_readme", "doc_id": "<doc_id>"}`

6. **On click — publish & verify**:
   ```bash
   # 1. Refuse to proceed if the merged file is missing/empty.
   [ -s /tmp/new.md ] || { echo "ERROR: /tmp/new.md missing or empty — go back to step 4"; exit 1; }

   # 2. Publish.
   cat /tmp/new.md | lark-cli docs +update --doc <doc_id> --mode overwrite --markdown - --as bot

   # 3. Fetch-verify the doc now reflects the new content.
   lark-cli docs +fetch --doc <doc_id> --format pretty --as bot | tee /tmp/readme-after.md | head -40

   # 4. If the post-publish doc is suspiciously short, rollback by re-publishing the old content.
   if [ "$(wc -l < /tmp/readme-after.md)" -lt 5 ]; then
     cat /tmp/readme-before.md | lark-cli docs +update --doc <doc_id> --mode overwrite --markdown - --as bot
     echo "ERROR: update produced blank doc; rolled back to previous version. Report failure to user."
     exit 1
   fi
   ```
   `overwrite` mode replaces the whole document — fine for our use case (no comments/anchors to preserve in the typical ReadMe). Same `docs +update` empty-payload silent-success caveat applies as in Path A 5a.

### Path C — Daily cron (auto-suggestion)

Triggered by `bin/cron-readme-check.sh` once a day. The cron only posts an "要不要让我看一眼？" card; on user click, the skill enters Path B (no ReadMe → polite reply, has ReadMe → smart-merge proposal).

The cron itself never creates a ReadMe — first-time creation is always owner-initiated. This is by design (autonomous docx creation has high accident-risk).

## Card schemas

### Draft preview (Path A)

```json
{
  "schema": "2.0",
  "header": {"title": {"tag": "plain_text", "content": "📝 ReadMe 草稿 · 请确认"}, "template": "blue"},
  "body": {"elements": [
    {"tag": "markdown", "content": "<draft markdown>"},
    {"tag": "hr"},
    {"tag": "column_set", "columns": [
      {"tag": "column", "elements": [{"tag": "button",
        "text": {"tag": "plain_text", "content": "✅ 创建并挂群 Tab"},
        "type": "primary",
        "behaviors": [{"type": "callback", "value": {"__claude_cb": true, "action": "create_readme"}}]
      }]},
      {"tag": "column", "elements": [{"tag": "button",
        "text": {"tag": "plain_text", "content": "✏️ 让我改改"},
        "type": "default",
        "behaviors": [{"type": "callback", "value": {"__claude_cb": true, "action": "revise"}}]
      }]}
    ]}
  ]}
}
```

### Update preview (Path B)

Same shape with:
- Title: `📝 ReadMe 更新草稿 · 请确认`
- First markdown block: `## 这次改了什么` diff summary
- Second markdown block: full new content
- Button `value`: `{"__claude_cb": true, "action": "publish_readme", "doc_id": "<doc_id>"}`

## Common errors

| code | meaning | fix |
|---|---|---|
| `9499 Invalid parameter type in json: doc` | wrapped `doc` value in an object | `tab_content.doc` must be a plain URL string (`"doc":"https://..."`), not `{"url":"..."}` or `{"doc_token":"..."}` |
| `99992402 member_type` validation | wrong member_type value | use `openchat`, not `chat` |
| `99991672 Permission denied` | scopes not on the app | direct user to `dev-config/permission` |
| docx readable to bot but not to chat members | chat-level grant skipped | re-run the drive `/permissions/.../members` POST in 5b |

## Anti-patterns

- **Don't** report "ReadMe created" / "ReadMe updated" based on the create/update response alone. `lark-cli docs +create / +update` returns `ok: true` even for empty payloads. Always `docs +fetch` after the call and inspect the body — if it's missing your content, rollback and report failure.
- **Don't** keep the draft markdown only in your reasoning or in card content. The bash steps pipe from `/tmp/draft.md` and `/tmp/new.md` — if those files aren't written to disk, the docx will be created/updated blank and the API will silently report success.
- **Don't** auto-create a ReadMe just because cron found activity — first-time creation is owner-initiated only.
- **Don't** push docx changes without the user clicking confirm. The ReadMe is visible to every chat member.
- **Don't** create a second "ReadMe" tab — always `list_tabs` first.
- **Don't** wrap the doc URL in an object for `tab_content.doc` — it's a plain string. `{"doc":"<url>"}` works; `{"doc":{"url":"<url>"}}` and `{"doc":{"doc_token":"<token>"}}` both error.
- **Don't** fall back to `tab_type: "url"` — that renders as an external link (browser-style), not an inline doc panel. Use `doc`.
- **Don't** forget step 5b (chat-level permission grant) — without it, the tab is broken from a member's POV.
