<p align="center">
  <picture>
    <img alt="OpenOmniBot" src="docs/pic/OmniBot.png" width="50%">
  </picture>
</p>

<h3 align="center">
你的端侧 AI 助手
</h3>

<div align="center">
  <img alt="GitHub Repo stars" src="https://img.shields.io/github/stars/omnimind-ai/OpenOmniBot">
  <a href="https://github.com/omnimind-ai/OpenOmniBot/releases/latest"><img alt="GitHub Release" src="https://img.shields.io/github/v/release/omnimind-ai/OpenOmniBot"></a>
  <br>
  <a href="https://omnimind.com.cn"><img src="https://img.shields.io/badge/About_us-万象智维-purple.svg?color=%234b0c77" alt="万象智维"></a>
  <a href="https://linux.do"><img src="https://img.shields.io/badge/Linux_Do-社区-yellow.svg?color=%23ac3712" alt="LinuxDo社区"></a>
  <a href="#其他">
    <img src="https://img.shields.io/badge/WeChat-微信群-lightgreen" alt="微信群"/>
  </a>
</div>

<p align="center">
| 
<a href="#-demo"><b>Demo</b></a> 
| 
<a href="#-快速开始"><b>Quick Start</b></a> 
| 
<a href="https://github.com/omnimind-ai/OpenOmniBot/releases"><b>Release</b></a> 
|
<a href="https://github.com/omnimind-ai/OmniInfer-LLM/issues"><b>Issues</b></a> 
|
</p>

## ✨ 项目简介
OpenOmniBot 是一个基于 Android 原生与 Flutter 混合架构的智能机器人助手应用。
与传统 AI App 不同，它关注的是：**从理解 → 决策 → 执行 → 反馈的完整闭环**, 是一个 Android 端真正可"执行"的 Agent。

## 🧠 核心能力：

- 🧩 **工具生态扩展**：Skills、Alpine 系统、浏览器、MCP、安卓系统工具...

- 📱 **手机任务自动化**：支持用视觉模型操作手机界面。

- ⏰ **系统级能力**：支持定时任务、闹钟提醒、日历事件创建/查询/修改、音频播放控制。

- 🧬 **记忆系统**：短期与长期记忆嵌入。

- 🔨 **生产力工具**：支持读写文件、浏览工作区、调用浏览器、调用终端。


## 🚀 开发指南

### 环境要求

- Flutter SDK (3.9.2+)
- JDK 11+

### 获取代码

```bash
git clone https://github.com/omnimind-ai/OpenOmniBot.git
cd OpenOmniBot

#安装 Flutter 依赖
cd ui
flutter pub get
```

### 构建并安装
```bash
cd .. # 回到根目录下
./gradlew :app:installDevelopDebug
```

## 🎮 快速开始

<div align="center">
  <img src="https://img.shields.io/badge/难度-新手友好-brightgreen" alt="难度"/>
  <img src="https://img.shields.io/badge/关卡-4_Levels-blue" alt="关卡"/>
  <img src="https://img.shields.io/badge/预计用时-15_min-orange" alt="预计用时"/>
</div>

<br>

> 欢迎来到小万的世界！这份闯关指南带你一步步解锁小万的全部实力。
> 每关三步：**📍 去哪找** → **🔧 做什么** → **✅ 怎么验证**。四关通关，你就是小万的最强召唤师！

---

### <img src="https://img.shields.io/badge/Level_1-核心引擎点火-critical" alt="Level 1"/> 模型提供商 (Provider) —— 给小万装上大脑

> 📍 **去哪找：** `设置` → `模型提供商`

**🔧 做什么：**

填入你的 LLM 服务商信息，让小万拥有思考能力。以阿里云百炼为例：

| 配置项 | 值 |
|-------|-----|
| **API URL** | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| **API Key** | `sk-xxxxxxxxxxxxxxxxxxxxxxxx`（替换为你自己的 Key） |
| **模型** | `qwen3.6-plus`（推荐） |

<details>
<summary>💡 配置结构参考（JSON）</summary>

```json
{
  "provider": {
    "api_url": "https://dashscope.aliyuncs.com/compatible-mode/v1",
    "api_key": "sk-xxxxxxxxxxxxxxxxxxxxxxxx",
    "model": "qwen3.6-plus"
  }
}
```

</details>

> 💡 支持任何 OpenAI 兼容格式的提供商（DeepSeek、OpenRouter、本地 Ollama 等），只需替换 URL 和 Key。

**✅ 通关验证：**

回到首页聊天界面，对小万说：

```
你好，请问你是谁？
```

收到小万的正常回复 → **🎉 Level 1 通关！引擎已点火！**

---

### <img src="https://img.shields.io/badge/Level_2-解锁全部能力-blue" alt="Level 2"/> 能力总览与工具配置 —— 给小万装上手和脚

完成 Level 1 后，小万已经能"思考"了。但真正的 Agent 不止能聊天 —— 它还能**操控手机、管理日程、读写文件、执行命令、浏览网页**。这一关带你认识小万的全部武器库，并配置两个需要手动开启的重型装备：**MCP 工具** 和 **Alpine 终端**。

#### 2-1 内置能力一览 —— 小万出厂自带的武器

> 📍 这些能力**无需额外配置**，Level 1 通关后即可直接使用。

| 能力 | 说明 | 试着对小万说… |
|------|------|--------------|
| 📱 **设备自动化** | 操作手机界面：点击、输入、滑动 | "帮我打开微信并发送一条消息" |
| ⏰ **时间管理** | 设置闹钟/提醒、创建/查询/修改日历事件 | "明天早上 9 点提醒我开会" |
| 📂 **文件处理** | 读写/搜索工作区文件、管理目录结构 | "帮我在工作区新建一个项目文件夹" |
| 🌐 **网页交互** | 智能浏览网页：导航、截图、提取内容 | "帮我搜索一下上海明天的天气" |
| 🎵 **多媒体控制** | 播放本地/网络音频、控制系统媒体播放 | "暂停当前音乐" |
| 🧬 **记忆系统** | 记录重要信息到长期记忆、检索历史关键点 | "请记住我对坚果过敏" |

#### 2-2 MCP 工具 —— 给小万接上外挂

> 📍 **去哪找：** `设置` → `MCP 工具`

**💡 什么是 MCP？**

MCP（Model Context Protocol）让大模型能直接调用外部工具 —— 获取实时信息、操作本地服务……就像给小万装上了各种"外挂插件"。

**🔧 做什么：**

1. 进入 MCP 配置页面，点击新建 MCP 工具
2. 填入服务器地址（Endpoint URL），如 `http://127.0.0.1:xxxx`
3. 填入密钥（Bearer Token）用于鉴权

<details>
<summary>💡 MCP 配置结构参考（JSON）</summary>

```json
{
  "mcp_server": {
    "name": "my-mcp-server",
    "endpoint_url": "http://127.0.0.1:8080",
    "bearer_token": "your-token-here"
  }
}
```

</details>

**✅ 验证：** 配置完成后，回到聊天界面，让小万调用你刚配置的 MCP 工具。例如对小万说 `"帮我调用 MCP 工具测试一下"`，小万成功调用并返回结果即可。

#### 2-3 Alpine 终端 —— 给小万一个 Linux 黑箱

> 📍 **去哪找：** `设置` → `Alpine 环境`

**💡 这是什么？**

我们在安卓手机里内置了一个硬核的小巧 Linux（Alpine）环境。有了它，小万可以直接执行终端命令 —— 跑脚本、装工具、管理 Python 虚拟环境，真正做到"指哪打哪"。

**🔧 做什么：**

进入页面后，你会看到以下结构：

| 区域 | 包含工具 | 状态 |
|------|---------|------|
| **环境配置** | Alpine 基础环境 | `ready` / `lost` |
| **开发环境** | Node.js、npm、Git、Python、uv、pip | `ready` / `lost` |
| **SSH** | ssh、sshpass、sshd | `ready` / `lost` |

页面底部有 **「开始配置」** 按钮：

```
1. 点击「开始配置」→ 等待环境下载与安装（首次需要网络，耐心等待）
2. 安装完成后，各工具状态从 lost → ready
3. SSH 相关工具为可选项，普通使用无需安装
```

> 💡 状态说明：`ready` = 已安装可用 · `lost`  = 尚未安装。如果点击「开始配置」后仍显示「未检测到」，请确认网络畅通后重试。

**✅ 验证：** 所有开发环境工具显示 `ready` 后，回到主界面对小万说 `"帮我用终端执行一个 ls 命令"`，看到执行结果即可。

<details>
<summary>💡 扩展能力：skill-creator 技能</summary>

小万内置了 `skill-creator` 技能，位于 `/workspace/.omnibot/skills/skill-creator`。它可以指导你**创建全新的自定义技能**（如天气查询、自动化脚本等），进一步扩展小万的能力边界。试着对小万说：

```
帮我创建一个查询天气的技能
```

</details>

**🎉 Level 2 通关条件：** 以上三步任选其一验证成功即可 → **装备就绪！**

---

### <img src="https://img.shields.io/badge/Level_3-打造专属领域-blueviolet" alt="Level 3"/> 场景配置 (Scene) —— 给小万注入灵魂

这一关有两个子任务：定制 **人格角色** + 分配 **场景模型**。

#### 3-1 SOUL.md —— 小万的灵魂编辑器

> 📍 **去哪找：** `设置` → `Workspace 记忆配置` → **「SOUL.md（Agent 灵魂）」** 编辑区

**🔧 做什么：**

SOUL.md 是小万的"性格说明书"，会注入到每轮对话的 System Prompt 中。你可以定义：

```markdown
# 示例 SOUL.md

## 身份
你是「小万」，一个专业的法律顾问助手。

## 语气
- 使用正式、专业的语言
- 适当引用法条编号

## 行为边界
- 不提供具体的法律建议，仅做信息整理
- 复杂问题建议用户咨询执业律师
```

> 💡 你也可以在对话中对小万说"请记住你是一个美食博主"，授权后它会自动更新 SOUL.md。

<details>
<summary>💡 记忆系统说明</summary>

小万拥有完整的记忆体系，让它真正"记住"你：

| 记忆类型 | 说明 | 存储方式 |
|---------|------|---------|
| **短期记忆** | 当前对话上下文 | 会话内自动维护 |
| **长期记忆** | 跨对话持久化的用户偏好与知识 | 向量化嵌入存储 |
| **SOUL.md** | Agent 人格与行为规则 | Workspace 文件 |
| **Memory Rollup** | 每日记忆整理与归纳 | 定时自动执行 |

</details>

**✅ 通关验证：**

编辑 SOUL.md → 保存 → 开一个**新对话** → 随便问个问题。如果回复风格符合你设定的人格 → ✅ 子任务 3-1 完成！

#### 3-2 场景模型配置 —— 给每个工位安排专属模型

> 📍 **去哪找：** `设置` → `场景模型配置`

**🔧 做什么：**

小万内部有多个"工位"，每个负责不同的事：

| 场景 | 职责 | 选模型建议 |
|------|------|-----------|
| **Agent** | 理解意图、决策调度 | 最聪明的模型 |
| **Operation** | GUI 自动化执行 | 响应快的视觉模型 |
| **Compactor** | 上下文压缩纠错 | 性价比高的模型 |
| **Chat Compactor** | 聊天历史总结 | 性价比高的模型 |
| **Loading** | 生成等待提示文案 | 最便宜的即可 |
| **Memory Embed** | 记忆向量化 | Embedding 模型 |
| **Memory Rollup** | 每日记忆整理 | 性价比高的模型 |

<details>
<summary>💡 场景配置结构参考（JSON）</summary>

```json
{
  "scenes": {
    "agent":         { "model": "qwen-max",    "note": "主力决策" },
    "operation":     { "model": "qwen-plus",   "note": "快速执行" },
    "compactor":     { "model": "qwen-plus",   "note": "上下文压缩" },
    "chat_compactor":{ "model": "qwen-plus",   "note": "聊天摘要" },
    "loading":       { "model": "qwen-turbo",  "note": "等待文案" },
    "memory_embed":  { "model": "text-embedding-v3", "note": "向量化" },
    "memory_rollup": { "model": "qwen-plus",   "note": "记忆整理" }
  }
}
```

</details>

> 💡 默认所有场景共用 Level 1 设置的模型。想省钱或提升效果？给特定场景绑定不同模型。选择「恢复默认」可随时还原。

**✅ 通关验证：**

把 Agent 场景绑定到一个不同的模型 → 发条消息 → 观察回复风格是否有变化 → **🎉 Level 3 通关！灵魂已注入！**

---

### <img src="https://img.shields.io/badge/Level_4-召唤分身-ff69b4" alt="Level 4"/> 子代理 (SubAgent) —— 小万的影分身之术

进阶玩法。当任务太复杂，小万可以拆成多个子任务，派出分身并行处理。

#### 4-1 对话中即时分身

> 📍 **去哪找：** 无需额外配置，小万自带此能力。

**🔧 做什么：**

在聊天中给小万一个可拆解的复合任务：

```
帮我使用子代理同时做三件事：
1. 查一下今天的科技新闻
2. 总结一下我昨天的会议纪要
3. 写一段明天团建的开场白
```

小万会调用 `subagent_dispatch`，派出最多 **6 个分身**并行执行，汇总后返回完整回复。

<details>
<summary>💡 SubAgent 调度结构参考（JSON）</summary>

```json
{
  "subagent_dispatch": {
    "max_concurrency": 6,
    "tasks": [
      { "id": 1, "instruction": "查一下今天的科技新闻", "tools": ["browser"] },
      { "id": 2, "instruction": "总结昨天的会议纪要", "tools": ["memory"] },
      { "id": 3, "instruction": "写一段团建开场白", "tools": [] }
    ]
  }
}
```

</details>

**✅ 通关验证：**

发送上面的示例 → 对话中出现 **并行执行任务** → 所有子任务返回结果 → ✅ 子任务 4-1 完成！

#### 4-2 定时 SubAgent 任务 —— 让分身自动值班

> 📍 **去哪找：** 对话中直接告诉小万 `定时任务` 管理

**🔧 做什么：**

```
每天 18：00 帮我总结今天学到的新知识。
```

小万会创建一个定时 SubAgent 任务，到点自动执行。

**✅ 通关验证：**

```bash
# 1. 对小万说：
"每天 18:00 帮我总结今天学到的新知识。"

# 2. 去「定时 → 定时任务」确认出现了带「SubAgent」标签的任务

# 3. 等执行时间到，检查侧边栏是否出现带绿色「SubAgent」徽章的新对话

# 4. 打开对话，看到小万自动生成的内容 → 🎉 终极通关！
```

---

### 🏆 通关总结

| 关卡 | 解锁能力 | 配置路径 |
|------|----------|----------|
| <img src="https://img.shields.io/badge/Level_1-通关-brightgreen" alt="L1"/> | 🧠 核心引擎点火 | `设置` → `模型提供商` |
| <img src="https://img.shields.io/badge/Level_2-通关-brightgreen" alt="L2"/> | 🛠️ 解锁全部能力 | 内置工具 / `设置` → `MCP 工具` / `Alpine 环境` |
| <img src="https://img.shields.io/badge/Level_3-通关-brightgreen" alt="L3"/> | 💫 打造专属领域 | `设置` → `Workspace 记忆` / `场景模型配置` |
| <img src="https://img.shields.io/badge/Level_4-通关-brightgreen" alt="L4"/> | 🥷 召唤分身 | 对话中直接使用 |

> 🎊 恭喜通关！还有疑问？随时问小万："我该怎么配置 XXX？"——毕竟，你已经把它培养得这么强了！

## 🧪 Demo
<table width="100%">
  <tr>
    <td width="20%" align="center">
      <div>
        <p><strong>下载抖音视频Skill演示</strong></p>
        <video src="https://github.com/user-attachments/assets/8dbe772a-b300-4d52-9428-c3030fbf97a8" controls="controls" style="max-width: 100%;"></video>
      </div>
    </td>
    <td width="20%" align="center">
      <div>
        <p><strong>手机任务执行</strong></p>
        <video src="https://github.com/user-attachments/assets/a9a22755-e6fb-43d9-8647-1bc62549a1da" controls="controls" style="max-width: 100%;"></video>
      </div>
    </td>
    <td width="20%" align="center">
      <div>
        <p><strong>定时任务演示</strong></p>
        <video src="https://github.com/user-attachments/assets/9bc78501-55ab-4c41-837d-5b8c6589e352" controls="controls" style="max-width: 100%;"></video>
      </div>
    </td>
    <td width="20%" align="center">
      <div>
        <p><strong>原生OpenClaw演示</strong></p>
        <video src="https://github.com/user-attachments/assets/45b235ae-17fb-4af6-89f0-03419a063441" controls="controls" style="max-width: 100%;"></video>
      </div>
    </td>
  </tr>
</table>

## 🏗️ 架构概览
```
OpenOmniBot/
├── app/                 # Android 主宿主模块：App 入口、Agent 编排、系统能力、MCP、前台服务
├── ui/                  # Flutter UI 模块：聊天、设置、任务、记忆等界面（Riverpod + GoRouter）
├── baselib/             # 基础核心库：数据库、网络、存储、模型配置、OCR、权限、设备信息
├── assists/             # 自动化执行引擎：任务调度、状态机、视觉检测、操作控制
├── accessibility/       # 无障碍与屏幕感知：Accessibility Service、截图、MediaProjection
├── omniintelligence/    # 智能能力抽象层：模型协议、任务状态、Agent 请求/响应模型
└── uikit/               # 原生浮窗/覆盖层 UI：Overlay、悬浮球、半屏面板
```

## 其他
感谢 linux.do 等社区的开发者的支持；
感谢优秀的开源项目：https://github.com/RohitKushvaha01/ReTerminal

<table align="center">
  <tr>
    <td align="center">
      <img src="docs/pic/wechat.png" alt="WeChat Group" width="220"/><br/>
      <b>WeChat Group</b>
    </td>
  </tr>
</table>
