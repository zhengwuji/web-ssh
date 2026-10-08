# Docker 与 Docker Compose

官方镜像发布在 `ghcr.io/zhengwuji/web-ssh`。该容器
以非 root 用户运行，并使用一个 `gthread` worker 启动 Gunicorn。

## 持久化数据卷

持久挂载 `/app/data`：

```yaml
services:
  webssh:
    image: ghcr.io/zhengwuji/web-ssh:latest
    volumes:
      - webssh_data:/app/data

volumes:
  webssh_data:
```

如果没有这个数据卷，用户、配置文件、密钥、主机信任、设置、备份以及
自动生成的应用密钥都会随容器一起消失。

仓库的 Compose 文件还会在 `/app/recovery` 挂载 `webssh_recovery`。
这个独立的持久化数据卷用于存放在线恢复的回滚状态，绝不能
嵌套在 `/app/data` 之下，也不能与其共享。

## 基础家庭实验室部署

```bash
curl -O https://raw.githubusercontent.com/zhengwuji/web-ssh/main/docker-compose.yml
docker compose up -d
```

基础文件发布 `5000:5000`，设置 `DEPLOYMENT_PROFILE=homelab`，允许
通配 CORS，使用与 HTTP 兼容的 Cookie，启用 tmux 集成，并
持久化 `/app/data`。

尽可能修改 Compose 文件以使用某个具体的源：

```yaml
environment:
  - CORS_ORIGINS=http://192.0.2.10:5000
  - ALLOW_CORS_WILDCARD=false
```

## 应用密钥

当未提供 `SECRET_KEY` 时，容器入口点会创建一个强
密钥并将其持久化到 `DATA_DIR/secret_key`。只要数据卷
得以保留，这让普通的容器重建变得安全。

如果覆盖了容器的 `DATA_DIR`，它必须是绝对路径，并且那个确切的
目录必须被持久挂载。日志、密钥和 `secret_key` 都会一起移动。
如果存在遗留的 `/app/data/secret_key`，请在启动前以 `0600` 权限把它复制到新的
`DATA_DIR`；启动过程会拒绝静默创建
第二个加密根。显式提供的外部 `SECRET_KEY` 仍
优先，并且不会被复制到数据目录中。

仅当部署具有刻意的密钥管理策略时才提供外部密钥。
`SECRET_KEY` 发生变化或丢失会使浏览器会话失效，
并导致无法解密已存储的 SSH 密钥。

## 生命周期与停止宽限期

基础服务使用 `stop_grace_period: 40s`。WebSSH 接受 1 到 30 秒的
应用关闭宽限期，默认值为 5。在关闭期间，它会停止
接受新工作、通知运行时任务，并且只等待有界的宽限期。

请让 Docker 的停止宽限期长于 `RUNTIME_SHUTDOWN_GRACE_SECONDS`，这样
应用就能在 Docker 发出强制终止之前取消读取器和传输。

## 健康检查

镜像和 Compose 文件会从容器内部探测 `/ready`。默认的
健康检查会等待：

- 应用运行时能够接受工作；
- 维护模式处于非激活状态；
- 一次成功的 SQLite 查询；
- 在 `DATA_DIR` 中完成创建/写入/fsync/删除探测。

用以下命令检查状态：

```bash
docker compose ps
docker inspect --format '{{json .State.Health}}' webssh
docker compose logs --tail=200 webssh
```

## 更新镜像

在更新之前，先创建并下载一份经过验证的备份。然后：

```bash
docker compose pull webssh
docker compose up -d
docker compose ps
curl -fsS http://localhost:5000/ready
```

如果较早的镜像已经创建了 `webssh_recovery` 数据卷，其中 `/app/recovery` 归
root 所有，而启动现在报告 `Permission denied`，请先停止
服务再修复它。空的数据卷可以被 Compose 移除并
重新创建。在一次中断的恢复期间或之后，绝不要移除非空的恢复数据卷；
请保留其内容，并由管理员把该数据卷的根目录改为镜像中 `appuser` 的 UID/GID 和 `0700` 权限。

在替换之前记录当前部署的不可变镜像摘要：

```bash
docker image inspect \
  ghcr.io/zhengwuji/web-ssh:latest \
  --format '{{index .RepoDigests 0}}'
```

对于受控的生产发布，请使用不可变的版本标签或摘要。

## 可选的 Redis 限流存储

默认的 `memory://` 后端会在进程重启时重置限流计数器。
若要在 Redis 可用期间保留计数器，请从随附的 Compose 注释中
启用私有的 Redis 服务并设置：

```yaml
environment:
  - RATELIMIT_STORAGE_URL=redis://redis:6379/0
```

不要对外发布 Redis 端口。如果 Redis 变得不可用，WebSSH 会使用
内存回退，并定期重试外部后端。

Redis 并不会让多个 WebSSH worker 变得安全。活跃的 SSH 传输和其他
协调工作仍保留在进程本地。

## 可选覆盖文件

Compose 文件从左到右应用。靠后的覆盖文件优先。

生产：

```bash
export WEBSSH_ORIGIN=https://ssh.example.com
docker compose \
  -f docker-compose.yml \
  -f docker-compose.production.yml \
  up -d
```

LDAP 加生产：

```bash
export WEBSSH_ORIGIN=https://ssh.example.com
docker compose \
  -f docker-compose.yml \
  -f docker-compose.ldap.yml \
  -f docker-compose.production.yml \
  up -d
```

请始终使用来自同一发布版本或提交的基础文件和覆盖文件。LDAP
覆盖文件会为 WebSSH 添加一个只读密钥挂载以及一个独立的辅助配置文件；
生产覆盖文件排在其后，因此其安全设置具有权威性。
可选择在生产覆盖文件之后追加 `-f docker-compose.hardened.yml`，以启用
额外的容器限制。在选择启用之前，请检查自定义可写路径、运行时 UID/GID
和资源预算；参见
[容器边界](https://github.com/zhengwuji/web-ssh/blob/main/docs/production-container.md)。

## 检查生效的配置

在更改正在运行的部署之前：

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.production.yml \
  config
```

对于 LDAP，请按启动时所用的相同顺序包含 `docker-compose.ldap.yml`。
复核对外发布的端口、环境变量值、挂载以及所选镜像。

## 备份边界

`webssh_data` 数据卷被原生备份格式所覆盖。独立的
LDAP 绑定密码与 CA 数据卷则有意不包含在内。请把两者都视为
机密，并记录各自如何恢复。

## 相关页面

- [生产部署](Production-Deployment)
- [LDAP 与 Active Directory](LDAP-and-Active-Directory)
- [备份、恢复与密钥轮换](Backup-Restore-and-Secret-Rotation)
- [升级、回滚与常见问题](Upgrading-Rollback-and-FAQ)
