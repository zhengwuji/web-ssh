# 安全模型与加固

WebSSH 是一个特权网关：它接收 SSH 凭据、打开远程会话、处理终端数据并传输文件。HTTPS 在传输过程中保护浏览器流量，但 WebSSH 本身必然能看到执行这些操作所需的材料。它在浏览器与 SSH 服务器之间并非端到端加密。

## 信任边界

将以下所有内容作为敏感系统加以保护：

- WebSSH 主机与容器运行时；
- `DATA_DIR`、其备份以及持久化的 `SECRET_KEY`；
- 反向代理与 TLS 私钥；
- LDAP bind、OIDC client、Redis 及其他基础设施凭据；
- 管理员浏览器与账户；
- 从 WebSSH 到 SSH、LDAP、OIDC、Redis 与 DNS 端点的网络。

WebSSH 进程或其主机被攻陷，可能泄露活动的终端/文件数据以及提供给它的凭据。

## 内置控制

WebSSH 包含：

- 针对 HTTP 表单与已认证 Socket.IO 事件契约的 CSRF 保护；
- `HttpOnly`、`SameSite=Lax` 会话 cookie，以及生产环境中的 `Secure` cookie；
- Content Security Policy、生产环境中的 HSTS、拒绝框架嵌入、防止 MIME 嗅探、referrer policy 与 permissions policy；
- 针对会话、传输、文件、profile、密钥与主机密钥数据的每用户所有权检查；
- 有界的连接、传输、临时存储与后台工作配额；
- 登录、重新认证、连接、备份以及默认速率限制；
- 显式 SSH 目标策略与每用户主机密钥校验；
- 按用户派生的加密私钥存储；
- 安全审计日志与管理员重新认证；
- 有界的维护、关闭、备份与恢复工作流。

这些是纵深防御层，而不是将默认的家用实验环境配置直接暴露到 Internet 的理由。

## 生产基线

面向 Internet 暴露时：

1. 在基础 Compose 文件之外同时使用 `docker-compose.production.yml`。
2. 在维护良好的反向代理处终止现代 HTTPS。
3. 将 WebSSH 绑定到回环地址或私有网络，而非公网接口。
4. 设置确切的 HTTPS `CORS_ORIGINS`；绝不使用通配符。
5. 将 `TRUSTED_PROXIES` 设置为可信代理层的确切数量。
6. 保持 `SESSION_COOKIE_SECURE=true`。
7. 禁用公开注册与浏览器管理员引导（bootstrap）。
8. 确认生产环境的强制内网目标阻断与预期的 SSH 目标网络一致。
9. 当计数器必须在重启后继续存在时，使用 Redis 支持的速率限制。
10. 保护并测试备份、恢复码以及本地管理员路径。

## SSH 凭据与私钥

存储的 SSH 私钥使用 Fernet 加密。每用户加密材料由 `SECRET_KEY:user_id` 通过 PBKDF2-HMAC-SHA256 以 600,000 次迭代派生而来。这降低了仅复制数据目录所带来的暴露风险，但如果一个正在运行的、被完全攻陷且同样持有该密钥的应用，它并不能保护密钥。

优先使用范围受限的远程账户、最小权限、尽可能短期的凭据以及 SSH 服务器端限制。绝不将密码、令牌或私钥内容写入日志。

## 主机密钥校验

WebSSH 使用每用户的 known-hosts 存储以及首次使用即信任（trust-on-first-use）工作流。新受信任的密钥会被固定（pinned）。密钥发生变更时会被拒绝，直到该差异被独立调查且旧的信任记录被显式撤销。

不要培训用户将接受变更的密钥视为例行操作。请通过单独的渠道验证远程主机的指纹。

## 身份提供方加固

- LDAP：使用 `ldaps://` 或 StartTLS，校验服务器证书，使用只读的最小权限服务账户，并限制用户/组过滤器。
- OIDC：使用受信任的签发方、确切的 redirect URI、密钥文件，以及在需要时显式的域或 subject 策略。
- Passkey：将恢复码离线保存，并及时撤销丢失的验证器。
- Tailscale SSH：使用严格的 WebSSH 用户、目标与远程用户允许列表；节点身份是共享的。

LDAP/AD 认证不会把目录密码复制到 WebSSH 中。在安全默认的 `LDAP_AUTO_PROVISION=false` 下，认证要求存在一个本地账户且已显式关联目录。显式设置 `LDAP_AUTO_PROVISION=true` 时，只能在成功完成已验证的 LDAP bind 之后创建一个非管理员账户，且绝不会占用已存在的本地用户名。

## 静态数据与备份

SQLite 数据库、用户 JSON 文件、known-host 数据、笔记、profile、命令以及加密密钥都存放在 `DATA_DIR` 中。原生备份还可能包含持久化的 `SECRET_KEY`，使其足以解密已存储的密钥材料。请单独加密备份并限制访问与保留期限。

## 漏洞上报

不要在公开 issue 中披露疑似漏洞。请遵循仓库 `SECURITY.md` 中的私密上报渠道，例如 GitHub 私密安全公告或所列出的安全联系人。

## 加固验证

在暴露之前，请验证生效的配置，而不仅仅是预期的 `.env`：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.production.yml \
  config
```

然后确认 HTTPS 重定向、安全 cookie、来源拒绝、代理 IP 处理、注册状态、SSH 目标策略、主机密钥行为、速率限制、`/ready`、备份下载过期以及恢复维护行为。
