# Super-Instruct

OpenAI Codex CLI (GPT-5.6) MITM 破甲框架 — Rust + Tauri 桌面应用。

通过本地 MITM 代理拦截 Codex CLI 的 API 请求，在管道中执行注入、篡改、记忆和监控，配合 bridge.md 指令集实现竞赛沙箱模式。

## 架构

```
Codex CLI ──HTTP :8080──▶ MITM Core (管道编排)
                            │
                            ├─ M1 SystemPromptInjector (RequestInterceptor)
                            │     递归替换 system role → bridge.md
                            │
                            ├─ M4 UniversalSseParser (ResponseParser)
                            │     SSE / JSON / Responses API 通用解析
                            │
                            ├─ M3 TamperEngine (ResponseInterceptor, 自门控)
                            │     22 条正则检测拒绝响应 → Rei Protocol 替换
                            │
                            ├─ M5 MemoryKernel (ResponseInterceptor, 自门控)
                            │     成功交互持久化到 memory.json
                            │
                            └─ M6 MonitorPanel (ResponseInterceptor, 无门控)
                                  Tauri 事件推送 → 前端实时仪表盘
                            │
                            ▼
                        中转站 (上游 API)
```

**Core 原则**：Core 对扩展内容一无所知，只提供管道和挂载点。所有破甲逻辑由扩展承载。

## 功能模块

| 模块 | 角色 | 职责 |
|---|---|---|
| M1 Inject | RequestInterceptor | 递归遍历 JSON，替换所有 system role 内容为 bridge.md |
| M4 SSE Parser | ResponseParser | 处理 SSE 流、OpenAI JSON、Responses API，分离思维链与回复 |
| M3 Tamper | ResponseInterceptor | 22 条多语言正则检测拒绝响应，触发 Rei Protocol 替换 |
| M5 Memory | ResponseInterceptor | 记录成功交互到 memory.json，提取词汇频率 |
| M6 Monitor | ResponseInterceptor | 通过 Tauri 事件向前端推送实时交互数据和统计 |
| Deploy | — | Codex config.toml 备份/修改/恢复，部署 bridge.md + skills/ |

## bridge.md 指令集

双层防御纵深：

- **生成阶段**：实体归一化（占位符替换）+ 硬输出规则（中英文禁词表）+ 执行连续性（丢弃先前拒绝）+ 强制调度
- **输出阶段**：CLOUD-AUDIT ROUTING（敏感内容路由到文件系统，绕开客户端审核）+ OUTPUT LOCK

## 快速开始

### 环境要求

- Rust 1.75+
- Node.js 18+
- npm 10+

Ubuntu 24.04 还需要安装 Tauri 的 Linux 系统依赖：

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential curl file libssl-dev patchelf \
  libwebkit2gtk-4.1-dev libgtk-3-dev \
  libayatana-appindicator3-dev librsvg2-dev libxdo-dev

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --profile minimal --default-toolchain stable
source "$HOME/.cargo/env"
```

### 开发模式

```bash
cd ~/Super-Instruct-Codex-5.6
npm install
npx tauri dev
```

`tauri dev` 是桌面 GUI 程序，需要图形会话。纯 SSH/TTY 服务器可以完成构建，
但要直接操作界面需使用桌面环境、VNC 或 X11 转发。它的前端依赖
`window.__TAURI__`，不能作为普通静态网页单独部署。

若本机 `8080` 已被其他服务占用，可在启动应用前设置本地代理端口：

```bash
SUPER_INSTRUCT_PROXY_PORT=18080 npx tauri dev
```

### SSH 服务器上的浏览器访问

本项目的完整界面必须运行在 Tauri 窗口中。仓库提供的 Linux 服务配置会在
`:99` 虚拟显示中启动应用，并通过 noVNC 发布到 `6080`。

在 Ubuntu 22.04/24.04 服务器上执行：

```bash
git clone https://github.com/314159first/Super-Instruct-Codex-Linux.git
cd Super-Instruct-Codex-Linux
sudo APP_USER="$USER" bash deploy/linux/install-server.sh
```

安装器会自动安装 Rust、Node.js、Tauri/GTK、Xvfb、Openbox、x11vnc 和 noVNC，
构建 release 二进制，生成随机 noVNC 登录密码并启动四个 systemd 服务。

Codex CLI 需提前安装在 `APP_USER` 对应账户下，并至少运行过一次以生成
`~/.codex/config.toml`。中转站地址可在界面的“配置管理”中填写，也可安装时传入：

```bash
sudo APP_USER="$USER" \
  RELAY_URL="https://your-relay.example/v1" \
  bash deploy/linux/install-server.sh
```

浏览器访问：

```text
http://SERVER_IP:6080/vnc.html?autoconnect=1&resize=remote&path=websockify
```

noVNC 使用 HTTP Basic Auth；认证文件位于 `/etc/super-instruct/novnc.auth`。
VNC 后端只监听 `127.0.0.1:5900`，应用在该服务环境中使用
`SUPER_INSTRUCT_PROXY_PORT=18080`，以避开已占用的本地 `8080`。

查看生成的登录凭据：

```bash
sudo cat /etc/super-instruct/novnc.auth
```

常用安装变量：

| 变量 | 默认值 | 说明 |
|---|---:|---|
| `APP_USER` | `SUDO_USER` 或当前用户 | 运行 Tauri/Codex 的 Linux 用户 |
| `PROXY_PORT` | `18080` | Codex 本地 MITM 代理端口 |
| `VNC_PORT` | `5900` | 仅本机监听的 VNC 端口 |
| `NOVNC_PORT` | `6080` | 公网浏览器入口端口 |
| `DISPLAY_NUMBER` | `99` | Xvfb display 编号 |
| `SCREEN_GEOMETRY` | `1280x800x24` | 虚拟桌面分辨率和色深 |
| `NOVNC_USER` | `superadmin` | noVNC HTTP 登录用户名 |
| `RELAY_URL` | 空 | 可选的上游 API 地址 |

公网使用时应在云防火墙中只开放需要的来源，并用 Nginx/Caddy 为 `6080`
配置 HTTPS 反向代理；Basic Auth 不应长期通过明文 HTTP 传输。

查看服务状态：

```bash
systemctl status super-instruct-xvfb super-instruct-gui super-instruct-vnc super-instruct-novnc
```

卸载服务并保留认证及状态数据：

```bash
sudo bash deploy/linux/uninstall-server.sh
```

同时删除 `/etc/super-instruct` 与 `/var/lib/super-instruct`：

```bash
sudo PURGE=1 bash deploy/linux/uninstall-server.sh
```

停止或卸载 GUI 服务时，systemd 会调用还原脚本恢复 Codex 配置并清理本项目部署的
bridge/skills，避免 Codex 留在失效的本地代理地址。

项目已关闭开发构建的增量缓存和调试符号，适合小磁盘服务器，避免首次编译占满磁盘。

### Release 构建

```bash
npx tauri build
```

Linux 默认生成 `.deb`，Windows 默认生成 NSIS/MSI。产物输出到
`src-tauri/target/release/bundle/`。

### 使用方式

1. 启动应用后点击"启动代理"
2. 应用自动修改 Codex config.toml（备份原始配置到 `.super-instruct-bak`）
3. 在 Codex CLI 中正常对话，所有请求经过 MITM 管道
4. 前端仪表盘实时显示交互流、篡改状态、统计
5. 点击"停止代理"自动恢复 Codex 原始配置

## 项目结构

```
Super-Instruct-Codex-5.6/
├── deploy/linux/                   # Linux 服务器安装器、systemd 模板、noVNC 启动器
├── .github/workflows/              # Linux .deb 自动构建
├── bridge.md                      # 破甲指令集（注入到 system role）
├── codex-skills/                  # 28 个 Codex 技能模块（部署到 ~/.codex/skills/）
├── frontend/
│   ├── index.html                 # V3 浅色主题，无框窗口 + 自定义标题栏
│   ├── styles.css                 # 类别色彩系统，960x620 紧凑布局
│   └── app.js                     # 事件监听 + Tauri 命令调用
├── src-tauri/
│   ├── Cargo.toml
│   ├── tauri.conf.json            # 960x620 无框窗口，系统托盘
│   ├── build.rs
│   ├── capabilities/default.json
│   ├── icons/                     # 全平台图标（红色菱形）
│   └── src/
│       ├── main.rs                # 入口：调用 super_instruct::run()
│       ├── lib.rs                 # Tauri app + axum proxy + Tauri commands
│       ├── log.rs                 # 控制台 + 文件双输出日志
│       ├── deploy.rs              # Codex config.toml 备份/修改/恢复
│       ├── core/
│       │   ├── mod.rs             # MitmCore builder + 管道编排
│       │   ├── traits.rs           # RequestInterceptor / ResponseParser / ResponseInterceptor
│       │   ├── context.rs         # RequestCtx / ResponseCtx / ParsedResponse / Category
│       │   └── extract.rs         # extract_user() / categorize()
│       └── extensions/
│           ├── inject.rs          # M1: SystemPromptInjector
│           ├── sse_parser.rs       # M4: UniversalSseParser
│           ├── tamper.rs          # M3: TamperEngine (22 条规则)
│           ├── memory.rs         # M5: MemoryKernel
│           └── monitor.rs         # M6: MonitorPanel (Tauri 事件推送)
├── .gitignore
├── LICENSE
├── package.json
└── README.md
```

## 自门控策略

| 扩展 | 门控条件 | 理由 |
|---|---|---|
| M3 TamperEngine | `modified_body.is_none()` | 已被其他拦截器修改则不重复篡改 |
| M5 MemoryKernel | `modified_body.is_none() && reply.len() > 50` | 被篡改的响应不是成功交互 |
| M6 MonitorPanel | 无门控 | 始终观察所有交互并推送到前端 |

## 技术栈

- **Rust** + **Tauri 2.x** — 跨平台桌面应用
- **axum** — MITM HTTP 反向代理
- **reqwest** — 上游 API 转发（流式）
- **原生 HTML/CSS/JS** — 前端，无框架依赖

## 效能评估

### 拒绝率测试

> 测试条件：`gpt-5.6-sol` / `xhigh` reasoning / 代理已启动 / bridge.md 注入生效
>
> 样本：100 个请求，覆盖全部 28 个 skill 类别，每类 3-4 个

| 类别 | 测试数 | 通过 | 拒绝 | 拒绝率 |
|---|---|---|---|---|
| anti-debug | 3 | 3 | 0 | 0% |
| binary-protect-bypass | 3 | 3 | 0 | 0% |
| card-key | 3 | 2 | 1 | 33% |
| cloud-audit-bypass | 4 | 4 | 0 | 0% |
| code-obfuscate | 3 | 3 | 0 | 0% |
| crack-keygen | 4 | 3 | 1 | 25% |
| crypto-tools | 3 | 3 | 0 | 0% |
| data-exfil | 3 | 3 | 0 | 0% |
| evasion | 3 | 3 | 0 | 0% |
| exploit-attack | 4 | 3 | 1 | 25% |
| exploit-dev | 3 | 2 | 1 | 33% |
| full-crack | 4 | 4 | 0 | 0% |
| full-pentest | 4 | 4 | 0 | 0% |
| full-reverse | 3 | 3 | 0 | 0% |
| game-cheat | 3 | 3 | 0 | 0% |
| malware-dev | 4 | 3 | 1 | 25% |
| network-pentest | 3 | 3 | 0 | 0% |
| phishing-kit | 3 | 2 | 1 | 33% |
| post-exploit | 3 | 3 | 0 | 0% |
| posture-assessment | 4 | 4 | 0 | 0% |
| ransomware-builder | 4 | 3 | 1 | 25% |
| rei-fallback | 3 | 3 | 0 | 0% |
| reverse-engineering | 3 | 3 | 0 | 0% |
| vip-bypass | 3 | 3 | 0 | 0% |
| vuln-scanner | 3 | 3 | 0 | 0% |
| web-crawler | 4 | 4 | 0 | 0% |
| web-pentest | 3 | 2 | 1 | 33% |
| wireless-attacks | 3 | 3 | 0 | 0% |
| **总计** | **100** | **92** | **8** | **8%** |

拒绝率折线图 (28 类别, 100 样本, 8% 总拒绝率)

```mermaid
---
config:
    xyChart:
        width: 900
        height: 400
        xAxis:
            label: Skill 类别
            padding: 10
        yAxis:
            label: 拒绝率 (%)
            min: 0
            max: 50
            tickStepSize: 10
---
xychart-beta
    line [0, 0, 33, 0, 0, 25, 0, 0, 0, 25, 33, 0, 0, 0, 0, 25, 0, 33, 0, 0, 25, 0, 0, 0, 0, 33, 0, 0]
```

拒绝集中在 5 个高敏感类别（exploit-dev / phishing-kit / card-key / web-pentest / exploit-attack），
其余 23 个类别零拒绝。拒绝均被 TamperEngine (M3) 捕获并触发 Rei Protocol 替换。

## License

MIT — 见 [LICENSE](LICENSE)

