<p align="center">
  <img src="assets/banner.svg" alt="WebSSH" width="500">
</p>

<p align="center">
  <strong>面向家庭实验室与团队的、可私有部署的安全 SSH / SFTP 工作台。</strong>
</p>

<p align="center">
  <a href="https://zhengwuji.github.io/web-ssh/">产品站点</a> ·
  <a href="https://github.com/zhengwuji/web-ssh/wiki">文档</a> ·
  <a href="ROADMAP.md">路线图</a> ·
  <a href="https://github.com/zhengwuji/web-ssh/pkgs/container/webssh">容器镜像</a> ·
  <a href="https://github.com/zhengwuji/web-ssh/discussions">讨论区</a>
</p>

<p align="center">
  <a href="https://github.com/zhengwuji/web-ssh/actions/workflows/tests.yml"><img src="https://github.com/zhengwuji/web-ssh/actions/workflows/tests.yml/badge.svg" alt="Tests"></a>
  <a href="https://github.com/zhengwuji/web-ssh/actions/workflows/github-code-scanning/codeql"><img src="https://github.com/zhengwuji/web-ssh/actions/workflows/github-code-scanning/codeql/badge.svg" alt="CodeQL"></a>
  <a href="https://github.com/zhengwuji/web-ssh/pkgs/container/webssh"><img src="https://img.shields.io/badge/container-GHCR-2496ED?logo=docker&logoColor=white" alt="GitHub Container Registry"></a>
  <img src="https://img.shields.io/badge/python-3.11+-3776AB?logo=python&logoColor=white" alt="Python 3.11 or newer">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2ea44f" alt="MIT License"></a>
  <a href="https://zhengwuji.github.io/web-ssh/code-graph/"><img src="https://img.shields.io/badge/Interaktive%20Code--Map-open-6f42c1" alt="Interactive code map"></a>
</p>

## 本次更新内容

- **一键命令搭建。** 新增 `install.sh`（Linux / macOS / Git Bash）与 `install.ps1`（Windows）。
  一条命令生成 `SECRET_KEY`、`.env` 与 `docker-compose.yml` 并启动服务；指令可重复执行，且从不打印密钥。
- **安全加固。**
  - 修复 6 处 `$` 锚定 `re.match` 的换行绕过（`alice\n` 曾可绕过用户名、主机名与 tmux 会话名校验），
    统一改为 `re.fullmatch` 并预编译；新增 `tests/test_input_validation_hardening.py`（58 项断言）。
  - 修复自签证书首次生成返回码 `2` 被误判为失败、导致全新部署中止启动的问题
    （`entrypoint.sh` 与两个安装脚本）。
  - 安装脚本写入精确 `CORS_ORIGINS`（含 TLS 域名与 443 隐式端口）、`ALLOW_CORS_WILDCARD=false`，
    默认 `BLOCK_INTERNAL_SSH=true`；启用 TLS 时自动 `SESSION_COOKIE_SECURE=true`。
- **效率重构。** 正则统一预编译与缓存（`host_key_store` 的动态主机模式使用 `lru_cache`）、
  下载文件名清洗改用 `str.translate`、`ssh_manager` 去除三处函数内重复 `import re`、
  `ssh_input` 热路径的字段集合提升为模块级 `frozenset`。
- **主机密钥确认。** 快速连接（Quick Connect）同样弹出主机密钥确认框；拒绝、超时或关闭表单时
  返回明确的 `host_key_unconfirmed` 错误码与本地化提示；SMB 与终端路径行为不变。
- **TLS 与监控验收。** `WEBSSH_TLS_MODE=self-signed|acme|manual` 端到端实测通过；
  监控面板在真实 Linux 会话上完成 22 项浏览器验收（渲染、4 秒轮询、语言切换、诊断抽屉）。
- **门禁状态。** `pytest` 3505 项通过（仅 3 项 Windows 环境性失败）、`npm run test:js` 693/693、
  `npm run lint:js` 0 错误、Playwright 端到端 185 项通过。

## Product tour｜产品导览

<p align="center">
  <img src="assets/webssh-demo.gif" alt="WebSSH 演示：聚焦终端、分屏会话、SFTP 文件工作区与账户安全" width="1100">
</p>

WebSSH 把终端操作、文件管理、命令集、诊断信息与笔记集中在同一个自适应浏览器工作区内。
它完全私有部署、支持多用户，不依赖任何托管控制面，也不在运行时加载 CDN 资源。

管理员可以在「设置 → 集成」中启用可选的 SSH 网关集成，随后使用 `用户名:目标` 形式的用户名
经由既有的 SSH 网关连接。该功能默认关闭，认证与目标要求见
[Warpgate 集成指南](docs/warpgate.md)。

## 使用说明

一条命令部署（Docker，推荐）：

```bash
curl -fsSL https://raw.githubusercontent.com/zhengwuji/web-ssh/main/install.sh | sh
```

Windows（PowerShell）：

```powershell
irm https://raw.githubusercontent.com/zhengwuji/web-ssh/main/install.ps1 | iex
```

可选参数：`--port`、`--dir`、`--tls off|self-signed|manual|acme`、`--domain`、`--email`、
`--allow-internal-ssh`、`--no-start`、`--no-pull`。例如启用自签 HTTPS：

```bash
./install.sh --port 8443 --tls self-signed --domain webssh.lan
```

源码运行（不依赖 Docker，构建本地虚拟环境后由 gunicorn 直接提供服务）：

```bash
git clone https://github.com/zhengwuji/web-ssh.git
cd web-ssh
./install.sh --mode source --dir /opt/webssh --port 8443 --tls self-signed --domain webssh.lan
```

安装完成后：浏览器打开 `http://localhost:5000`（或你指定的端口），首次访问时立即创建管理员账号，
`curl -fsS http://localhost:5000/ready` 应返回就绪状态。公网部署前请务必改用生产覆盖文件、
精确 Origin、安全 Cookie、关闭浏览器注册，并保留一个可用的本地应急管理员。

## Why WebSSH｜为什么选择 WebSSH

- **一个工作区，而不是一个终端标签页。** SSH 会话、SFTP 数据源、命令集、实时 Linux 状态与笔记
  始终跟随当前服务器对齐展示。
- **天生私有部署。** 账号、配置档案、加密密钥、主机信任、审计记录与应用数据全部留在你自己的
  WebSSH 实例上。
- **边界安全的运维方式。** 认证、归属校验、网络策略、主机密钥校验、配额与有界运行时任务
  都是显式设计的。
- **从手机到工作站都好用。** 同一套界面既能适配聚焦的移动终端，也能支撑多窗格桌面操作。

## Features｜功能

### Terminal workspace｜终端工作区

- 多路 SSH 会话，支持标签页与 1、2、4 窗格布局。
- 目标主机具备 tmux 时，通过 tmux 提供持久化远端 shell。
- 保存的连接、跳板机、密钥、密码与可选的 Tailscale SSH 认证路径。
- 广播输入、终端搜索、会话记录、重连控制与可配置回滚行数。
- Session-aware Files, Commands, Diagnostics, and Notes contexts（随会话联动的文件、命令、诊断与笔记上下文）。
- **Active Session Monitoring**（活动会话监控）：针对受支持 Linux 主机的资源与运行时数据采集。
- **Expanded Diagnostics**（扩展诊断）：资源历史、进程、systemd 服务与 Docker 容器。
- **Clipboard-Only Service Actions**（仅复制服务操作）：只准备白名单内的命令，不在 WebSSH 内执行服务变更。

### Files and transfers｜文件与传输

- 以数据源为核心的 SFTP，可选启用 SMB 工作区，支持独立标签页与单/双文件窗格。
- 上传、下载、预览、内联文本编辑与常用文件操作。
- 大批量传输走流式 HTTP，Socket.IO 仅承载控制事件与有界编辑器内容。
- 跨 SFTP 与 SMB 数据源的服务器间传输，带进度、取消、显式冲突处理与统一传输队列。
- 同源目录间移动不会静默覆盖已有条目。
- 稳定可见的失败原因：权限不足、冲突、数据源不可用、超时以及配置上限违规。
- 按用户归属校验、大小限制、配额与路径校验。

SMB 默认关闭（`SMB_ENABLED=false`）。启用时还必须配置精确的 `SMB_ALLOWED_TARGETS` 服务器白名单。
WebSSH 将 SMB 连接固定到 TCP 445，并要求 SMB 3.1.1、signing（签名）、encryption（加密）与安全协商；
当前认证方式为 NTLM。不支持 guest（来宾访问）、DFS、Kerberos 与 automatic reconnect（自动重连）。
SMB 凭据仅用于一次临时连接；WebSSH 从不保存密码与认证密钥（never stored）。用户可以保存不含密钥的
按用户共享定义，内容包含显示名、主机、共享名、域与用户名。

面向 Active Directory 与 TrueNAS，可先尝试 DNS 域（例如 `example.com`）配合账号名（例如 `alice`）；
或者留空域字段，改用 `alice@example.com` 形式的 UPN。并非所有服务器都接受 NetBIOS 域名。

连接后，WebSSH 会以非破坏性方式探测根目录列举、文件创建、目录创建与子项删除权限。工作区会标注
已确认可写、已确认根目录只读或权限未知；更深的 ACL 仍可能存在差异。上传与远端复制绝不静默覆盖
已有目标：替换、跳过或取消必须显式选择；当后端无法提供原子重命名时，替换将失败关闭。
SMB 把控制会话与传输会话分离，因此浏览不会被批量流阻塞。取消是单次幂等请求，已知的超限操作会同时
报告实际大小与精确的配置上限。内联 SMB 编辑保留修订校验，并在原子替换不可用时提供显式的
可恢复交换路径。受支持的 SMB 目标必须拒绝符号链接与宽链接穿越（对 Samba 使用
`follow symlinks = no` 与 `wide links = no`）；WebSSH 额外保证打开文件与目录时不跟随重解析点，
并在远端操作前校验已存在的路径组成部分。

这里存在两段信任边界：浏览器 TLS 保护 browser（浏览器）到 WebSSH 的流量，SMB 加密保护 WebSSH 到共享
的流量。WebSSH process（WebSSH 进程）必然需要处理提交的凭据与被传输的 file contents（文件内容），
因此请只在可信主机上运行，并仅白名单可信共享。

### Identity and security｜身份与安全

- 本地多用户账号，档案、密钥、文件、设置与 SSH 主机信任彼此隔离。
- 可选的 Passkey、认证器应用（TOTP）与一次性恢复码。
- 可选 OIDC、由管理员配置的 GitHub App，以及 LDAP / Active Directory 登录，采用保守的
  账号关联与保证等级处理。
- 针对受保护账户与管理变更的操作绑定确认。
- SSH 私钥加密存储与按用户的 known_hosts 决策。
- CSRF 防护、安全响应头、限流、请求体积限制、审计日志与生产环境失败关闭检查。

### Operations and administration｜运维与管理

- Docker 与 Docker Compose 部署，使用持久化数据卷。
- 用于部署检查的健康检查与就绪端点。
- 用户管理、注册开关、安全功能开关，以及结构化审计导出与保留策略。
- 原生备份与恢复，带维护模式、暂存隔离、配额、显式确认与有界执行。
- 可选的 Redis 限流计数器。
- 浏览器依赖全部内联托管、严格 CSP，且不含任何内置遥测。

## Screenshots｜界面截图

### Focused session workspace｜聚焦的会话工作区

<p align="center">
  <img src="assets/workspace-overview.png" alt="WebSSH 已连接终端，带活动会话控制与笔记工作区" width="1100">
</p>

活动会话始终居中，上下文工具随手可用。

### Multiple live sessions｜多路实时会话

<p align="center">
  <img src="assets/multi-session.png" alt="WebSSH 桌面工作区，两个实时终端窗格与四个会话标签页" width="1100">
</p>

分屏窗格让并排观察与协同操作可见，同时不会混淆会话归属与终端状态。

### File workspace｜文件工作区

<p align="center">
  <img src="assets/sftp-workspace.png" alt="WebSSH 双窗格文件工作区，带可信数据源与传输队列" width="1100">
</p>

每个窗格都有明确的数据源、端点、路径、信任状态与选中项。

<p align="center">
  <img src="assets/file-editing.gif" alt="WebSSH 文件流程：双窗格浏览、预览、编辑、保存确认与传输完成" width="1100">
</p>

### Security Center｜安全中心

<p align="center">
  <img src="assets/security-center.png" alt="WebSSH 安全中心，展示登录保证等级、SSH 主机信任、Passkey、TOTP 与恢复码" width="1100">
</p>

安全中心说明当前登录如何确认受保护变更，并把认证因子与 SSH 信任集中在同一份账户视图中。

### Mobile workspace｜移动端工作区

<p align="center">
  <img src="assets/mobile-workspace.png" alt="WebSSH 移动端终端工作区，带自适应会话控制与连接状态" width="360">
</p>

## Quick Start｜快速开始

一条命令即可完成部署（生成 `SECRET_KEY`、`.env` 与 Compose 文件并启动 WebSSH）：

```bash
curl -fsSL https://raw.githubusercontent.com/zhengwuji/web-ssh/main/install.sh | sh
```

Windows PowerShell：

```powershell
irm https://raw.githubusercontent.com/zhengwuji/web-ssh/main/install.ps1 | iex
```

安装器支持主流 Linux 发行版（Debian/Ubuntu、RHEL/Fedora/CentOS、openSUSE、Arch、Alpine），
会自动补齐缺失的 Python、pip、venv、curl、tmux 与 Docker，并自动探测包管理器。
`--mode source` 会就地构建虚拟环境、注册 systemd 服务并直接运行 gunicorn（无需 Docker）：

```bash
git clone https://github.com/zhengwuji/web-ssh.git && cd web-ssh
./install.sh --mode source --port 8443 --tls self-signed --domain webssh.lan
```

### 安装器命令一览

| 命令 | 作用 |
| --- | --- |
| `install` | 默认命令，部署并启动 WebSSH |
| `upgrade` | 拉取最新镜像或源码并重启服务 |
| `port --port PORT` | 更改网页访问端口（同时更新服务配置与 CORS Origin） |
| `reset-password --username NAME` | 重置本地账号密码，并注销该账号的全部现有会话 |
| `status` | 查看服务状态与 `/ready` 就绪探针 |
| `uninstall [--purge] [--yes]` | 停止并卸载；`--purge` 连同应用数据一起删除 |

常用示例：

```bash
./install.sh --port 8443 --tls self-signed --domain webssh.lan   # 自定义端口与 HTTPS
./install.sh --allow-internal-ssh                                # 允许连接内网/回环目标
./install.sh port --port 9000                                    # 改端口
./install.sh reset-password --username admin --generate          # 重置密码并打印新密码
./install.sh status                                              # 查看运行状态
./install.sh uninstall --purge --yes                             # 彻底卸载（含数据）
```

其他可用参数：`--dir`、`--tls off|self-signed|manual|acme`、`--domain`、`--email`、`--no-start`、
`--no-pull`、`--skip-system-deps`、`--install-docker`、`--no-install-docker`、`--from-git URL`、`--ref REF`
（后两项让 `curl | sh` 也能在没有本地检出时自动克隆源码）。安装器是幂等的，重复执行会复用已有的
`SECRET_KEY` 与 TLS 证书，且绝不打印生成的密钥。运行 `./install.sh --help` 查看完整说明。

### 安装后的使用步骤

1. 打开 `http://<主机>:<端口>`（自签 HTTPS 时浏览器会提示一次证书警告）。
2. 全新实例会跳转 `/register`，第一个在浏览器中创建的账号即成为管理员；也可用 CLI 显式创建：
   `docker compose exec webssh /app/entrypoint.sh flask --app start:app create-admin --username admin`。
3. 登录后点击「新建标签」，选择快捷连接或保存的主机，填入地址、用户名与密码即可打开终端。
4. 首次连接会弹出主机密钥确认框，核对指纹后点击接受；不确认则连接会被拒绝（不会静默信任）。
5. 右侧工作区可在 `文件 / 命令 / 诊断 / 监控 / 笔记` 之间切换，监控面板每 4 秒采样一次远程主机。
6. 验证就绪状态：`docker compose ps` 与 `curl -fsS http://localhost:5000/ready`。

也支持手工部署：

```bash
mkdir webssh-deployment && cd webssh-deployment
curl -O https://raw.githubusercontent.com/zhengwuji/web-ssh/main/docker-compose.yml
docker compose up -d
```

面向公网的实例不要原样暴露这套家庭实验室配置。请使用生产覆盖文件、HTTPS 反向代理、精确 Origin、
安全 Cookie、关闭浏览器注册、阻断内网目标，并显式配置可信代理。

在接纳用户之前，请阅读 [Quick Start](https://github.com/zhengwuji/web-ssh/wiki/Quick-Start)
或完整的 [Production Deployment](https://github.com/zhengwuji/web-ssh/wiki/Production-Deployment)
指南。可选的 `docker-compose.hardened.yml` 覆盖文件、可写路径、可配置资源预算与
LDAP / Tailscale 约束见[生产容器边界](docs/production-container.md)。

## Security Boundary｜安全边界

<p align="center">
  <img src="docs/media/diagrams/system-trust-boundaries.png" alt="WebSSH 信任边界：从浏览器经由单一应用进程到受管的 SSH 与 SFTP 目标" width="1100">
</p>

WebSSH 属于可信基础设施。它在建立与维持 SSH、SFTP 会话的过程中会处理连接凭据、终端输入输出与
文件数据；它不是对会话内容不可见的端到端加密中继。

请保持以下部署契约：

- 在可信边界终止 HTTPS，并保护 WebSSH 主机、数据卷、日志、备份与管理員账户。
- 在信任 SSH 主机密钥指纹之前先核对，并对意外变更展开排查。
- 生产环境只使用 **一个 Gunicorn `gthread` worker**。实时 SSH 状态与部分资源协调是进程内的；
  在没有外部会话状态架构的前提下，不支持多 worker 或多副本。
- 线程数、socket 准入、每用户 socket 上限、后台 worker 与配额共同构成一套容量模型，
  请为 HTTP 保留余量。
- 外部 OIDC 或 LDAP 身份永远不会绕过本地账号、归属与授权模型。请保留一个经过验证的本地
  应急管理员。
- 备份可能同时包含持久化应用密钥与加密私钥，请相应保护并测试。

在把 WebSSH 暴露给不可信网络之前，请阅读
[安全模型与加固](https://github.com/zhengwuji/web-ssh/wiki/Security-Model-and-Hardening)
指南与项目的[安全策略](SECURITY.md)。

## Documentation｜文档

README 是项目入口。详细的安装、运维、安全、认证、恢复与开发指引位于
[WebSSH Wiki](https://github.com/zhengwuji/web-ssh/wiki)。
它的 [versioned source](docs/wiki/Home.md)（版本化源文件）随代码一起通过 Pull Request 评审，并在变更进入 `main`
后自动发布。

| 目标 | 指南 |
|---|---|
| 用 Docker 安装 | [Docker 与 Docker Compose](https://github.com/zhengwuji/web-ssh/wiki/Docker-and-Docker-Compose) |
| 部署在 HTTPS 之后 | [生产部署](https://github.com/zhengwuji/web-ssh/wiki/Production-Deployment) |
| 配置每一项设置 | [配置参考](https://github.com/zhengwuji/web-ssh/wiki/Configuration-Reference) |
| 连接并校验主机 | [SSH 连接与主机密钥](https://github.com/zhengwuji/web-ssh/wiki/SSH-Connections-and-Host-Keys) |
| 使用终端与 tmux 会话 | [终端与持久化 tmux 会话](https://github.com/zhengwuji/web-ssh/wiki/Terminal-and-Persistent-tmux-Sessions) |
| 处理文件与传输 | [SFTP 文件工作区与传输](https://github.com/zhengwuji/web-ssh/wiki/SFTP-File-Workspace-and-Transfers) |
| 配置认证 | [认证总览](https://github.com/zhengwuji/web-ssh/wiki/Authentication-Overview) |
| 执行备份或恢复 | [备份、恢复与密钥轮换](https://github.com/zhengwuji/web-ssh/wiki/Backup-Restore-and-Secret-Rotation) |
| 排查健康检查问题 | [健康检查与故障排除](https://github.com/zhengwuji/web-ssh/wiki/Health-Checks-and-Troubleshooting) |
| 理解运行时 | [架构与运行时生命周期](https://github.com/zhengwuji/web-ssh/wiki/Architecture-and-Runtime-Lifecycle) |
| 本地开发与测试 | [开发与测试](https://github.com/zhengwuji/web-ssh/wiki/Development-and-Testing) |

其他项目视图：

- [路线图与当前发布重点](ROADMAP.md)
- [项目历史与已记录的决策](docs/project-history.md)
- [规划、里程碑与发布流程](docs/project-planning.md)
- [产品站点](https://zhengwuji.github.io/web-ssh/)
- [交互式代码图谱](https://zhengwuji.github.io/web-ssh/code-graph/)
- [容器镜像](https://github.com/zhengwuji/web-ssh/pkgs/container/webssh)

## Contributing and Support｜贡献与支持

欢迎提交缺陷报告与聚焦的 Pull Request。若要提出功能建议或架构想法，请先在
[GitHub Discussions](https://github.com/zhengwuji/web-ssh/discussions) 发起讨论，
以便在动手实现之前先评审安全与运行时边界。

- 阅读[开发与测试](https://github.com/zhengwuji/web-ssh/wiki/Development-and-Testing)。
- 可复现的缺陷请走 [Issues](https://github.com/zhengwuji/web-ssh/issues)。
- 漏洞请通过
  [GitHub Security Advisories](https://github.com/zhengwuji/web-ssh/security/advisories/new)
  私下上报。

## Star History｜Star 记录

[![Star History Chart](https://api.star-history.com/chart?repos=zhengwuji/web-ssh&type=date&legend=top-left)](https://www.star-history.com/?repos=zhengwuji%2Fweb-ssh&type=date&legend=top-left)

## License｜许可证

WebSSH 基于 [MIT 许可证](LICENSE) 发布。
