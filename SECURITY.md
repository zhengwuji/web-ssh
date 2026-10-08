# 安全策略

## 支持版本

| 版本 | 是否支持 |
| ---- | -------- |
| 最新版 | :white_check_mark: |

## 上报漏洞

本项目严肃对待安全。如果你在 WebSSH 中发现安全漏洞，请以负责任的方式上报。

### 如何上报

**请不要为安全漏洞提交公开的 GitHub Issue。**

请通过以下方式上报：

- **GitHub 安全公告：**[上报漏洞](https://github.com/zhengwuji/web-ssh/security/advisories/new)

### 请包含哪些信息

- 漏洞描述
- 复现步骤
- 潜在影响
- 建议的修复方式（如有）

### 响应时间线

- **首次响应：** 48 小时内
- **状态更新：** 7 天内
- **修复目标：** 30 天内（视复杂程度而定）

### 披露政策

- 在公开披露之前，请给我合理的修复时间
- 我会在发布说明中致谢上报者（除非你希望保持匿名）

## 安全模型

### 认证与授权

| 功能 | 实现方式 |
| ---- | -------- |
| 密码哈希 | bcrypt 加自动生成的盐 |
| 会话管理 | Flask-Login 加安全 Cookie |
| WebSocket 认证 | 基于会话，并校验归属 |
| CSRF 防护 | 所有表单使用 Flask-WTF 令牌 |
| 限流 | 每个 IP 每分钟 5 次登录尝试 |
| 通行密钥 | 可选 WebAuthn，校验精确的 RP ID/Origin、用户验证与一次性服务端挑战 |
| TOTP | 可选认证器应用多因素认证，按用户加密密钥、限制注册次数、防重放地消费时间步 |
| 恢复 | 一次性恢复码静态哈希存储；仅在主认证成功后可用，并在因子替换或显式关闭多因素认证前受限 |
| LDAP | 可选 StartTLS/LDAPS 认证，带证书校验、稳定的目录身份与失败关闭的会话再校验 |
| OIDC | 可选授权码流程，带 PKCE、nonce/state 校验、显式的 issuer/subject 关联，以及运维方定义的签名 `acr`/`amr` 保证等级 |
| GitHub | 可选由管理员配置的 GitHub App 流程，带 PKCE、服务端一次性 state、不可变的数字身份关联、失败关闭的组织策略，且只能开通非管理员账号 |
| 管理员二次确认 | 一次性五分钟授权，绑定当前认证会话、精确操作、精确目标与所需保证等级 |

### 数据保护

| 数据 | 保护方式 |
| ---- | -------- |
| SSH 私钥 | 使用 Fernet（AES-128-CBC + HMAC）静态加密 |
| GitHub 客户端密钥 | 使用由持久化 `SECRET_KEY` 派生、带域分隔的密钥在应用数据库中加密；在管理 API 中只可写入 |
| 密钥派生 | PBKDF2-SHA256，600,000 次迭代 |
| 按用户隔离 | 密钥由 `SECRET_KEY + user_id` 派生 |
| 文件权限 | 密钥以 0600 存储，目录以 0700 存储 |

### 网络安全

| 功能 | 实现方式 |
| ---- | -------- |
| 安全响应头 | CSP、X-Frame-Options（DENY）、X-Content-Type-Options、HSTS |
| CORS | 可配置；未设置时默认仅允许 localhost |
| WebSocket | 需认证，按用户房间隔离 |
| 反向代理 | 通过 `TRUSTED_PROXIES` 支持 ProxyFix |
| 请求体 | 非安全控制类请求在 CSRF 解析前限制为 64 KiB；恢复功能为 4 KiB，WebAuthn 为 64 KiB，SFTP 上传保留其独立的流式限制 |

### SSH 安全

| 功能 | 实现方式 |
| ---- | -------- |
| 主机密钥校验 | 首次使用即信任（TOFU），带持久化存储 |
| 主机密钥日志 | 新密钥连同指纹写入审计，便于复核 |
| 凭据处理 | 使用后从内存中清除 |
| 存储密钥操作 | 连接尝试限流先于存储密钥的 PBKDF2/解密；加密密钥库设有原子计数与字节增长上限 |
| 远端剪贴板 | 持久化 tmux 的 OSC 52 请求需要一次全新的、可见的浏览器操作；重放输出与普通 SSH 输出无法写入剪贴板 |
| 实时输出 | 按浏览器 ACK 计数，并结合每 socket、每用户与全局上限对 SSH 施加背压；浏览器卡死会被断连，但不会关闭其 SSH/tmux 会话 |

## 部署安全最佳实践

### 必须做到

1. **选择并满足生产安全配置文件**
   ```bash
   export DEPLOYMENT_PROFILE=production
   export DEBUG=False
   export CORS_ORIGINS=https://ssh.example.com
   export ALLOW_CORS_WILDCARD=false
   export SESSION_COOKIE_SECURE=true
   export REGISTRATION_ENABLED=False
   export BLOCK_INTERNAL_SSH=true
   export TRUSTED_PROXIES=1
   ```
   若这些边界不安全或含糊，生产启动会失败关闭。只有在不信任任何代理头时才显式设置
   `TRUSTED_PROXIES=0`。TLS 在代理处终止时仍然要求安全 Cookie。
   信任代理头时，请把后端端口限制给该代理。随附的生产 Compose 覆盖文件把它绑定到
   `127.0.0.1:5000`；容器化反向代理请使用私有、不对外发布的网络。

2. **设置强 `SECRET_KEY`**
   ```bash
   export SECRET_KEY=$(openssl rand -hex 32)
   ```

3. **初始化第一个管理员**
   ```bash
   flask --app start:app create-admin --username admin
   ```
   使用 Docker Compose 时执行：
   ```bash
   docker compose exec webssh /app/entrypoint.sh flask --app start:app create-admin --username admin
   ```
   该命令会提示输入密码且不回显。推荐在生产环境使用这条显式路径（生产环境已关闭公开注册）。
   若运维方在全新安装上启用了注册，第一个注册的账号会成为管理员，之后所有账号都只是普通用户。
   切勿把尚未认领的全新实例暴露给不可信网络。

4. **使用 TLS** —— 部署在带 HTTPS 的反向代理之后

5. **设置明确的 CORS Origin**
   ```bash
   export CORS_ORIGINS=https://your-domain.com
   ```

### 建议做到

6. **把 `TRUSTED_PROXIES` 设为可信代理层的精确层数**
   ```bash
   export TRUSTED_PROXIES=1
   ```

7. **限制网络访问** —— 不要在无保护的情况下直接暴露到公网

8. **定期更新** —— 保持容器镜像为最新版本

9. **创建并校验离线备份**
   ```bash
   flask --app start:app backup create \
     --destination /secure-backups/webssh.zip \
     --confirm-offline
   flask --app start:app backup verify /secure-backups/webssh.zip
   ```
   在执行创建、恢复或轮换操作前，请停止所有使用该 `DATA_DIR` 的 WebSSH 进程。
   备份包含安全敏感数据，可能含持久化的 `SECRET_KEY`；请单独加密、限制访问，并定义保留与安全删除策略。

10. **只轮换持久化的应用密钥**
    ```bash
    flask --app start:app rotate-secret-key --confirm-offline
    ```
    该命令会先创建并校验备份，逐项暂存并校验重新加密的 SSH 密钥，最后才发布
    `DATA_DIR/secret_key`。它会拒绝外部提供但持久化文件中缺失或不一致的密钥。
    由外部密钥管理服务持有的密钥，请通过该服务与单独控制的密钥迁移流程轮换。

11. **保留一个经过验证的本地应急管理员**
    OIDC 与 LDAP 受部署开关约束，GitHub App 认证则在管理面板中运行时配置。
    任何身份提供方都可能独立于 WebSSH 发生故障。请至少保留一个本地管理员，
    使用强密码并已测试通行密钥或 TOTP 因子，把其恢复码离线保存。
    由 GitHub 开通的账号永远不能成为管理员。

### 可选的多因素认证与保证等级

多因素认证并非全局强制。账号会继续使用原有登录方式，直到该用户注册通行密钥或认证器应用
并显式启用多因素认证。LDAP 用户可在近期完成目录登录后注册本地 WebSSH 因子；
其目录密码既不会被保留，也不会被转换为本地密码。

除非签名声明与提供方专属的 `OIDC_MFA_*` 或 `OIDC_PHISHING_RESISTANT_*` 配置精确匹配，
OIDC 认证都只算基础保证等级。不要从其他提供方复制声明值。请先核实提供方的令牌契约与
条件访问/认证策略，再分别测试正向与反向声明。移动端推送是身份提供方的能力，不是 WebSSH 的推送服务。
管理员在提供方重新认证时会请求 `prompt=login`、`max_age=0` 以及配置的 `OIDC_STEP_UP_ACR_VALUES`。

恢复码不能替代主凭据。在密码或 LDAP 主步骤成功之后，一个恢复码会创建一个受限的恢复会话。
此时仅可使用安全页面、替换因子注册、显式关闭多因素认证、登出以及必需的静态资源。
恢复码以原子方式消费，无法重放。

敏感的管理变更需要与操作绑定的二次确认。授权是不透明的，服务端只保存哈希，在路由执行前即被消费，
且绝不会存入浏览器的本地/会话存储。规则或功能开关的变更不会终止现有浏览器或 SSH 会话：
受影响的用户会在后续认证/注册时获得新策略，而进行中的 SSH 工作会按配置的正常会话生命周期结束。
显式的账号锁定、删除与多因素重置操作仍会按文档所述撤销目标账号。

### 容器安全

Docker 镜像以非 root 用户（`appuser`）运行，并具备：

- 受限的文件权限（数据目录为 0700）
- 不保留多余的内核能力
- 启用健康检查
- Gunicorn 26 `gthread` 运行时，恰好一个 worker，并使用有界、可配置的 `GUNICORN_THREADS`（默认 64）
- 只使用原生 Socket.IO 线程模型；不使用 Eventlet worker，也不做 monkey patching

`greenlet` 之所以可能出现在通用锁文件中，仅因为 SQLAlchemy 把它声明为带平台标记的传递依赖。
它不是一个可选的 WebSSH 运行时，也不能被单独移除；改动该依赖图需要其自身经过评审的 SQLAlchemy 升级。

请按已记录的镜像仓库摘要保留此前部署的不可变镜像，作为 Gunicorn-26 运行时的纯镜像回滚产物。
使用现有的 `/app/data` 卷重新部署它，并验证就绪状态、登录、已存储密钥、终端与 SFTP。
成功发布后会保留一个经过验证的 `image-release-<commit-sha>` Actions 产物，其中包含该不可变镜像引用，
保留 90 天。请在升级前保存当前已部署版本的产物。无需对持久化数据做回滚或格式重写。

## 已知限制

| 限制 | 说明 | 缓解措施 |
| ---- | ---- | -------- |
| 内存内限流 | 多 worker 时会被绕过 | 使用单 worker（默认） |
| TOFU 主机密钥 | 首次连接自动接受 | 通过日志复核新的主机密钥 |
| 受部署开关约束的身份功能 | 通行密钥、TOTP、OIDC 与 LDAP 同时需要部署允许与管理员启用 | 配置精确的 Origin/提供方设置，验证就绪状态，并在启用前保持本地管理员恢复流程经过测试 |
| 运行时 GitHub 认证 | 错误的回调、被撤销的客户端密钥、缺少组织权限或 GitHub 故障都会阻止提供方登录 | 在管理面板中配置 GitHub App，使用精确回调，验证组织策略，并保持本地管理员恢复流程经过测试 |
| OIDC 声明语义不一致 | `acr` 与 `amr` 没有通用的保证等级含义 | 只对已配置提供方文档化并测试过的值做白名单；否则 WebSSH 会把该登录视为基础保证等级 |
| 进程内实时会话 | 活动 SSH 状态要求恰好一个 WebSSH worker | 保持文档所述的单 `gthread` worker，并使用正常会话生命周期，而非由策略触发的批量终止 |

## 安全审计

本项目尚未经过正式的第三方安全审计。代码已按安全最佳实践进行评审，但在高安全环境中使用时
仍应追加额外评审。

## 变更记录

与安全相关的改动会在发布说明中以 `[SECURITY]` 标记记录。
