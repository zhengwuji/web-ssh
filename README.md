<p align="center">
  <img src="assets/banner.svg" alt="WebSSH" width="500">
</p>

<p align="center">
  <strong>A secure, self-hosted SSH and SFTP workspace for homelabs and teams.</strong>
</p>

<p align="center">
  <a href="https://zhengwuji.github.io/web-ssh/">Product site</a> ·
  <a href="https://github.com/zhengwuji/web-ssh/wiki">Documentation</a> ·
  <a href="ROADMAP.md">Roadmap</a> ·
  <a href="https://github.com/zhengwuji/web-ssh/pkgs/container/webssh">Container image</a> ·
  <a href="https://github.com/zhengwuji/web-ssh/discussions">Discussions</a>
</p>

<p align="center">
  <a href="https://github.com/zhengwuji/web-ssh/actions/workflows/tests.yml"><img src="https://github.com/zhengwuji/web-ssh/actions/workflows/tests.yml/badge.svg" alt="Tests"></a>
  <a href="https://github.com/zhengwuji/web-ssh/actions/workflows/github-code-scanning/codeql"><img src="https://github.com/zhengwuji/web-ssh/actions/workflows/github-code-scanning/codeql/badge.svg" alt="CodeQL"></a>
  <a href="https://github.com/zhengwuji/web-ssh/pkgs/container/webssh"><img src="https://img.shields.io/badge/container-GHCR-2496ED?logo=docker&logoColor=white" alt="GitHub Container Registry"></a>
  <img src="https://img.shields.io/badge/python-3.11+-3776AB?logo=python&logoColor=white" alt="Python 3.11 or newer">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-2ea44f" alt="MIT License"></a>
  <a href="https://zhengwuji.github.io/web-ssh/code-graph/"><img src="https://img.shields.io/badge/Interaktive%20Code--Map-open-6f42c1" alt="Interactive code map"></a>
</p>

## Product tour

<p align="center">
  <img src="assets/webssh-demo.gif" alt="WebSSH tour showing a focused terminal, split sessions, the SFTP workspace, and account security" width="1100">
</p>

WebSSH keeps terminal work, files, commands, diagnostics, and notes in one
responsive browser workspace. It is self-hosted, multi-user, and built without
a hosted control plane or runtime CDN dependencies.

After an administrator enables the optional gateway integration in Settings → Integrations,
connect through an existing SSH gateway with a user:target username. Disabled by default. See the
[Warpgate integration guide](docs/warpgate.md) for authentication and target requirements.

## 中文说明：本次更新与使用

### 本次更新内容

- **一键命令搭建。** 新增 `install.sh`（Linux/macOS/Git Bash）与 `install.ps1`（Windows）。
  一条命令生成 `SECRET_KEY`、`.env` 与 `docker-compose.yml` 并启动服务；可重复执行，且从不打印密钥。
- **安全加固。**
  - 修复 6 处 `$` 锚定 `re.match` 的换行绕过（`alice\n` 曾能通过用户名、主机名与 tmux 名校验），
    统一改为 `re.fullmatch` 并预编译；新增 `tests/test_input_validation_hardening.py`（58 项断言）。
  - TLS 自签证书首次生成返回码 `2` 被误判为失败的问题，已在 `entrypoint.sh` 与安装脚本中修复。
  - 安装脚本写入精确 `CORS_ORIGINS`、`ALLOW_CORS_WILDCARD=false`，默认 `BLOCK_INTERNAL_SSH=true`；
    启用 TLS 时自动 `SESSION_COOKIE_SECURE=true`，并补上真实域名的 Origin 白名单。
- **效率重构。** 正则统一预编译与缓存（`host_key_store` 的动态主机模式使用 `lru_cache`）、
  下载文件名清洗改用 `str.translate`、`ssh_manager` 去除三处函数内重复 `import re`、
  `ssh_input` 热路径的字段集合提升为模块级 `frozenset`。
- **主机密钥确认。** 快速连接（Quick Connect）同样弹出主机密钥确认框；拒绝、超时或关闭表单时
  返回明确的 `host_key_unconfirmed` 错误码与本地化提示；SMB 与终端路径行为不变。
- **TLS 与监控验收。** `WEBSSH_TLS_MODE=self-signed|acme|manual` 端到端实测通过；
  监控面板在真实 Linux 会话上完成 22 项浏览器验收（渲染、4 秒轮询、语言切换、诊断抽屉）。
- **门禁状态。** `pytest` 3503 项通过（仅 3 项 Windows 环境性失败）、`npm run test:js` 693/693、
  `npm run lint:js` 0 错误、Playwright 端到端 185 项通过。

### 使用说明

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

## Why WebSSH

- **One workspace, not a terminal tab.** Keep SSH sessions, SFTP sources,
  commands, live Linux context, and notes aligned with the active server.
- **Self-hosted by design.** Accounts, profiles, encrypted keys, host trust,
  audit records, and application data remain on your WebSSH instance.
- **Safe operational boundaries.** Authentication, ownership checks, network
  policy, host-key verification, quotas, and bounded runtime work are explicit.
- **Useful from phone to workstation.** The same interface adapts from a focused
  mobile shell to multi-pane desktop operations.

## Features

### Terminal workspace

- Multiple SSH sessions with tabs and 1-, 2-, or 4-pane layouts.
- Persistent remote shells through tmux when tmux is available on the target.
- Saved connections, jump hosts, key, password, and optional Tailscale SSH
  authentication paths.
- Broadcast input, terminal search, transcripts, reconnect controls, and
  configurable scrollback.
- Session-aware Files, Commands, Diagnostics, and Notes contexts.
- **Active Session Monitoring** for supported Linux resource and runtime data.
- **Expanded Diagnostics** for resource history, processes, systemd services,
  and Docker containers.
- **Clipboard-Only Service Actions** that prepare allowlisted commands without
  executing the service change inside WebSSH.

### Files and transfers

- Source-first SFTP and opt-in SMB workspace with independent tabs and one or
  two file panes.
- Uploads, downloads, previews, inline text editing, and common file operations.
- Streamed HTTP bulk transfers with Socket.IO limited to control events and
  bounded editor content.
- Server-to-server transfers across SFTP and SMB sources with progress,
  cancellation, explicit conflict handling, and a shared transfer queue.
- Same-source moves between folders without silently replacing existing items.
- Stable, visible transfer reasons such as permission denied, conflict,
  unavailable source, timeout, and configured-limit violations.
- Per-user ownership checks, size limits, quotas, and path validation.

SMB is disabled by default (`SMB_ENABLED=false`). Enabling it also requires an
exact `SMB_ALLOWED_TARGETS` server allowlist. WebSSH fixes SMB connections to
TCP 445 and requires SMB 3.1.1, signing, encryption, and secure negotiation;
the current authentication mode is NTLM. Guest access, DFS, Kerberos, and
automatic reconnect are not supported. SMB credentials are used for one
temporary connection. Passwords and authentication secrets are never stored by
WebSSH. Users may save non-secret, per-user share definitions containing a
display name, host, share, domain, and username.

For Active Directory and TrueNAS, first try the DNS domain (for example
`example.com`) with the account name (for example `alice`). Alternatively,
leave the domain field empty and use a UPN such as `alice@example.com`. NetBIOS
domain names may not be accepted by every server.

After connecting, WebSSH non-destructively checks root listing, file creation,
directory creation, and child deletion access. The workspace labels confirmed
write access, confirmed root read-only access, or unknown access; deeper ACLs
can still differ. Uploads and remote copies never silently overwrite an
existing destination: replace, skip, or cancel requires an explicit choice,
and replacement fails closed when the backend cannot provide an atomic rename.
SMB uses separate control and transfer sessions so browsing does not wait for a
bulk stream. Cancellation is a single idempotent request, and known oversized
operations report both the actual size and exact configured limit. Inline SMB
editing preserves revision checks and offers an explicit recoverable-swap path
when atomic replacement is unavailable.
Supported SMB targets must refuse symlink and wide-link traversal (for Samba,
use `follow symlinks = no` and `wide links = no`). WebSSH additionally opens
files and directories without following reparse points and validates existing
path components before remote operations.

This is a two-link trust boundary: browser TLS protects browser-to-WebSSH
traffic, while SMB encryption protects WebSSH-to-share traffic. The WebSSH process
necessarily handles the submitted credentials and transferred file contents, so
run it only on a trusted host and allowlist only trusted shares.

### Identity and security

- Local multi-user accounts with isolated profiles, keys, files, settings, and
  SSH host trust.
- Optional Passkeys, authenticator apps (TOTP), and one-time Recovery Codes.
- Optional OIDC, admin-configured GitHub App, and LDAP/Active Directory sign-in with conservative account
  linking and assurance handling.
- Action-bound confirmation for protected account and administrative changes.
- Encrypted SSH private-key storage and per-user known-host decisions.
- CSRF protection, secure response headers, rate limits, request limits, audit
  logging, and production fail-closed checks.

### Operations and administration

- Docker and Docker Compose deployment with a persistent data volume.
- Health and readiness endpoints for deployment checks.
- User administration, registration controls, security feature gates, and
  structured audit export and retention.
- Native backup and restore with maintenance mode, staging isolation, quotas,
  explicit confirmation, and bounded execution.
- Optional Redis-backed rate-limit counters.
- Vendored browser dependencies, restrictive CSP, and no built-in telemetry.

## Screenshots

### Focused session workspace

<p align="center">
  <img src="assets/workspace-overview.png" alt="Connected WebSSH terminal with active-session controls and a notes workspace" width="1100">
</p>

The active session stays central while contextual tools remain close at hand.

### Multiple live sessions

<p align="center">
  <img src="assets/multi-session.png" alt="WebSSH desktop workspace with two live terminal panes and four session tabs" width="1100">
</p>

Split panes make side-by-side observation and coordinated work visible without
mixing session ownership or terminal state.

### File workspace

<p align="center">
  <img src="assets/sftp-workspace.png" alt="WebSSH dual-pane file workspace with trusted sources and a transfer queue" width="1100">
</p>

Each pane has an explicit source, endpoint, path, trust state, and selection.

<p align="center">
  <img src="assets/file-editing.gif" alt="WebSSH file workflow from dual-pane browsing through preview, editing, save confirmation, and transfer completion" width="1100">
</p>

### Security Center

<p align="center">
  <img src="assets/security-center.png" alt="WebSSH Security Center showing sign-in assurance, SSH host trust, Passkeys, TOTP, and Recovery Codes" width="1100">
</p>

The Security Center explains how the current sign-in confirms protected
changes and keeps factors and SSH trust in one account-owned view.

### Mobile workspace

<p align="center">
  <img src="assets/mobile-workspace.png" alt="WebSSH mobile terminal workspace with responsive session controls and connection status" width="360">
</p>

## Quick Start

The supplied Compose file is intended for evaluation and trusted homelab
networks. It stores the database, generated application secret, user data, and
encrypted keys in the `webssh_data` volume.

One command prepares a deployment directory (generated `SECRET_KEY`, `.env`,
Compose file) and starts WebSSH:

```bash
curl -fsSL https://raw.githubusercontent.com/zhengwuji/web-ssh/main/install.sh | sh
```

On Windows:

```powershell
irm https://raw.githubusercontent.com/zhengwuji/web-ssh/main/install.ps1 | iex
```

Both installers accept `--port`, `--dir`, `--tls off|self-signed|manual|acme`,
`--domain`, `--allow-internal-ssh`, `--no-start`, and `--no-pull`. They are
idempotent and never print the generated secret.

Or do it by hand:

```bash
mkdir webssh-deployment
cd webssh-deployment
curl -O https://raw.githubusercontent.com/zhengwuji/web-ssh/main/docker-compose.yml
docker compose up -d
```

Open <http://localhost:5000>. On a new instance, create the first administrator
immediately from a trusted network. The one-time browser bootstrap closes after
that account exists.

Verify the container and readiness endpoint:

```bash
docker compose ps
curl -fsS http://localhost:5000/ready
```

The installer also supports `--mode source`, which builds a local virtualenv
from a source checkout and runs gunicorn directly. It enables HTTPS with a
self-signed certificate in one step:

```bash
git clone https://github.com/zhengwuji/web-ssh.git
cd webssh
./install.sh --mode source --port 8443 --tls self-signed --domain webssh.lan
```

For an Internet-facing instance, do not expose this homelab configuration
unchanged. Use the production overlay, an HTTPS reverse proxy, exact origins,
secure cookies, disabled browser registration, internal-target blocking, and
explicit trusted-proxy settings.

Read the [Quick Start](https://github.com/zhengwuji/web-ssh/wiki/Quick-Start) or
the complete [Production Deployment](https://github.com/zhengwuji/web-ssh/wiki/Production-Deployment)
guide before accepting users. See [production container boundaries](docs/production-container.md)
for the optional `docker-compose.hardened.yml` overlay, writable paths,
configurable resource budgets, and LDAP/Tailscale constraints.

## Security Boundary

<p align="center">
  <img src="docs/media/diagrams/system-trust-boundaries.png" alt="WebSSH trust boundaries from the browser through the single application process to owned SSH and SFTP targets" width="1100">
</p>

WebSSH is trusted infrastructure. It processes connection credentials,
terminal input and output, and file data while establishing and maintaining SSH
and SFTP sessions. It is not an end-to-end encrypted relay that is blind to
session contents.

Keep these deployment contracts intact:

- Terminate HTTPS at a trusted boundary and protect the WebSSH host, data
  volume, logs, backups, and administrator accounts.
- Review SSH host-key fingerprints before trusting them and investigate
  unexpected changes.
- Production uses exactly **one Gunicorn `gthread` worker**. Live SSH state and
  part of the resource coordination are process-local; multiple workers or
  replicas are not supported without an external session-state architecture.
- Thread count, socket admission, per-user socket limits, background workers,
  and quotas form one capacity model. Keep HTTP capacity reserved.
- External OIDC or LDAP identity never bypasses the local account, ownership,
  or authorization model. Retain a tested local break-glass administrator.
- Backups can contain the persisted application secret and encrypted private
  keys together. Protect and test them accordingly.

See the [Security Model and Hardening](https://github.com/zhengwuji/web-ssh/wiki/Security-Model-and-Hardening)
guide and the project's [security policy](SECURITY.md) before exposing WebSSH
to untrusted networks.

## Documentation

The README is the project entry point. Detailed installation, operation,
security, authentication, recovery, and development guidance lives in the
[WebSSH Wiki](https://github.com/zhengwuji/web-ssh/wiki). Its
[versioned source](docs/wiki/Home.md) is reviewed with the code through pull
requests and published automatically after changes reach `main`.

| Goal | Guide |
|---|---|
| Install with Docker | [Docker and Docker Compose](https://github.com/zhengwuji/web-ssh/wiki/Docker-and-Docker-Compose) |
| Deploy behind HTTPS | [Production Deployment](https://github.com/zhengwuji/web-ssh/wiki/Production-Deployment) |
| Configure every setting | [Configuration Reference](https://github.com/zhengwuji/web-ssh/wiki/Configuration-Reference) |
| Connect and verify hosts | [SSH Connections and Host Keys](https://github.com/zhengwuji/web-ssh/wiki/SSH-Connections-and-Host-Keys) |
| Use terminal and tmux sessions | [Terminal and Persistent tmux Sessions](https://github.com/zhengwuji/web-ssh/wiki/Terminal-and-Persistent-tmux-Sessions) |
| Work with files and transfers | [SFTP File Workspace and Transfers](https://github.com/zhengwuji/web-ssh/wiki/SFTP-File-Workspace-and-Transfers) |
| Configure authentication | [Authentication Overview](https://github.com/zhengwuji/web-ssh/wiki/Authentication-Overview) |
| Run backup or restore | [Backup, Restore and Secret Rotation](https://github.com/zhengwuji/web-ssh/wiki/Backup-Restore-and-Secret-Rotation) |
| Troubleshoot health checks | [Health Checks and Troubleshooting](https://github.com/zhengwuji/web-ssh/wiki/Health-Checks-and-Troubleshooting) |
| Understand the runtime | [Architecture and Runtime Lifecycle](https://github.com/zhengwuji/web-ssh/wiki/Architecture-and-Runtime-Lifecycle) |
| Develop and test locally | [Development and Testing](https://github.com/zhengwuji/web-ssh/wiki/Development-and-Testing) |

Additional project views:

- [Roadmap and current release focus](ROADMAP.md)
- [Project history and documented decisions](docs/project-history.md)
- [Planning, milestones and release workflow](docs/project-planning.md)
- [Product site](https://zhengwuji.github.io/web-ssh/)
- [Interactive code graph](https://zhengwuji.github.io/web-ssh/code-graph/)
- [Container image](https://github.com/zhengwuji/web-ssh/pkgs/container/webssh)

## Contributing and Support

Bug reports and focused pull requests are welcome. For feature proposals and
architecture ideas, start with [GitHub Discussions](https://github.com/zhengwuji/web-ssh/discussions)
so the security and runtime boundaries can be reviewed before implementation.

- Read [Development and Testing](https://github.com/zhengwuji/web-ssh/wiki/Development-and-Testing).
- Use [Issues](https://github.com/zhengwuji/web-ssh/issues) for reproducible bugs.
- Report vulnerabilities privately through
  [GitHub Security Advisories](https://github.com/zhengwuji/web-ssh/security/advisories/new).

## Star History

[![Star History Chart](https://api.star-history.com/chart?repos=zhengwuji/web-ssh&type=date&legend=top-left)](https://www.star-history.com/?repos=zhengwuji%2Fweb-ssh&type=date&legend=top-left)

## License

WebSSH is available under the [MIT License](LICENSE).
