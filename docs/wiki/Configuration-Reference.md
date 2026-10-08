# 配置参考

WebSSH 从环境变量读取配置。本地 `.env` 文件以 `override=False` 加载，因此由操作系统、容器运行时或机密管理器提供的变量优先。

请从仓库的 `.env.example` 开始。下表描述了运维契约；升级时请检查该文件，因为可能会新增选项。

## 核心设置

| 变量 | 用途 | 默认值或要求 |
|---|---|---|
| `SECRET_KEY` | 加密并签名安全敏感状态 | 直接以生产模式启动时为必需。容器入口点可以生成它并将其持久化到数据卷中。 |
| `DATA_DIR` | 规范的 SQLite、密钥、日志与生成机密的根目录 | 容器中为 `/app/data`；容器覆盖值必须是绝对路径且持久 |
| `DEPLOYMENT_PROFILE` | 选择部署防护措施 | `homelab`；面向 Internet 的部署请使用 `production` |
| `DEBUG` | Flask 调试模式 | `False`；绝不要在生产环境启用 |
| `HOST` | 应用绑定地址 | 容器外为 `127.0.0.1` |
| `PORT` | 应用监听端口 | `5000` |
| `APPLICATION_ROOT` | 子目录部署的 URL 前缀 | 空/根 |

请将 `SECRET_KEY` 视为长期存续的安装状态。在没有受支持的轮换工作流的情况下替换它，会使加密的 SSH 密钥与已签名状态失效。请参阅 [备份、恢复与机密轮换](Backup-Restore-and-Secret-Rotation)。

## 浏览器源、代理与 cookie

| 变量 | 用途 |
|---|---|
| `CORS_ORIGINS` | 逗号分隔的 Socket.IO/浏览器源允许列表 |
| `ALLOW_CORS_WILDCARD` | 允许 `*`；仅限家庭实验室，且作为生产源策略会被拒绝 |
| `TRUSTED_PROXIES` | 受信任反向代理层数；`0` 表示没有 |
| `SESSION_COOKIE_SECURE` | 仅通过 HTTPS 发送会话 cookie |
| `SESSION_TIMEOUT` | 空闲 SSH 会话超时（秒）；默认 `1800` |

生产配置文件要求显式的 HTTPS 源、安全 cookie 与显式的受信任代理。通配符源不是生产配置。请参阅 [反向代理与子目录部署](Reverse-Proxy-and-Subfolder-Deployment)。

## 注册与本地认证

| 变量 | 用途 | 默认值 |
|---|---|---|
| `REGISTRATION_ENABLED` | 允许公开创建额外的本地账号 | `False`；生产环境拒绝 `True` |
| `BOOTSTRAP_REGISTRATION_ENABLED` | 允许在全新的家庭实验室数据库中恰好创建一个首位管理员 | 家庭实验室默认值；生产配置文件禁用并拒绝 |
| `ADMIN_PANEL_ENABLED` | 可以禁用管理员面板 | 启用 |
| `ADMIN_USERS` | 逗号分隔的现有用户名，在启动时提升为管理员 | 空 |

对于受控部署，优先使用 `flask create-admin`。公开注册独立于 LDAP 与 OIDC 登录。

## SSH 网络策略

| 变量 | 用途 |
|---|---|
| `BLOCK_INTERNAL_SSH` | 按照网络策略阻止到回环、私有、链路本地及其他受保护目标的 SSH 连接 |
| `PROXY_JUMP_REMOTE_DNS_ALLOWLIST` | 受信任堡垒机可以远程解析的精确主机名 |

`BLOCK_INTERNAL_SSH=true` 适合面向 Internet 的网关，但可能与家庭实验室使用相冲突。在启用之前，请解析并校验精确的目标策略。主机密钥校验仍是独立的控制措施。

## 运行时容量

| 变量 | 默认值 | 契约 |
|---|---|---|
| `GUNICORN_THREADS` | `64` | 支持范围 `8` 到 `256` |
| `MAX_SOCKET_CONNECTIONS` | `48` | 全局已准入的 Socket.IO 连接数 |
| `MAX_SOCKET_CONNECTIONS_PER_USER` | `8` | 每用户 Socket.IO 连接数 |
| `BACKGROUND_WORKERS` | 计算得出的基线 | 有界执行器；最小值为清理作业加上全局 SSH 会话与后台作业配额 |
| `RUNTIME_SHUTDOWN_GRACE_SECONDS` | `5` | 优雅关闭窗口；支持范围 `1` 到 `30` 秒 |

生产环境要求恰好一个使用 `gthread` 的 Gunicorn worker。活动 SSH 通道以及部分协调状态是进程本地的。增加 worker 数量无法安全地扩展 WebSSH。

至少保留四个空闲 HTTP 线程：

```text
GUNICORN_THREADS - MAX_SOCKET_CONNECTIONS >= 4
```

LDAP 会在同一运行时生命周期中增加一个有界清理任务；请将后台容量作为一个合并预算来规划。

## 用户配额

| 变量 | 默认值 |
|---|---:|
| `QUOTA_SSH_SESSION_GLOBAL` | `10` |
| `QUOTA_SSH_SESSION_PER_USER` | `5` |
| `QUOTA_QUICK_CONNECTION_GLOBAL` | `12` |
| `QUOTA_QUICK_CONNECTION_PER_USER` | `3` |
| `QUOTA_TRANSFER_GLOBAL` | `8` |
| `QUOTA_TRANSFER_PER_USER` | `2` |
| `QUOTA_TEMP_BYTES_GLOBAL` | `1073741824` |
| `QUOTA_TEMP_BYTES_PER_USER` | `536870912` |
| `QUOTA_BACKGROUND_JOB_GLOBAL` | `4` |
| `QUOTA_BACKGROUND_JOB_PER_USER` | `1` |

连接、传输、后台工作与线程限制构成同一个容量模型。不要在未检查 HTTP 预留、内存、远程服务器容量与关闭行为的情况下孤立地提高某一项限制。

## 速率限制

| 变量 | 默认值 |
|---|---:|
| `RATELIMIT_ENABLED` | `true` |
| `RATELIMIT_STORAGE_URL` | `memory://` |
| `RATELIMIT_DEFAULT` | `200 per hour` |
| `RATELIMIT_LOGIN_LIMIT` | `5 per minute` |
| `RATELIMIT_REAUTH` | `5 per minute` |
| `SSH_CONNECT_RATELIMIT` | `10 per minute` |
| `SSH_KEY_WRITE_RATELIMIT` | `30 per minute` |
| `SSH_KEY_LIST_RATELIMIT` | `30 per minute` |
| `CONNECTION_MUTATION_RATELIMIT` | `60 per minute` |

密钥列表以及重命名、替换或删除密钥后的刷新，会在各浏览器连接之间共享每用户的
`SSH_KEY_LIST_RATELIMIT`。准入检查发生在变更之前；当额度耗尽时，变更会被拒绝而不会改动
密钥。已接受的变更会保留其确认与更新后的密钥列表。可用性
仍会对照当前密钥文件进行检查，而不缓存解密后的密钥。

## SSH 密钥与实时输出限制

| 变量 | 默认值 |
|---|---:|
| `SSH_KEY_MAX_RECORDS` | `100` |
| `SSH_KEY_STORE_MAX_BYTES` | `8388608` (8 MiB encrypted) |
| `SSH_OUTPUT_MAX_UNACKED_BYTES_PER_SOCKET` | `524288` (512 KiB) |
| `SSH_OUTPUT_MAX_UNACKED_EVENTS_PER_SOCKET` | `128` |
| `SSH_OUTPUT_MAX_UNACKED_EVENTS_PER_USER` | `1024` |
| `SSH_OUTPUT_MAX_UNACKED_EVENTS_GLOBAL` | `8192` |
| `SSH_OUTPUT_MAX_UNACKED_BYTES_PER_USER` | `4194304` (4 MiB) |
| `SSH_OUTPUT_MAX_UNACKED_BYTES_GLOBAL` | `33554432` (32 MiB) |
| `SSH_OUTPUT_ACK_TIMEOUT_SECONDS` | `10` seconds |

密钥限制只拒绝存储增长。字节
限制以上的既有存储仍可读取，并可以用更小的
密钥进行重命名、删除或替换。实时终端输出由每个浏览器确认。如果某个浏览器
在配置的超时时间内一直阻塞确认预算，WebSSH 会
应用 SSH 背压，然后只断开该浏览器；底层
SSH 或持久 tmux 会话仍可用于重连。

同一浏览器连接中的所有终端共享最多八个
未确认输出事件的投递窗口，并进一步受上述预算约束。这会对 SSH 读取者进行节流，并使输出 ACK 的突发保持在 Engine.IO 的轮询
数据包限制以下，同时为控制流量留出空间。等待投递配额
本身并不意味着某个 ACK 已逾期。配置的超时仍适用于
每个未完成的输出事件。打开更多终端标签页不会创建
额外的 Socket.IO 连接。

`memory://` 是进程本地的，计数器会在进程重启时重置。请使用 `redis://` URL 获得持久、共享的计数器。Redis 不会改变单 worker 架构。

## 文件传输与编辑器限制

| 变量 | 默认值 |
|---|---:|
| `MAX_DOWNLOAD_SIZE` | `104857600` (100 MiB) |
| `MAX_ZIP_DOWNLOAD_SIZE` | `524288000` (500 MiB) |
| `MAX_TRANSFER_MEMBERS` | `10000` |
| `MAX_PREVIEW_SIZE` | `512000` bytes |
| `MAX_PREVIEW_TAIL_LINES` | `10000` |
| `MAX_SUPPORTED_FILE_SIZE` | `1073741824` (1 GiB) |
| `SFTP_OPERATION_TIMEOUT` | `30` seconds |
| `SFTP_MAX_PACKET_BYTES` | `1048576` (1 MiB) |
| `SFTP_MAX_HANDLE_BYTES` | `16384` (16 KiB) |
| `MAX_EDITOR_FILE_SIZE` | `5242880` (5 MiB) |
| `EDITOR_SAVE_BYTES_PER_MINUTE` | `20971520` (20 MiB per user) |
| `TRANSFER_TEMP_DIR` | `DATA_DIR/tmp` |
| `FILE_CONTROL_MAX_PATH_BYTES` | `4096` bytes |
| `FILE_CONTROL_BYTES_PER_MINUTE` | `2097152` (2 MiB per user) |
| `REMOTE_FILENAME_MAX_BYTES` | `4096` bytes |
| `REMOTE_LISTING_MAX_METADATA_BYTES` | `4194304` (4 MiB) |
| `REMOTE_LISTING_PAGE_SIZE` | `500` entries |
| `REMOTE_LISTING_SNAPSHOT_TTL_SECONDS` | `60` seconds |
| `REMOTE_LISTING_SNAPSHOT_MAX_STATES` | `8` snapshots per process |
| `REMOTE_LISTING_SNAPSHOT_MAX_PER_USER` | `4` snapshots per user |
| `CONNECTION_STORE_RECOVERY_MAX_BYTES` | `16777216` (16 MiB) |
| `CONNECTION_STORE_RECOVERY_MAX_RECORDS` | `10000` |

批量上传与下载通过 HTTP 流式传输；Socket.IO 承载控制事件与有界的编辑器内容，而不是整个文件。提高应用限制时，请将代理的请求体与超时限制与 WebSSH 对齐。

SFTP 目录响应是分页的。声明的协议数据包与不透明句柄
大小、原始条目数（包括 `.` 与 `..`）、文件名、长名称、聚合
元数据以及文件控制预算都会在数据被保留或回显之前强制执行。

## 已保存连接限制

| 变量 | 默认值 |
|---|---:|
| `PROFILE_MAX_RECORDS` | `500` |
| `JUMP_HOST_MAX_RECORDS` | `100` |
| `CONNECTION_STORE_MAX_BYTES` | `2097152` (2 MiB per store) |
| `CONNECTION_CONFIG_MAX_BYTES` | `4194304` (4 MiB combined) |

超出正常限制的旧版存储会从浏览器 UI 中被隔离。在
停止所有 WebSSH 进程之后，`flask --app start connection-store list` 与
`connection-store delete` 提供一条非机密的、有界的恢复路径，上限为
上述独立的恢复上限。增长会被拒绝，配置文件
与跳板主机密钥引用仍会进行所有权检查。

## 功能开关与 tmux

| 变量 | 默认值或用途 |
|---|---|
| `TMUX_ENABLED` | `false`；启用持久远程 tmux 会话 |
| `TMUX_DEFAULT` | `false`；在连接对话框中预选 tmux |
| `TMUX_SESSION_PREFIX` | `webssh` |
| `HOST_KEY_MANAGEMENT_ENABLED` | `true` |
| `RECOVERY_CODES_ENABLED` | `true` |
| `AUDIT_EXPORT_ENABLED` | `true` |
| `MAX_RECOVERY_JSON_SIZE` | `4096` bytes |

## 通行密钥设置

| 变量 | 用途 |
|---|---|
| `WEBAUTHN_ENABLED` | 启用通行密钥注册与登录 |
| `WEBAUTHN_RP_ID` | 仅公共域名；默认为 `localhost` |
| `WEBAUTHN_RP_NAME` | 显示名称；默认为 `WebSSH` |
| `WEBAUTHN_ORIGIN` | 精确的浏览器源，包含 scheme 与可选端口 |
| `MAX_WEBAUTHN_JSON_SIZE` | 请求上限；默认为 64 KiB |

## 审计与备份

| 变量 | 默认值 |
|---|---:|
| `AUDIT_LOG_MAX_BYTES` | `10485760` |
| `AUDIT_LOG_BACKUP_COUNT` | `5` |
| `BACKUP_UPLOAD_MAX_SIZE` | `1073741824` |
| `BACKUP_OPERATION_TIMEOUT` | `1800` |
| `BACKUP_DOWNLOAD_TTL` | `600` |
| `BACKUP_MAX_MEMBERS` | `10000` |
| `BACKUP_MAX_FILE_SIZE` | `1073741824` |
| `BACKUP_MAX_TOTAL_SIZE` | `10737418240` |
| `BACKUP_MAX_COMPRESSION_RATIO` | `200` |
| `BACKUP_MAX_MANIFEST_SIZE` | `10485760` |
| `BACKUP_TEMP_DIR` | `webssh-backup-operations` 下的系统临时目录 |
| `BACKUP_RECOVERY_DURABLE` | `false`；在线恢复时必须为 `true` 且使用持久的外部存储 |

审计导出最多扫描 50,000 条记录，并在响应元数据中声明是否发生截断。备份安全限制还会限制归档成员数量、单个大小、总大小、压缩比与清单大小。

`BACKUP_TEMP_DIR` 在创建备份时可以保持临时性。在线恢复
还要求它是绝对路径、私有、位于 `DATA_DIR` 之外，并且在
进程/容器替换后仍然持久。

## OIDC、GitHub、LDAP、通行密钥与 Tailscale

身份提供方变量归组在各自的专门页面中：

- [LDAP 与 Active Directory](LDAP-and-Active-Directory)
- [OpenID Connect](OpenID-Connect)
- [GitHub 认证](GitHub-Authentication)
- [通行密钥与恢复码](Passkeys-and-Recovery-Codes)
- [Tailscale SSH](Tailscale-SSH)

所有可选身份提供方在显式配置之前都处于禁用状态。GitHub 是
环境变量模型的例外：它的完整配置与加密客户端机密在 Admin Panel 中管理，因此不需要任何 Compose 或 `.env` 条目。不要将绑定密码、OIDC 客户端机密或其他可复用凭据直接放入提交到源代码管理的 Compose YAML 中。

## 校验有效配置

在部署之前渲染合并后的 Compose 配置：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.production.yml \
  config
```

当启用 LDAP 时添加 `-f docker-compose.ldap.yml`。在启动服务之前，确认有效的绑定地址、源、cookie 模式、注册状态、代理信任、卷与机密文件。
