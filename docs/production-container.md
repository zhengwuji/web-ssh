# 生产容器边界

请使用 Docker Compose 2.24.4 或更高版本，并在使用 `docker-compose.production.yml`
启动基础文件之前，将 `WEBSSH_ORIGIN` 设置为确切的公网 HTTPS 源。
生产叠加文件保留既有的 HTTPS、cookie、注册、代理和目标策略设置，
并将端口 5000 绑定到回环地址。

```bash
export WEBSSH_ORIGIN=https://ssh.example.com
docker compose -f docker-compose.yml -f docker-compose.production.yml config
docker compose -f docker-compose.yml -f docker-compose.production.yml up -d
```

更新此配置不会施加新的文件系统、任务或内存限制，不会替换自定义运行时目录，
也不会添加临时挂载。现有的自定义限制和挂载仍由操作者控制。仅更新镜像
不会改变 Compose 设置。请使用同一发布版本或同一提交中的文件。

## 可选的容器限制

在生产叠加文件之后追加 `docker-compose.hardened.yml`，以启用只读根文件系统、
丢弃的 Linux 能力、`no-new-privileges`、受限的 tmpfs 挂载以及明确的内存/任务上限：

```bash
docker compose -f docker-compose.yml -f docker-compose.production.yml -f docker-compose.hardened.yml config
docker compose -f docker-compose.yml -f docker-compose.production.yml -f docker-compose.hardened.yml up -d
```

这是一个明确的部署选择。启用之前，请检查应用/自定义入口点的写入、自定义挂载、
运行时属主以及工作负载容量。它适用于当前镜像；在应用这些限制之前，
请先测试较旧或派生的镜像。现有安装可以在不启用此叠加文件的情况下，
沿用其既有的部署设置使用当前镜像。

标准镜像以 UID/GID 1000 运行。启用加固后，可写位置为：

| 路径 | 用途 | 生命周期 |
| --- | --- | --- |
| `/app/data` | 数据库、生成的密钥、用户文件和应用程序临时文件 | 持久化数据卷 |
| `/app/recovery` | 位于每实例私有目录中的备份操作、恢复暂存和回滚副本 | 持久化恢复卷 |
| `/tmp` | 通用临时文件 | tmpfs，容器重建时清空 |
| `/run/webssh` | 私有 Gunicorn 运行时/控制套接字目录 | 1 MiB tmpfs，权限模式 0700 |

两个 tmpfs 挂载均禁用执行、设备节点和 set-user-ID 行为。
`XDG_RUNTIME_DIR=/run/webssh` 使 Gunicorn 运行时文件不落在只读根文件系统上。
请保持数据卷和恢复卷对生效的容器用户可写。
对于自定义的 `user:` 设置，请将 `WEBSSH_RUNTIME_UID` 和 `WEBSSH_RUNTIME_GID`
设置为相同的数字 ID，并在持久化挂载上配置相匹配的权限。这些变量设置的是
运行时挂载的属主；它们不会更改容器用户，也不会递归更改现有数据的权限。

| Compose 变量 | 加固默认值 | 用途 |
| --- | --- | --- |
| `WEBSSH_PIDS_LIMIT` | `512` | 最大任务数，包括进程和线程 |
| `WEBSSH_MEMORY_LIMIT` | `2g` | 容器内存上限，包括 tmpfs 用量 |
| `WEBSSH_TMPFS_SIZE` | `128m` | 由临时操作共享的 `/tmp` 容量 |
| `WEBSSH_RUNTIME_UID` / `WEBSSH_RUNTIME_GID` | `1000` / `1000` | 私有运行时挂载的属主 |

请在 Compose 环境或 `.env` 中设置这些变量，使用完整的文件列表检查
`docker compose config`，然后重建服务。例如，`WEBSSH_TMPFS_SIZE=1g`
会扩展 `/tmp`；同时也要配置合适的内存上限。
`/tmp` 下的自定义 `TRANSFER_TEMP_DIR` 共享该容量。并发的归档/导出操作可能将其耗尽，
即使每一次都低于应用程序配额。对于更大的工作负载，请将传输暂存文件放在
容量足够的可写挂载上，或保留默认的 `DATA_DIR/tmp`。常规 HTTP 上传会流式写入
目标位置，不需要在 `/tmp` 中占用其完整大小。
当根文件系统为只读时，文档化卷之外的自定义写入路径需要各自拥有可写挂载。
请勿将持久化恢复数据放在 tmpfs 上。

请只保留一个 Gunicorn worker；默认的 64 个 Gunicorn 线程和 48 个
套接字连接可使 HTTP 容量保持可用。SSH 传输线程、后台工作、传输任务和
tmpfs 内容同样会消耗资源。在提高应用程序并发之前，请监控
内存/OOM 事件和任务数。资源上限并非经过负载测试的并发保证。40 秒的
停止宽限期让有界应用程序关闭得以完成。

## 备份与恢复兼容性

恢复存储必须位于数据目录、静态文件和日志之外；
恢复操作还会拒绝与其实际目标位置重叠的恢复存储。
请为归档、解压文件和有回滚副本预留空间。恢复写入使用原子文件复制，
因此恢复数据可以驻留在独立的文件系统上。

`flask --app start:app backup create --confirm-offline` 在可写时仍使用 `DATA_DIR`
的父目录。如果该目录为只读或拒绝写入，该命令将使用 `BACKUP_TEMP_DIR` 下的
每实例私有目录，并打印归档文件的实际路径。显式的 `--destination` 永远不会被
重定向；空间不足、源读取错误和已存在的目标位置仍会失败。使用所提供的 Compose
文件时，回退归档驻留在持久化恢复卷上。使用自定义设置时，请使用持久化的备份存储，
并将已完成的归档复制到加密的异地存储。留在一次性容器可写层或临时目录中的
备份不具有持久性。CLI 备份与恢复要求应用程序已停止，并且需要离线确认。

## 可选的身份验证与网络

对于 LDAP，请按此顺序合并基础文件、LDAP 文件和生产文件，如需加固再追加加固文件：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml -f docker-compose.production.yml config
docker compose -f docker-compose.yml -f docker-compose.ldap.yml -f docker-compose.production.yml up -d
```

请先按照 [LDAP 指南](ldap-authentication.md) 配置 LDAP 并初始化密钥。
`/run/webssh-auth` 仍是一个独立的只读机密卷挂载；它不在 `/run/webssh` 的覆盖范围内。
只有显式调用的 `ldap-tools` 辅助工具会写入这些机密。可选限制适用于 WebSSH 服务。

叠加文件不会创建 Tailscale 接口或守护进程。
[Tailscale SSH](tailscale-ssh.md) 需要其文档所述的内核接口和共享网络命名空间，
以及显式的用户、目标和远程用户允许列表。请将 TUN 设备与网络能力保留在
独立的 Tailscale 服务中。自定义 sidecar 部署必须将已发布的端口移动到
拥有该命名空间的 sidecar 上。生产目标策略和接口检查仍然适用。

## 一次性运行时验证

`scripts/check_hardened_container.py --image IMAGE --revision COMMIT_SHA
--platform linux/amd64` 会演练既有的生产设置、可选加固，以及带有自定义 UID/GID、
传输路径和更大 tmpfs 的加固配置。它会检查修订版本、就绪状态、文件系统/进程限制、
一次 160 MiB 的暂存写入、在线备份、离线 CLI 备份、恢复、SQLite 完整性、
重启和优雅关闭。另一个发布平台请使用 `linux/arm64`。`--profile` 可以选择
`compatible`、`hardened` 或 `hardened-custom`；CI/发布检查会运行全部三种配置。
该辅助工具使用匿名卷和带有唯一标签的一次性容器，
并在删除它们之前检查属主。它不使用部署数据。
镜像扫描和不可变发布候选检查仍然是必需的。这些
是功能性冒烟测试，并非对每个自定义镜像或工作负载的证明。
