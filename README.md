# 日课 Rike

**一张「工」字表，把一天收进一页。**
*One 工-shaped sheet that holds a whole day.*

[中文](#中文) · [English](#english)

macOS 原生应用 · Swift 6 + SwiftUI · 零第三方依赖 · 数据不出本机
*Native macOS · Swift 6 + SwiftUI · zero third-party dependencies · your data never leaves the machine*

```
┌────────────────────────────────────────────────────┐
│  上横  今日 TODO          TODO for today           │  ← 定方向 / set direction
│        ⌂ 下限   ★ 最重要   2 · 3 · 4 …             │
└────────────────────────────────────────────────────┘
      ┌──────────────────────────────────────┐
      │  时间轴  00 ─── 06 ─── 12 ─── 18 ──  │
      │  中竖    计划 ▒▒▒   ▒▒▒▒             │  ← 对照 / compare
      │          实际 ███     ██████         │
      ├───────────────────┬──────────────────┤
      │  计划 Planned     │  实际 Actual     │
      │  09:00 至 11:30   │  09:12 至 11:05  │
      └───────────────────┴──────────────────┘
┌────────────────────────────────────────────────────┐
│  下横  今日总结          Today in review           │  ← 收回来 / close the loop
│        触动 · 成功日记 · 明天会更好 · 模糊清单      │
└────────────────────────────────────────────────────┘
```

---

## 中文

### 为什么是「工」字

「工」字的三笔就是一天的三个动作，形不是装饰，是结构：

| 位置 | 内容 | 它回答的问题 |
|---|---|---|
| **上横**（通栏） | 今日 TODO | 今天往哪儿走？ |
| **中竖**（内缩） | 计划 ｜ 实际 | 想的和做的差在哪儿？ |
| **下横**（通栏） | 今日总结 | 今天留下了什么？ |

上下两横通栏、中间内缩，屏幕上自然立出一个「工」字。
上横定方向，中竖做对照，下横收回来——一天从开头走到结尾，一页读完。

### 上横 · 今日 TODO

- **下限单独一行**，不混在 TODO 里。下限不一定是工作，比如「今天必须在 23:00 前睡觉」——
  那不是一件要做的事，是今天无论如何要守住的线，塞进工作清单会被淹掉。
- **顺序即优先级**。第一条自动标 ★，拖动即调整。不另设优先级字段——
  位置本身就是判断，再让人手动打一个标记等于问了两遍。

### 中竖 · 计划 ｜ 实际

左右两列同轴并排，上方一条横排时间轴把两者叠在一起看：上轨计划，下轨实际。

- **计划**是意图，用虚线描边；**实际**是事实，用实心填充。
  这比多找一个色相更能一眼分清左右，而且这个区别本身有意义。
- **实际的时间可以留空**（`__:__`）。开完会回来补录、晚上回顾一整天时，
  当前时刻和那件事发生的时刻毫无关系，替你猜一个「现在起一小时」几乎总是错的。
- 时间随时可改，改完自动按时间排序——不用电脑的那几个小时，回来补就是了。
- 时间轴走 **elapsed 轴**而不是墙钟轴：秋令时当天 01:30 出现两次，
  墙钟轴会把两个不同的真实区间画到同一个位置。

### 下横 · 今日总结

| 栏目 | 记什么 |
|---|---|
| **触动** | 今天最触动的一件事，好坏都算，写细 |
| **成功日记** | 3~5 条自己做成的小事（灵感来自《小狗钱钱》）。回车落一条，接着记下一条 |
| **明天会更好** | 怎么调整，让明天做得更好 |
| **模糊清单** | 卡住的位置 → 真正想逃开的 → 最坏情况 → 明天 30 分钟内的第一步 |

「模糊清单」是把一件说不清的烦心事拆成四栏。说不清的时候人会逃，
拆完往往发现要逃的不是那个问题本身。

### 另外两个页签

- **仪表盘**：计划与实际的差、软件使用时长。给「上次中断的日期」，**不给连续天数**。
- **阻断器**：注意力被劫持时按一下，记录触发器和当时真正想逃开的事。

### 四条写死的产品原则

来自周岭《认知觉醒》。这是产品约束，不是风格：

1. **用记录代替打卡** —— 不显示连续天数。
2. **设下限不设上限** —— 下限的标准是「再累也做得到」。
3. **少即是多** —— 下限限一条，约束写进数据模型。
4. **中性不评价** —— 状态是「已完成／未记录」，没有 ✓ ⚠ 和鼓励语。

理由：打卡 → 认知闭合 → 应付 → 放弃 → 愧疚，而愧疚正是失控的燃料。
一个做成打卡的 app 会亲手把使用者送回失控。

### 数据与导出

- 每天一个 JSON，存在 `~/Library/Application Support/com.ybjv.gong/`。
- **导出是手动的**：⌘E 或点日期左边的按钮，导出当前界面那一天，
  文件名 `2026-09-01-daily-record.md`。
- 导出**宁可不写，绝不覆盖**：目标已存在时必须同时满足「有生成标记」和
  「内容 hash 等于上次导出值」才替换，否则另存 `*.gong-conflict.md`，原文件一字不动。

### 快速开始

```bash
./scripts/build.sh      # 编译 + 组装 .app + ad-hoc 签名 → build/Rike.app
./scripts/install.sh    # 安装到 /Applications
swift test              # 163 项单元 / 集成测试
```

要求 macOS 14+。无 Dock 图标（`LSUIElement`），从菜单栏「工」图标进主窗口；
主窗口打开时会临时出现 Dock 图标，方便切窗口。

**快捷键**：⌘← / ⌘→ 前后一天 · ⌘T 回到今天 · ⌘E 导出当天

界面支持中文 / English、浅色 / 深色，以及四套主题（工务 · 宣纸 · 石墨 · 松墨）。

---

## English

### Why the character 工

*工* (gōng) is written with three strokes — and they map onto the three moves of a day.
The shape isn't decoration; it's the structure:

| Stroke | Content | The question it answers |
|---|---|---|
| **Top bar** (full width) | Today's TODO | Where am I going today? |
| **Middle stem** (inset) | Planned ｜ Actual | Where did intent and reality diverge? |
| **Bottom bar** (full width) | Today in review | What did today leave behind? |

Full-width top and bottom, inset middle — the layout draws a 工 on screen.
Set direction, compare, close the loop. One page, beginning to end.

### Top bar · Today's TODO

- **The floor gets its own line**, separate from the TODO list. A floor isn't necessarily work —
  "lights out before 23:00" isn't a task, it's a line you hold no matter what.
  Buried in a work list, it drowns.
- **Order is priority.** The first item is automatically marked ★; drag to reorder.
  There's no separate priority field — position already is the judgment, and asking
  for a second marker is asking the same question twice.

### Middle stem · Planned ｜ Actual

Two columns side by side, with a horizontal timeline above that overlays them:
planned on the upper track, actual on the lower.

- **Planned is intent** — dashed outline. **Actual is fact** — solid fill.
  That reads faster than another hue, and the distinction itself carries meaning.
- **Actual times may be left blank** (`__:__`). When you're logging after the fact —
  back from a meeting, reviewing at night — the current clock has nothing to do with
  when the thing happened, so guessing "now, plus an hour" is almost always wrong.
- Times stay editable and re-sort themselves. The hours you spend away from the
  computer get filled in when you get back.
- The timeline runs on an **elapsed axis**, not a wall-clock one: on a fall-back DST day
  01:30 happens twice, and a wall-clock axis would draw two different real intervals
  in the same place.

### Bottom bar · Today in review

| Field | What goes in it |
|---|---|
| **Moved me** | The one thing that moved you today — good or bad. Be specific |
| **Wins** | 3–5 small things you actually got done (after *Ein Hund namens Money*). Press return, log the next |
| **Better tomorrow** | What to change so tomorrow goes better |
| **Fog list** | Where you're stuck → what you're really avoiding → worst case → first 30-minute step tomorrow |

The fog list breaks one vague, nagging thing into four columns. Vagueness is what makes
people flee; once it's broken down, the thing you were fleeing usually turns out not to be
the problem itself.

### Two more tabs

- **Dashboard** — planned vs. actual, time per application. It shows *the date you last
  broke the chain*, and deliberately **never a streak count**.
- **Breaker** — one press when your attention gets hijacked; logs the trigger and what
  you were actually trying to escape.

### Four product rules that don't bend

From *Cognitive Awakening* (Zhou Ling). These are constraints, not styling:

1. **Record, don't check in** — no streak counters.
2. **Set a floor, not a ceiling** — a floor is something you can do on your worst day.
3. **Less is more** — one floor per day, enforced in the data model.
4. **Neutral, never graded** — states are "done / not recorded". No ✓, no ⚠, no cheering.

Why: check-in → closure → going through the motions → quitting → guilt — and guilt is
exactly what fuels the next loss of control. An app built as a habit tracker would
personally walk its user back into it.

### Data and export

- One JSON per day under `~/Library/Application Support/com.ybjv.gong/`.
- **Export is manual**: ⌘E, or the button left of the date. It exports the day currently
  on screen, as `2026-09-01-daily-record.md`.
- Export **would rather not write than overwrite**: when the target exists, it's replaced
  only if it carries the generated marker *and* its content hash matches the last export.
  Otherwise the content goes to `*.gong-conflict.md` and the original is left untouched.

### Quick start

```bash
./scripts/build.sh      # compile + assemble .app + ad-hoc sign → build/Rike.app
./scripts/install.sh    # install to /Applications
swift test              # 163 unit / integration tests
```

Requires macOS 14+. No Dock icon by default (`LSUIElement`) — open the main window from
the 工 icon in the menu bar. While that window is open a Dock icon appears, so you can
⌘-tab back to it.

**Shortcuts**: ⌘← / ⌘→ previous / next day · ⌘T today · ⌘E export the current day

Chinese / English, light / dark, and four themes (Structural · Paper · Graphite · Pine).

---

## 项目结构 Layout

```
Sources/GongCore/     # 全部实现，可 @testable import
  Model/              # 数据模型与不变式        data model and invariants
  Support/            # 时间工具、时间轴投影     time utilities, timeline projection (pure)
  Store/              # 原子写、导出、设置       atomic writes, export, settings
  Monitor/            # 前台应用监控 + reducer   foreground app monitor + reducer
  Breaker/            # 注意力阻断器             the attention breaker
  UI/                 # SwiftUI 视图             SwiftUI views
  App/                # AppDelegate、协调器      AppDelegate, coordinator
Sources/Rike/         # 两行进程入口             two-line entry point
Tests/GongCoreTests/  # 163 项测试               163 tests
prototype/            # HTML 视觉原型            HTML visual prototypes
scripts/              # 构建、安装、配色核对       build, install, contrast check
```

## 许可 License

尚未确定。在此之前保留所有权利。
Not yet decided. All rights reserved until then.
