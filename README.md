# OpenOmniBot

> 那晚豆包和龙虾都喝多了...<br> 一个Android端真正可“执行”的Agent，而不仅仅是一个对话式聊天机器人


## ✨ 项目简介
OpenOmniBot 是一个基于 Android 原生与 Flutter 混合架构的智能机器人助手应用。
与传统 AI App 不同，它关注的是：**从理解 → 决策 → 执行 → 反馈的完整闭环**。

## 当前已具备的核心能力包括：

- 🧠 **统一 Agent 入口**：根据用户意图自动决定「直接回答」或「调用工具执行」或 「使用Skill」
- 🧩 **工具生态扩展**：Termux，浏览器、MCP、OpenClaw、安卓系统工具...
- 📱 **手机任务自动化**：支持用视觉模型操作手机界面，结合无障碍、截图、状态机完成跨 App 的自动点击、输入、滚动、流程执行。
- ⏰ **系统级能力**：支持定时任务、闹钟提醒、日历事件创建/查询/修改。
- 🧬 **记忆系统**：有“本地记忆”和“Mem0 云端长期记忆”，可以查看、编辑、删除，并用于个性化建议和长期偏好沉淀。
- 🔨 **生产力工具**：支持读写文件、浏览工作区、调用浏览器、调用终端。


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

## 🚀 快速开始

### 环境要求

- Android Studio (推荐最新版)
- Flutter SDK (3.9.2+)
- JDK 11+

### 获取代码

```bash
git clone https://github.com/omnimind-ai/OpenOmniBot.git
cd OpenOmniBot

#安装 Flutter 依赖
cd ui
flutter pub get
cd ..
```

### 构建并安装
```bash
./gradlew :app:installDevelopDebug
```
### 配置

在APP的设置页中配置：

- 模型提供商
- 场景模型配置
- Mem0云记忆配置
- MCP工具
- Termux安装与配置


## 🧪 最小可运行示例

### ✅ 示例 1：闹钟（Tool Calling）
```
帮我创建一个明天早上 8 点的闹钟，标题叫“起床开会”
```

### ✅ 示例 2：抖音下载视频（Skill）
```
帮我下载 <抖音视频链接>
```

### ✅ 示例 3：复杂任务执行（Phone Use）
```
帮我在大众点评收藏打卡xx，并给个五星好评
```

### 其他
感谢 linux.do 等社区的开发者的支持

<table align="center">
  <tr>
    <td align="center">
      <img src="docs/pic/wechat_2026-3-21.jpg" alt="WeChat Group" width="220"/><br/>
      <b>WeChat Group</b>
    </td>
  </tr>
</table>