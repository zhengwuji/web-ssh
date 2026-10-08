# Tailscale SSH 部署与安全

WebSSH 可以使用运行 WebSSH 的机器或容器的 Tailscale 身份向目标进行认证。浏览器
用户无需提供密码或私有 SSH 密钥。目标上必须通过 `tailscale set --ssh` 启用
Tailscale SSH，并且 tailnet 策略必须授权该 WebSSH 节点。

## 共享身份安全模型

Tailscale 看到的是 WebSSH 节点，而不是点击连接的那个具体的 WebSSH 账号。因此，
所有被授权使用此功能的 WebSSH 用户共享同一个 tailnet 身份，以及分配给该节点或
标签的全部权限。

请仅在受信任的家庭实验室（homelab）或类似受控环境中使用此模式：

1. 为 WebSSH 分配一个专用标签，例如 `tag:webssh`。
2. 将该标签限制为仅能访问所需目标标签或主机上的 TCP 22 端口。
3. 将 Tailscale SSH 规则限制为所需的远程操作系统用户名。
4. 保持 WebSSH 注册处于禁用或严格受控的状态。
5. 将 WebSSH 强制的目标允许列表以及可选的远程用户名允许列表配置为第二道边界。
   tailnet ACL 与 SSH 策略仍然是权威依据。

每一次被授权或被拒绝的 Tailscale SSH 尝试都会写入安全审计日志，其中包含 WebSSH
用户名、目标、远程用户名、客户端 IP 以及 `shared-node` 身份标记。

## WebSSH 配置

Tailscale SSH 默认关闭。请显式启用它：

```env
TAILSCALE_SSH_ENABLED=true
TAILSCALE_SSH_ALLOWED_WEBSSH_USERS=operator
TAILSCALE_SSH_ALLOWED_TARGETS=tiny-server,100.64.0.10:2222
TAILSCALE_SSH_ALLOWED_REMOTE_USERS=root,ubuntu
TAILSCALE_SSH_INTERFACE=tailscale0
```

当该功能启用时，管理员始终被允许访问。`TAILSCALE_SSH_ALLOWED_WEBSSH_USERS`
列表用于向额外的 WebSSH 用户名授予访问权限。只要该功能被启用，目标允许列表就是
强制的。单独的主机名、IPv4 地址或 IPv6 地址均表示端口 22。如需使用其他端口，请
使用 `hostname:port`、`IPv4:port` 或 `[IPv6]:port`。目标匹配是精确且大小写不敏感
的，而远程操作系统用户名则是精确且大小写敏感的。在生产部署中，如果已启用的功能
其目标列表为空或格式错误，或者接口为空，则会拒绝启动。家庭实验室配置文件会发出
安全警告，忽略个别格式错误的条目以便有效的同类条目仍然可用，并且在没有任何有效
目标或接口时关闭所有连接。当该功能被禁用时，这些值保持休眠状态。在 DNS 解析之后，
WebSSH 只接受内核路由使用 `TAILSCALE_SSH_INTERFACE`（默认 `tailscale0`）的地址，
锁定该地址，并将连接的套接字绑定到同一接口。路由变化无法悄悄地把连接转移到其他
接口。

Tailscale 认证不能与 ProxyJump 组合使用。路由与接口证明仅适用于来自 WebSSH 主机
的直接连接。

## tailnet 策略示例

请根据实际部署调整标签、目标与用户。该示例有意只向 WebSSH 标签授予对带标签服务器
的 SSH 访问权限：

```json
{
  "tagOwners": {
    "tag:webssh": ["autogroup:admin"],
    "tag:servers": ["autogroup:admin"]
  },
  "grants": [
    {
      "src": ["tag:webssh"],
      "dst": ["tag:servers"],
      "ip": ["tcp:22"]
    }
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["tag:webssh"],
      "dst": ["tag:servers"],
      "users": ["root"]
    }
  ]
}
```

## 带持久化状态的 Docker 边车（sidecar）

该边车是一个独立的 Tailscale 容器，它与 WebSSH 共享网络命名空间。其
`/var/lib/tailscale` 卷可在容器更新和重启之间保留节点注册信息。请将 WebSSH 端口
发布在 Tailscale 服务上，因为 `network_mode: service:tailscale` 使两个容器共用
同一个网络命名空间。

### 安全的首次设置

不要在全新的、可被公网访问的 WebSSH 数据库上启用 Tailscale SSH。在启用共享的
Tailscale 身份之前，请先在 Docker 主机上显式创建管理员。

请按以下顺序引导部署：

1. 在受信任的网络上，按原样保存并启动下面的边车配置。它刻意以
   `TAILSCALE_SSH_ENABLED=false` 启动。
2. 显式创建第一个管理员：
   ```bash
   docker compose exec webssh /app/entrypoint.sh flask --app start:app create-admin --username admin
   ```
3. 除非确实需要，否则请保持生产环境的自助注册处于禁用状态。由于管理员已先被
   创建，之后通过公开注册创建的每个账号都是非管理员的。在除此之外为空的安装
   环境中，第一个注册的账号将会成为管理员。
4. 配置范围较窄的目标与远程用户允许列表，然后将 `TAILSCALE_SSH_ENABLED` 改为
   `true`。
5. 使用 `docker compose up -d` 应用更新后的配置。

生产环境的自助注册始终处于禁用状态。在家庭实验室配置文件中，保存在 Admin Panel
中的注册设置优先于环境变量默认值。

### 家庭实验室 Compose 示例

本示例遵循仓库现有的家庭实验室默认值：它允许任意浏览器源（`CORS_ORIGINS=*`）
并允许非 TLS 的 HTTP Cookie。请仅在受信任的网络上使用它。生产环境的 HTTPS 替换
配置紧接在该示例之后给出。

```yaml
services:
  tailscale:
    image: tailscale/tailscale:stable
    hostname: webssh
    restart: unless-stopped
    ports:
      - "5000:5000"
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}
      - TS_AUTH_ONCE=true
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=false
      - TS_EXTRA_ARGS=--advertise-tags=tag:webssh
    volumes:
      - tailscale_state:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - NET_RAW

  webssh:
    image: ghcr.io/zhengwuji/web-ssh:latest
    restart: unless-stopped
    network_mode: service:tailscale
    depends_on:
      - tailscale
    environment:
      - HOST=0.0.0.0
      - PORT=5000
      # Trusted homelab defaults, matching the repository Compose file.
      - CORS_ORIGINS=*
      - ALLOW_CORS_WILDCARD=true
      - SESSION_COOKIE_SECURE=false
      # Keep online-restore rollback state durable and separate from DATA_DIR.
      - BACKUP_TEMP_DIR=/app/recovery
      - BACKUP_RECOVERY_DURABLE=true
      # Keep disabled until an administrator has been created with the CLI.
      - TAILSCALE_SSH_ENABLED=false
      # Leave empty to allow only existing WebSSH administrators.
      - TAILSCALE_SSH_ALLOWED_WEBSSH_USERS=
      - TAILSCALE_SSH_ALLOWED_TARGETS=tiny-server
      - TAILSCALE_SSH_ALLOWED_REMOTE_USERS=root
      - TAILSCALE_SSH_INTERFACE=tailscale0
    volumes:
      - webssh_data:/app/data
      - webssh_recovery:/app/recovery

volumes:
  tailscale_state:
  webssh_data:
  webssh_recovery:
    driver: local
```

完成管理员引导与允许列表配置之后，将取值改为 `TAILSCALE_SSH_ENABLED=true` 即可
启用该功能。

对于 HTTPS 部署，请将这三项家庭实验室浏览器设置替换为公开源与安全 Cookie：

```yaml
      - CORS_ORIGINS=https://ssh.example.com
      - SESSION_COOKIE_SECURE=true
```

使用具体源时，请移除 `ALLOW_CORS_WILDCARD=true`。如果 Docker 主机上的反向代理
负责终止 TLS，还请将发布的端口绑定到回环地址，这样客户端就无法绕过 HTTPS：

```yaml
    ports:
      - "127.0.0.1:5000:5000"
```

对于容器化的反向代理，则应改为移除 `ports` 块，将 `tailscale` 服务与代理接入
同一个内部 Docker 网络，并代理到 `tailscale:5000`。在这两种情况下，都请按照主
README 中的说明配置 `TRUSTED_PROXIES`。不要同时列出通配符源和具体源。

请在部署时通过环境文件或密钥管理器提供 `TS_AUTHKEY`；不要将其提交到 Compose
中。建议使用带标签的、可重用的或由 OAuth 签发的凭据，并赋予其所需的最小标签
权限。在持久化节点状态存在之后，`TS_AUTH_ONCE=true` 可避免每次重启时进行不必要
的重新认证。
