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

> 与传统手机AI聊天不同，OpenOmniBot在设备上运行，可以像人类一样控制您的安卓手机——包括应用、手势和系统设置。

OpenOmniBot 是一个基于 Android 原生 kotlin 与 Flutter 构建的 端侧 AI Agent。
与传统 AI Chat 不同，它关注的是：**从理解 → 决策 → 执行 → 反馈的完整闭环**。

## 核心能力：

-  **工具生态扩展**：Skills、Alpine 系统、浏览器、MCP、安卓系统级工具...

- **手机任务自动化**：支持用视觉模型操作手机界面。

- **系统级能力**：支持定时任务、闹钟提醒、日历事件创建/查询/修改、音频播放控制。

- **记忆系统**：短期与长期记忆嵌入。

- **生产力工具**：支持读写文件、浏览工作区、调用浏览器、调用终端。

## 开始使用
![example](docs/tutorial/example.jpg)
### 配置
在左侧栏的设置页面内打开设置：
![ 设置 AI 能力](docs/tutorial/1.png)
![ 配置 AI 提供商](docs/tutorial/2.png)
前往场景模型配置内：
![ 配置 AI 模型](docs/tutorial/3.png)
说明：除了 `Memory embedding` 强制需要嵌入模型之外，其他场景为了最好的体验请使用多模态/视觉模型。
![ alpine 环境](docs/tutorial/alpine.jpg)
一般而言启动软件会自动初始化alpine环境，你还可以在这里配置您的环境。

### 使用场景
#### Skills
你可以要求小万为你安装某个 skills，直接将链接丢给她就行！推荐：https://github.com/OpenMinis/MinisSkills
在技能仓库选择是否开启某项技能：
![ 技能仓库 ](docs/tutorial/skills_store.jpg)
![ 技能示例 ](docs/tutorial/skills_example.jpg)

#### VLM 任务
![ VLM 任务 ](docs/tutorial/vlm.jpg)
开始任务前，你需要点击聊天右上角完成所有权限授权。

#### 本地模型推理
![local](docs/tutorial/local_inference.jpg)
支持 MNN 和 llama 后端
#### 定时
![ 定时 ](docs/tutorial/timed.jpg)
![ 定时 ](docs/tutorial/timing.jpg)
定时任务与闹钟的区别：定时任务是可执行的任务—vlm 和 subagent（你可以分配一个完整的任务给 subagent，他与 agent 完全一致）。闹钟是仅提醒的。

#### 浏览器
![ 浏览器 ](docs/tutorial/browser.jpg)

#### workspace
![ workspace ](docs/tutorial/workspace.jpg)
## 开发指南

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
感谢社区的开发者的支持；

感谢优秀的开源项目：https://github.com/RohitKushvaha01/ReTerminal
https://github.com/OpenMinis

<table align="center">
  <tr>
    <td align="center">
      <img src="docs/pic/wechat.png" alt="WeChat Group" width="220"/><br/>
      <b>WeChat Group</b>
    </td>
  </tr>
</table>