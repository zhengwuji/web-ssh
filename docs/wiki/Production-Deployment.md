# 生产部署

对于面向互联网或以其他方式不受信任的多用户
部署，请使用此配置文件。WebSSH 把生产设置视为经过校验的安全契约：
不安全的组合会阻止启动，而不只是记录警告。

## 架构

推荐的部署具有以下边界：

```text
Browser --HTTPS--> trusted reverse proxy --private HTTP--> WebSSH
                                                    |
                                                    +--SSH/SFTP--> targets
```

只有受信任的反向代理才应访问 WebSSH 的后端端口。请把
Docker 主机、数据卷、日志和备份作为特权基础设施加以保护。

## 要求

- Docker Compose 2.24.4 minimum（Docker Compose 2.24.4 or newer）；生产覆盖文件使用 `!override` 来
  替换家庭实验室的端口绑定。
- 一个公共 DNS 名称和受信任的 TLS 证书。
- 一个支持 WebSocket 升级的反向代理。
- 一个持久化的 `/app/data` 数据卷。
- 在更新之前记录一份备份和回滚镜像。

## 使用生产覆盖文件部署

```bash
curl -O https://raw.githubusercontent.com/zhengwuji/web-ssh/main/docker-compose.yml
curl -O https://raw.githubusercontent.com/zhengwuji/web-ssh/main/docker-compose.production.yml

export WEBSSH_ORIGIN=https://ssh.example.com

docker compose \
  -f docker-compose.yml \
  -f docker-compose.production.yml \
  config

docker compose \
  -f docker-compose.yml \
  -f docker-compose.production.yml \
  up -d
```

该覆盖文件默认把 WebSSH 绑定到 `127.0.0.1:5000`。同一主机上的
反向代理可以使用该地址。对于容器化的代理，请移除对外端口
发布，并把两个服务连接到私有 Docker 网络。

## 可选的容器限制

生产覆盖文件保留现有的资源与文件系统设置。
对于当前镜像，追加 `-f docker-compose.hardened.yml` 以显式
选择只读根文件系统、被丢弃的能力、私有运行时 tmpfs 以及资源
限制。请从与其他 Compose 文件相同的发布版本获取该文件。
请先检查自定义写入路径、数字 UID/GID 和容量。配置与备份行为参见
[生产容器边界](https://github.com/zhengwuji/web-ssh/blob/main/docs/production-container.md)。
该额外覆盖文件不会取代
生产 HTTPS 和身份验证设置。

## 创建管理员

在生产环境中，浏览器引导和公开注册都被禁用。请从受信任的主机
创建或提升一名管理员：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.production.yml \
  exec webssh \
  /app/entrypoint.sh flask --app start:app create-admin --username admin
```

对于非交互式自动化，请把 `--password-file` 与一个挂载到容器内的私有普通
文件（非符号链接）配合使用。该命令会移除一个结尾的
换行符，并且绝不打印密码。

## 强制实施的生产设置

随附的覆盖文件配置了：

```yaml
DEPLOYMENT_PROFILE: production
CORS_ORIGINS: ${WEBSSH_ORIGIN}
ALLOW_CORS_WILDCARD: "false"
SESSION_COOKIE_SECURE: "true"
REGISTRATION_ENABLED: "False"
BOOTSTRAP_REGISTRATION_ENABLED: "false"
BLOCK_INTERNAL_SSH: "true"
TRUSTED_PROXIES: ${TRUSTED_PROXIES:-1}
```

生产启动会拒绝：

- 调试模式；
- 通配或缺失的浏览器源；
- 不安全的浏览器 Cookie；
- 浏览器引导或开放注册；
- 被禁用的内部目标阻止；
- 未指定的代理信任边界。

仅当 WebSSH 不接受任何代理头时才显式设置 `TRUSTED_PROXIES=0`。
当该值非零时，能够绕过代理的客户端可能会伪造
转发信息，因此请限制后端网络路径。

## 反向代理检查清单

该代理必须：

- 终止 HTTPS；
- 保留公共 `Host` 头；
- 转发 `X-Forwarded-Proto`；
- 经过预期数量的受信任层级转发客户端地址；
- 支持 WebSocket 的 `Upgrade` 和 `Connection` 头；
- 避免把明文后端暴露给客户端。

nginx、Traefik 和 Caddy 的示例参见
[反向代理与子目录部署](Reverse-Proxy-and-Subfolder-Deployment)。

## 身份选项

本地账户仍是恢复的基础。

- 至少保留一个本地管理员，并配有经过测试的恢复材料。
- OIDC 要求显式且稳定的 `(issuer, subject)` 关联；它绝不只信任
  电子邮件。
- LDAP/Active Directory 要求显式且稳定的身份关联；已关联的用户
  是非管理员，且不能回退到本地密码或替代因素。
- Passkey 要求确切的公共 RP ID 和 HTTPS 源。

只有在基础的本机管理员部署可用之后，才启用可选身份。

## 目标网络策略

生产环境启用 `BLOCK_INTERNAL_SSH=true`，在 DNS 解析之后阻止回环、
链路本地、私有和保留目标。这降低了
不受信任用户把 WebSSH 用作 SSRF 或内网跳板的风险。

如果真实用例需要私有目标，请不要在
广泛可访问的服务上简单地放宽该标志。请限制用户和网络访问、隔离该
实例，并记录该例外。

## 容量契约

请只保留一个 Gunicorn worker。默认值为：

- `GUNICORN_THREADS=64`
- `MAX_SOCKET_CONNECTIONS=48`
- `MAX_SOCKET_CONNECTIONS_PER_USER=8`
- 至少预留四个线程用于 HTTP 路由和流式传输。

有界的运行时执行器默认等于由清理循环、允许的 SSH 读取器和后台任务
推导出的必需最小值。启用 LDAP 会为该最小值增加一个
常驻的重新校验任务。

## 运维检查

部署之后：

```bash
curl -fsS https://ssh.example.com/health
curl -fsS https://ssh.example.com/ready
docker compose ps
docker compose logs --tail=200 webssh
```

验证：

1. HTTPS 重定向和证书校验。
2. 浏览器中的安全 Cookie。
3. 注册页面不可用。
4. 管理员登录与恢复。
5. 一次直接的 SSH 连接和主机密钥信任。
6. SFTP 列目录和一次小规模传输。
7. 容器的优雅重启和就绪状态恢复。

## 每次升级之前

- 创建并下载一份经过验证的备份。
- 记录已部署的不可变镜像摘要。
- 复核发布说明和持久化数据的兼容性。
- 保留上一个镜像可用。
- 确认重启策略为 `unless-stopped` 或等效的受管
  重启策略。

## 相关页面

- [安全模型与加固](Security-Model-and-Hardening)
- [备份、恢复与密钥轮换](Backup-Restore-and-Secret-Rotation)
- [健康检查与故障排查](Health-Checks-and-Troubleshooting)
