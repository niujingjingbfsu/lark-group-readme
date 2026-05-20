# Group ReadMe

**让每个飞书群都有一份会自己更新的 README。**

一个 Claude Code Skill 包，让 AI agent 把飞书群打理成项目的活档案：群里讨论的关键信息——决策、产出物、当前进展、待办——自动沉淀到一份挂在群 Tab 的飞书云文档里。这份文档随群里讨论的演进持续更新。

---

## 我们想解决什么问题

飞书群本来就是项目协作的天然容器：决策在这里发生、产出物在这里分享、人在这里出现。但群有一个根本性的问题——**所有信息都在时间流里流走了**。

### 群聊天记录的根本困境

群里发生过这些事：

- 上周三定了 v2 方案，推翻了 v1
- 设计稿在小张那条消息里，深埋第 380 楼
- "其实那个 deadline 又推迟了"——某次会后口头说的
- 项目背景 PRD 在某次置顶里，但置顶后来被换掉了

**新人进群第一件事**：往上翻 500 条消息。
**老人想确认一个细节**：往上翻 500 条消息。
**离开三天回来**：往上翻 500 条消息。

群聊天记录就是"按时间无情往下流"的数据结构——**它没有"当前状态"**。

### 群公告 / 置顶都救不了

理论上群公告该承担"当前状态"的角色。但大家都知道——它一旦写好就再也没人动了。

为什么？因为改一句话要走 6 步：

> 进群 → 点群头像 → 设置 → 群公告 → 编辑 → 保存

每一次都不致命，但累积起来没人愿意做。所以公告永远停在群创建那天的样子。

---

## 我们的解决方式

让 AI agent **持续把群里讨论的关键信息沉淀到一份文档**。这份文档挂在群 Tab 上，叫 **ReadMe**——名字直接借自 GitHub 项目的 README，意思一样：**进群第一眼能看到的、这个项目当前是什么状态、谁在做什么、产出物在哪**。

### ReadMe 是什么样的

一份飞书云文档，结构大致是：

```
# 项目名

> 一句话说清这个项目要解决什么问题

## 当前状态
- 卡在哪、谁在跟、下一个 deadline 是哪天

## 关键决策
- v2 方案（2025-05-18 定）
- 推翻了 v1，原因是 XX

## 产出物
- PRD: [link]
- 设计稿: [link]
- 演示视频: [link]

## 待办
- [ ] 张三：本周内出 v2 demo
- [ ] 李四：联调环境准备
```

这份文档挂在群 Tab 的 **ReadMe** 标签下——进群一眼看到，点开就读。

### 它是怎么"自己更新"的

AI agent **持续地** 消费群里的讨论，三种触发方式：

| 触发方式 | 例子 |
|---|---|
| 用户直接点名 | "把刚才决定的方案 v2 写到 ReadMe 的关键决策里" |
| 用户让它整理一段 | "把我们群上周聊的内容整理进 ReadMe" |
| agent 自己感知 | 讨论结束后主动发卡片："这段讨论里有新结论 / 新产出物，要不要让我整理一份 ReadMe 更新？" |

每次更新都是 **agent 起草 → 给你看 diff → 你点确认 → 才真正写入文档**。

### 核心约束：永远不自动发布

ReadMe 对群里所有人可见，所以 AI 不能自己改自己发。所有路径收敛到同一个模式：

> **起草 → 卡片预览 → 用户点确认 → 才真正写入**

用户不点，文档里什么都不会变。这是设计上的红线。

---

## 两个 skill

| Skill | 类型 | 做什么 |
|---|---|---|
| `lark-create-group` | 一次性动作 | 用一句话建群：建群 + 加人 + 发开场白 |
| `lark-group-readme` | 多入口持续维护 | 创建 ReadMe 文档、挂群 Tab、消费群讨论持续更新 |

详见各自目录下的 `SKILL.md`。

---

## 当前实现 / 未来形态

### 当前：cron + pull，每天一次

cron 脚本每天 09:07 跑一次，对配置在白名单里的群拉过去 24 小时的消息，超过阈值就发卡片到群里邀请 owner 起草 ReadMe 更新。

**离线、每日、拉模型**，跟 bridge 解耦，工程简单。

### 未来：事件驱动 + 静默窗口

更理想的形态是：群里讨论刚告一段落（约 15 分钟没新消息），agent 就在后台判断是否值得更新 ReadMe。用户感知层面，"每天一次"变成"刚讨论完就提议"。

这需要 lark-channel-bridge 本体配合。完整需求清单见 [`docs/BRIDGE_REQUIREMENTS.md`](./docs/BRIDGE_REQUIREMENTS.md)。

---

## 怎么用 / 自己装一份

依赖：

- **Claude Code** — 运行 agent
- **lark-channel-bridge** — 把飞书消息桥到 agent
- **lark-cli** — 飞书 API 命令行工具
- 一个飞书 bot 应用，需要的 scope：
  - `im:chat`（群信息）
  - `docx:document`（创建 / 编辑云文档）
  - `im:chat:writeonly` 或同类（操作群 Tab）

安装：

```bash
git clone https://github.com/niujingjingbfsu/lark-group-readme.git
cp lark-group-readme/skills/* ~/.claude/skills/
cp lark-group-readme/bin/groups.conf.example lark-group-readme/bin/groups.conf
# 编辑 groups.conf，列出要监控的群 chat_id
crontab -e   # 加一行：7 1 * * * /path/to/lark-group-readme/bin/cron-readme-check.sh
```

我们自己跑了一个叫 **Seraphina** 的实例供内部使用——你可以装一份同样的，起任何你喜欢的名字。

---

## 贡献 / Issue

欢迎在 GitHub 提 Issue / PR：https://github.com/niujingjingbfsu/lark-group-readme
