<p align="center">
  <picture>
    <img alt="OpenOmniBot" src="docs/pic/OmniBot.png" width="50%">
  </picture>
</p>

<h3 align="center">
Your On-Device AI Assistant
</h3>

<div align="center">
  <img alt="GitHub Repo stars" src="https://img.shields.io/github/stars/omnimind-ai/OpenOmniBot">
  <a href="https://github.com/omnimind-ai/OpenOmniBot/releases/latest"><img alt="GitHub Release" src="https://img.shields.io/github/v/release/omnimind-ai/OpenOmniBot"></a>
  <br>
  <a href="https://omnimind.com.cn"><img src="https://img.shields.io/badge/About_us-OmniMind-purple.svg?color=%234b0c77" alt="OmniMind"></a>
  <a href="https://linux.do"><img src="https://img.shields.io/badge/Linux_Do-Community-yellow.svg?color=%23ac3712" alt="LinuxDo Community"></a>
  <a href="#misc">
    <img src="https://img.shields.io/badge/WeChat-Group-lightgreen" alt="WeChat Group"/>
  </a>
</div>

<p align="center">
  <a href="README.md">English</a> | <a href="README_zh.md">简体中文</a>
</p>

<p align="center">
| 
<a href="#-demo"><b>Demo</b></a> 
| 
<a href="#-quick-start"><b>Quick Start</b></a> 
| 
<a href="https://github.com/omnimind-ai/OpenOmniBot/releases"><b>Release</b></a> 
|
<a href="https://github.com/omnimind-ai/OmniInfer-LLM/issues"><b>Issues</b></a> 
|
</p>

## ✨ About

OpenOmniBot is an intelligent robot assistant app built on a hybrid architecture of native Android and Flutter. Unlike traditional AI apps, it focuses on **the complete closed loop from understanding → decision-making → execution → feedback** — a truly "executable" Agent on Android.

## 🧠 Core Capabilities

- 🧩 **Extensible Tool Ecosystem** — Skills, Alpine system, browser, MCP, Android system tools, and more.

- 📱 **Phone Task Automation** — Operate the phone UI using vision models.

- ⏰ **System-Level Features** — Scheduled tasks, alarm reminders, calendar event creation/query/modification, audio playback control.

- 🧬 **Memory System** — Short-term and long-term memory embedding.

- 🔨 **Productivity Tools** — Read/write files, browse workspace, invoke browser, invoke terminal.

## 🚀 Development Guide

### Prerequisites

- Flutter SDK (3.9.2+)
- JDK 11+

### Get the Code

```bash
git clone https://github.com/omnimind-ai/OpenOmniBot.git
cd OpenOmniBot

# Install Flutter dependencies
cd ui
flutter pub get
```

### Build & Install

```bash
cd .. # Back to root directory
./gradlew :app:installDevelopDebug
```

## 🚀 Quick Start

> Follow these steps to set up OpenOmniBot from scratch — it should take about 15 minutes.

---

### Step 1: Configure a Model Provider

#### Enter Provider Details

`Settings` → `Model Provider`

Fill in your LLM provider details. Using Alibaba Cloud Bailian as an example:

| Field | Value |
|-------|-------|
| **API URL** | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| **API Key** | `sk-xxxxxxxxxxxxxxxxxxxxxxxx` (replace with your own key) |
| **Model** | `qwen3.6-plus` (recommended) |

<p align="center">
  <img src="docs/tutorial/2.png" width="300" alt="Model provider configuration example"/>
</p>

Any OpenAI-compatible provider is supported (DeepSeek, OpenRouter, local Ollama, etc.) — just replace the URL and Key.

#### Verify

Go back to the chat screen and send "Hello". A normal reply means the configuration is successful.

---

### Step 2: Built-in Capabilities & Tool Configuration

#### 2.1 Built-in Capabilities

Once the model is configured, OpenOmniBot can chat right away. The following capabilities also work out of the box with no extra setup:

| Capability | Description | Example Command |
|------------|-------------|-----------------|
| 📱 Device Automation | Operate the phone UI: tap, type, swipe | "Open WeChat and send a message" |
| ⏰ Time Management | Set alarms/reminders, create/query/modify calendar events | "Remind me about the meeting at 9 AM tomorrow" |
| 📂 File Handling | Read/write/search workspace files, manage directory structure | "Create a new project folder in the workspace" |
| 🌐 Web Interaction | Browse the web: navigate, screenshot, extract content | "Search for tomorrow's weather in Shanghai" |
| 🎵 Media Control | Play local/network audio, control system media playback | "Pause the current music" |
| 🧬 Memory System | Save important information to long-term memory | "Remember that I'm allergic to nuts" |

The following two require manual configuration:

#### 2.2 MCP Tools

`Settings` → `MCP Tools`

MCP (Model Context Protocol) allows OpenOmniBot to call external tool services for real-time information, local service operations, and more.

1. Go to the MCP configuration page and tap "New MCP Tool"
2. Enter the server address (Endpoint URL), e.g. `http://127.0.0.1:xxxx`
3. Enter the secret (Bearer Token) for authentication

<p align="center">
  <img src="docs/tutorial/4.png" width="300" alt="MCP tool configuration example"/>
</p>

**Verify:** Go back to the chat screen and ask OpenOmniBot to call the MCP tool you configured. A successful result means it's working.

#### 2.3 Alpine Terminal

`Settings` → `Alpine Environment`

OpenOmniBot includes a lightweight Linux (Alpine) environment that can execute terminal commands, run scripts, manage Python virtual environments, and more.

| Section | Included Tools | Status |
|---------|---------------|--------|
| Base Environment | Alpine base environment | `ready` / `lost` |
| Dev Environment | Node.js, npm, Git, Python, uv, pip | `ready` / `lost` |
| SSH | ssh, sshpass, sshd | `ready` / `lost` |

Tap "Start Setup" at the bottom of the page and wait for the environment to download and install. Once complete, tool statuses will change from `lost` to `ready`. SSH is optional.

<p align="center">
  <img src="docs/tutorial/5.png" width="300" alt="Alpine terminal configuration example"/>
</p>

**Verify:** Tell OpenOmniBot "Run an ls command in the terminal" and check the output.

<details>
<summary>Bonus: skill-creator</summary>

OpenOmniBot includes a built-in `skill-creator` skill located at `/workspace/.omnibot/skills/skill-creator`. It can help you create custom skills (e.g., weather lookup, automation scripts). Try saying: "Create a skill that checks the weather."

</details>

---

### Step 3: Personalization

#### 3.1 SOUL.md — Custom Persona

`Settings` → `Workspace Memory Config` → `SOUL.md (Agent Soul)`

SOUL.md is OpenOmniBot's persona configuration file, injected into the System Prompt of every conversation turn. You can define its identity, tone, and behavioral boundaries:

```markdown
## Identity
You are "OmniBot", a professional legal consultant assistant.

## Tone
- Use formal, professional language
- Reference statute numbers where appropriate

## Behavioral Boundaries
- Do not provide specific legal advice; only organize information
- For complex issues, suggest the user consult a licensed attorney
```

You can also say "Remember that you are a food blogger" in a conversation — once authorized, OpenOmniBot will automatically update SOUL.md.

<details>
<summary>Memory System Details</summary>

| Memory Type | Description | Storage |
|-------------|-------------|---------|
| Short-term Memory | Current conversation context | Maintained automatically within the session |
| Long-term Memory | Cross-conversation persistent user preferences & knowledge | Vectorized embedding storage |
| SOUL.md | Agent persona and behavioral rules | Workspace file |
| Memory Rollup | Daily memory consolidation and summarization | Scheduled automatic execution |

</details>

**Verify:** Edit SOUL.md and save, start a new conversation, and observe whether the reply style matches your settings.

#### 3.2 Scene Model Configuration

`Settings` → `Scene Model Config`

OpenOmniBot uses multiple internal scenes, each responsible for a different role. By default, all scenes share the model set in Step 1. You can assign different models to specific scenes to optimize performance or reduce cost:

| Scene | Role | Model Recommendation |
|-------|------|---------------------|
| Agent | Intent understanding & decision dispatch | Smartest model |
| Operation | GUI automation execution | Fast vision model |
| Compactor | Context compression & error correction | Cost-effective model |
| Chat Compactor | Chat history summarization | Cost-effective model |
| Loading | Generate waiting prompt text | Cheapest option |
| Memory Embed | Memory vectorization | Embedding model |
| Memory Rollup | Daily memory consolidation | Cost-effective model |

Select "Restore Defaults" to reset at any time.

<p align="center">
  <img src="docs/tutorial/3.png" width="300" alt="Scene model configuration example"/>
</p>

---

### Step 4: Using SubAgents

#### 4.1 SubAgents in Conversation

When a task is complex, OpenOmniBot can split it into multiple subtasks and process them in parallel. No extra configuration needed — just use it directly in conversation:

```
Use subagents to do three things at once:
1. Look up today's tech news
2. Summarize yesterday's meeting notes
3. Write an opening speech for tomorrow's team outing
```

OpenOmniBot will dispatch up to 6 subagents to execute in parallel and return the combined results.

#### 4.2 Scheduled SubAgent Tasks

You can also have OpenOmniBot run subagent tasks on a schedule:

```
Every day at 18:00, summarize what I learned today.
```

Once set, you can view and manage these in `Schedule` → `Scheduled Tasks`.

---

### Configuration Summary

| Step | Content | Configuration Path |
|------|---------|-------------------|
| Step 1 | Configure model provider | `Settings` → `Model Provider` |
| Step 2 | Built-in capabilities / MCP / Alpine | Built-in (out of the box) / `Settings` → `MCP Tools` / `Alpine Environment` |
| Step 3 | Persona & scene models | `Settings` → `Workspace Memory Config` / `Scene Model Config` |
| Step 4 | SubAgents | Use directly in conversation |

## 🧪 Demo
<table width="100%">
  <tr>
    <td width="20%" align="center">
      <div>
        <p><strong>Douyin Video Download Skill</strong></p>
        <video src="https://github.com/user-attachments/assets/8dbe772a-b300-4d52-9428-c3030fbf97a8" controls="controls" style="max-width: 100%;"></video>
      </div>
    </td>
    <td width="20%" align="center">
      <div>
        <p><strong>Phone Task Execution</strong></p>
        <video src="https://github.com/user-attachments/assets/a9a22755-e6fb-43d9-8647-1bc62549a1da" controls="controls" style="max-width: 100%;"></video>
      </div>
    </td>
    <td width="20%" align="center">
      <div>
        <p><strong>Scheduled Task Demo</strong></p>
        <video src="https://github.com/user-attachments/assets/9bc78501-55ab-4c41-837d-5b8c6589e352" controls="controls" style="max-width: 100%;"></video>
      </div>
    </td>
    <td width="20%" align="center">
      <div>
        <p><strong>Native OpenClaw Demo</strong></p>
        <video src="https://github.com/user-attachments/assets/45b235ae-17fb-4af6-89f0-03419a063441" controls="controls" style="max-width: 100%;"></video>
      </div>
    </td>
  </tr>
</table>

## 🏗️ Architecture Overview
```
OpenOmniBot/
├── app/                 # Android host module: App entry, Agent orchestration, system capabilities, MCP, foreground service
├── ui/                  # Flutter UI module: Chat, settings, tasks, memory screens (Riverpod + GoRouter)
├── baselib/             # Core library: Database, networking, storage, model config, OCR, permissions, device info
├── assists/             # Automation engine: Task scheduling, state machine, visual detection, operation control
├── accessibility/       # Accessibility & screen awareness: Accessibility Service, screenshots, MediaProjection
├── omniintelligence/    # Intelligence abstraction layer: Model protocols, task states, Agent request/response models
└── uikit/               # Native overlay UI: Overlay, floating button, half-screen panel
```

## Misc
Thanks to the community developers for their support.

Thanks to these excellent open-source projects: https://github.com/RohitKushvaha01/ReTerminal, https://github.com/OpenMinis

<table align="center">
  <tr>
    <td align="center">
      <img src="docs/pic/wechat.png" alt="WeChat Group" width="220"/><br/>
      <b>WeChat Group</b>
    </td>
  </tr>
</table>
