# Tailscale SSH

Tailscale SSH 是可选的，并默认禁用。每个已授权的 WebSSH 用户
都使用 WebSSH 节点的同一个 Tailscale 身份。这比普通的每用户 SSH 凭据
更强的信任边界。

## 仅当所有控制措施齐备时才启用

仅在具备以下条件时使用 Tailscale SSH：

- 为 WebSSH 节点设置专用 Tailscale 标签；
- 狭义的 tailnet ACL 与 SSH 规则；
- 受信任的 WebSSH 管理员，或明确的非管理员允许列表；
- 强制的精确目标与端口允许列表；
- 精确的远程操作系统用户名允许列表；
- 经过测试的本地 WebSSH 管理员与恢复路径；
- 持久的 Tailscale 节点状态。

隐藏 UI 并不是授权。后端会强制执行 WebSSH 用户、目标、
远程用户与 tailnet 策略。

## WebSSH 设置

```bash
TAILSCALE_SSH_ENABLED=true
TAILSCALE_SSH_ALLOWED_WEBSSH_USERS=operator
TAILSCALE_SSH_ALLOWED_TARGETS=tiny-server,100.64.0.10:2222
TAILSCALE_SSH_ALLOWED_REMOTE_USERS=root,ubuntu
TAILSCALE_SSH_INTERFACE=tailscale0
```

当该功能启用时，管理员按角色获得授权。用户
允许列表用于额外添加特别受信任的非管理员 WebSSH 账号。该功能启用时
目标列表是必需的。裸主机名、IPv4 地址或 IPv6
地址表示端口 22；请使用 `hostname:port`、`IPv4:port` 或 `[IPv6]:port` 指定
其他端口。生产环境在启用状态下目标列表为空或格式错误，
或接口为空时拒绝启动。家庭实验室会发出安全警告，忽略
个别的格式错误条目，从而使有效的同级条目仍然可用，并在没有有效目标或接口保留时让每个
连接都以关闭失败。在该功能禁用时，休眠值是被容忍的。WebSSH 只解析一次，仅接受内核路由使用 `TAILSCALE_SSH_INTERFACE`（默认
`tailscale0`）的地址，固定该地址，并将连接套接字绑定到同一
接口。路由变化无法把连接静默移动到另一个
接口。空的远程用户列表仍把该维度交给
tailnet SSH 策略。

Tailscale 认证无法与 ProxyJump 组合使用。路由与
接口证明仅适用于来自 WebSSH 主机的直接连接。

## Tailnet 策略概念

使用专用的源标签（例如 `tag:webssh`）与目标标签（例如
`tag:servers`）。仅授予 TCP/22，并且仅授予 WebSSH 应当
访问的远程用户。

示例策略：

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

请根据当前的 Tailscale 策略 schema 与组织控制措施调整此内容。
该示例有意保持狭窄。

## 持久 sidecar 模型

Tailscale sidecar 可以与 WebSSH 共享其网络命名空间。请持久化
`/var/lib/tailscale`，使节点身份在更新后仍然保留。

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
      - CORS_ORIGINS=*
      - ALLOW_CORS_WILDCARD=true
      - SESSION_COOKIE_SECURE=false
      - BACKUP_TEMP_DIR=/app/recovery
      - BACKUP_RECOVERY_DURABLE=true
      - TAILSCALE_SSH_ENABLED=false
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

该示例以 Tailscale SSH 禁用状态启动。

## 安全的引导顺序

1. 在受信任的网络上以
   `TAILSCALE_SSH_ENABLED=false` 启动 sidecar 部署。
2. 使用 CLI 显式创建第一个 WebSSH 管理员。
3. 除非确有必要，否则保持普通注册关闭。
4. 配置 tailnet 策略与精确的 WebSSH 允许列表。
5. 启用 Tailscale SSH。
6. 重建服务并测试一组狭义的目标/用户组合。

## 生产环境浏览器访问

将家庭实验室的 CORS 与 cookie 设置替换为：

```yaml
environment:
  - CORS_ORIGINS=https://ssh.example.com
  - SESSION_COOKIE_SECURE=true
```

移除通配符 CORS。如果主机上的反向代理终止 TLS，请将
发布的端口绑定到回环地址：

```yaml
ports:
  - "127.0.0.1:5000:5000"
```

对于容器化的代理，请移除公共端口并使用私有的共享
网络。

## Auth key 处理

不要将 `TS_AUTHKEY` 提交到版本控制。请通过环境文件或机密
管理器提供它。优先使用带标签的可复用凭据或 OAuth 签发的凭据，且只具备拥有 `tag:webssh` 所需的
权限。`TS_AUTH_ONCE=true` 可避免在持久节点状态存在之后进行不必要的
重新认证。

## 用户体验

已授权的配置文件可以选择 Tailscale SSH，而非密码或已存储
密钥。当不需要交互式凭据时，已保存的配置文件可以直接启动。在授权仍然有效时，
手动重连也可以直接进行。

## 故障排查

### Tailscale 选项缺失

检查功能标志，以及该 WebSSH 账号是管理员还是被
列在 `TAILSCALE_SSH_ALLOWED_WEBSSH_USERS` 中。

### 目标被拒绝

检查精确的 WebSSH 目标允许列表、DNS/Tailscale 名称、tailnet 授权、SSH
规则以及远程用户允许列表。

### 重启后节点身份发生变化

确认 `/var/lib/tailscale` 是持久的，并且 `TS_STATE_DIR` 指向它。

### 所有 WebSSH 用户都显示为同一个源

这就是设计边界：Tailscale 看到的是共享的 WebSSH 节点身份。
请使用 WebSSH 审计日志与严格的用户/目标/远程用户控制，或者不要
为那些应当拥有独立 tailnet 身份的用户启用该功能。

## 相关页面

- [安全模型与加固](Security-Model-and-Hardening)
- [配置文件、跳板主机与命令](Profiles-Jump-Hosts-and-Commands)
- [生产环境部署](Production-Deployment)
