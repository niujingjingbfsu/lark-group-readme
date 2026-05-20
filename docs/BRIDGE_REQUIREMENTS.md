# 实时版 ReadMe 感知 —— 给 lark-channel-bridge 的需求

> 这份文档不是 lark-group-readme 自己能落地的功能，需要 **lark-channel-bridge 本体**配合改造。
> 写给 bridge 那边的开发者 / agent，作为提需求的输入。

---

## 1. 背景

Group ReadMe 的核心机制是：把群里讨论的关键信息持续沉淀到一份挂在群 Tab 的飞书云文档里。这份文档不能自动更新——必须由 agent 起草、owner 点确认才写入。

当前的"自动检查"是 **cron pull 模型**：

- `bin/cron-readme-check.sh`（重构前叫 `cron-announcement-check.sh`）每天 09:07 跑一次
- 对配置在 `groups.conf` 里的群，主动拉过去 24h 的消息
- 消息量够多就发卡片邀请 owner 起草 ReadMe 更新

**目标形态**是 **事件 + 静默窗口的准实时模型**：群里讨论刚告一段落，agent 就主动跳出来提议 ReadMe 更新——而不是要等到第二天早上。

从产品视角，用户感知的差别是：

| 当前 | 目标 |
|---|---|
| 每天早上看报纸的秘书 | 一直在群里听着的同事 |
| 昨天的事今早提醒 | 讨论刚结束几分钟就提醒 |

---

## 2. 产品形态（用户视角）

1. 群里讨论进行中 —— agent 安静，不打断
2. 讨论告一段落（约 15 分钟没新消息） —— agent 在后台 **判断这段讨论是否值得沉淀到 ReadMe**
3. 值得 → 发一张草稿卡片到群里：「这段讨论我整理了一份 ReadMe 更新草稿，要不要看看？」
4. 不值得 → 完全静默，不发任何东西
5. 同一群 4 小时内不会重复提议（克制机制）

用户**永远不会看到**："webhook"、"事件订阅"、"静默窗口"、"buffer" 这些字眼。

---

## 3. 对 bridge 的具体依赖

### 依赖 1：扩展事件订阅范围

**现状假设**：bridge 当前已订阅 `im.message.receive_v1`，但消息处理逻辑只在 **bot 被 @ 或 p2p 私聊** 时才唤起 claude session。

**需求**：

- 对**配置在白名单里**的群，**所有消息**（包括非 @ 的纯讨论消息）都要被 bridge 捕获
- 飞书 app 后台的事件订阅范围可能需要扩展，由 bridge owner 在飞书应用后台开启
- 白名单之外的群保持现状不变（不要全局打开，否则成本和噪声都不可控）

**消息类型最低支持**：`text`, `post`, `merge_forward`, `share_calendar_event`, `file`（带链接的产出物）

### 依赖 2：per-chat 消息缓冲区

每个白名单群维护一个消息缓冲队列。

- **存储**：持久化到磁盘（sqlite 或文件均可），bridge 重启不丢
- **字段**：至少包含 `msg_id`、`sender_id`、`sender_name`、`content`、`message_type`、`created_at`
- **保留时长**：判断完一次后清空（或标记 consumed），避免重复消费
- **大小上限**：单群单窗口建议 ≤ 200 条，超过的截断保留最新

### 依赖 3：静默窗口触发器（替换 cron）

bridge 内常驻一个轻量 daemon（goroutine / 协程均可），不再依赖 crontab。

**触发条件**（对每个白名单群独立判断）：

```
let now = 当前时间
let last_msg = 该群最后一条入队消息的时间
let last_check = 该群上次触发判断的时间
let cooldown = 4 小时

if (now - last_msg >= 15min)            # 静默窗口
   AND (last_msg > last_check)          # 有新消息可消费
   AND (now - last_check >= cooldown)   # 冷却期已过
then 触发判断
```

**扫描频率**：每 1 分钟一次足够（不要更高，无意义）

**参数应可配置**：静默窗口 / 冷却时长建议从配置文件读，缺省 `15min` / `4h`。

### 依赖 4：触发入口契约

触发时，bridge 调用 lark-group-readme 的 **"判断 + 起草"入口**。

**推荐实现：spawn claude 进程**（跟当前 cron 脚本的模型一致）：

```bash
claude --print --append-system-prompt "<readme-check-prompt>" <<EOF
chat_id: <群 id>
chat_name: <群名>
window_start: <ISO 时间>
window_end: <ISO 时间>
messages:
<JSON 数组或 NDJSON：缓冲区内的消息>
EOF
```

- claude 进程负责：判断是否值得沉淀 → 如值得，拉 ReadMe 文档现状 → 起草增量更新 → 发卡片到该群
- claude 进程负责：如不值得，**直接退出，不发任何消息**
- bridge 只负责：spawn、等待退出、记录 `last_check = now`

**bridge 不需要知道判断逻辑、不需要知道 ReadMe 结构** —— 那都是 lark-group-readme 这边 SKILL.md 的事。

### 依赖 5：白名单管理

复用现有的 `bin/groups.conf` 格式即可（一行一个 chat_id），bridge 启动时读取，支持 SIGHUP 热重载（可选）。

未来可考虑让 owner 通过 p2p 跟 agent 说「把 XX 群加入监控」来动态增删，那是 lark-group-readme 这边可以做的事，需要 bridge 提供一个写白名单的口子。**第一版不需要**。

### 依赖 6：与正常对话流的隔离

**重要**：静默窗口触发的 claude 进程和"用户 @ agent"触发的 claude session 必须**完全独立**：

- 不共享 conversation 状态
- 不会互相打断
- 如果某群正好有人 @ agent 在对话，**该群的静默窗口触发要跳过这次**（避免两条腿打架）

最简单的实现：用 file lock / chat-id-级别的 mutex。bridge 这边已经有类似机制（一个 chat 同时只跑一个 claude session），复用即可。

---

## 4. 验收标准

**场景 1：触发**
1. 在白名单群里连续发 5 条非 @ 的讨论消息
2. 然后 15 分钟不说话
3. **预期**：bridge 自动 spawn claude；claude 判断后或起草 ReadMe 更新或静默；行为日志可见

**场景 2：克制**
1. 触发一次之后，4 小时内再在该群发 5 条消息 + 15 分钟静默
2. **预期**：不触发（冷却中），但消息正常进缓冲

**场景 3：隔离**
1. 群里讨论 5 条后 14 分钟，有人 @ agent 问别的事
2. **预期**：正常对话流走通，且这次静默窗口触发被跳过

**场景 4：重启不丢**
1. 缓冲了 10 条消息后 bridge 重启
2. **预期**：消息缓冲完好，静默窗口照常计时

---

## 5. 不在本次范围内

- **修改 agent 的判断/起草逻辑** —— 是 lark-group-readme 这边 SKILL.md 的工作
- **飞书 app 权限申请** —— 由 lark-group-readme owner 在飞书开发者后台完成
- **跨群关联**（一个项目涉及多个群的合并感知） —— 留给未来
- **更智能的"讨论结束"判断**（基于内容而不仅是时间静默） —— 留给未来

---

## 6. 落地后 lark-group-readme 这边要做的事（对照）

为了不让 bridge 团队孤军，列出 lark-group-readme 这边对应要改的部分（**不在本文档要求范围内，仅做对照**）：

- 退役 `bin/cron-readme-check.sh`、从 crontab 移除
- 新增一个 SKILL 入口（或 prompt 文件），专门处理"窗口消息 → 判断 + 可选起草"
- 调整 `skills/lark-group-readme/SKILL.md`，让它能消费"窗口消息"作为输入源

---

## 7. 联系人

- lark-group-readme owner：项目 README 里有
- 本文档持续更新：[lark-group-readme/docs/BRIDGE_REQUIREMENTS.md](./BRIDGE_REQUIREMENTS.md)
