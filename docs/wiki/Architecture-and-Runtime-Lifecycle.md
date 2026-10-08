# 架构与运行时生命周期

WebSSH 是一个 Flask 应用，具备已认证的 HTTP 与 Socket.IO 接口、Paramiko SSH/SFTP 通道、SQLite 持久化以及一个有界的线程化运行时。

## 请求与连接流

![WebSSH 信任边界，展示可信代理入口、单进程、持久化状态、审计与受管目标](https://github.com/zhengwuji/web-ssh/blob/main/docs/media/diagrams/system-trust-boundaries.png?raw=true)

浏览器不会通过隐藏的点对点路径直接连接到 SSH 目标。WebSSH 终止已认证的应用会话、检查所有权与策略，然后打开服务器端的 SSH 或 SFTP 连接。

```text
Browser
  |-- HTTPS/forms/API --------> Flask routes and blueprints
  |-- Socket.IO controls -----> authenticated socket events
  |-- streamed transfers -----> HTTP transfer routes
                                   |
                                   v
                          ownership and quota checks
                                   |
                      +------------+-------------+
                      |                          |
                  SSH manager              persistent storage
                      |                   SQLite + per-user files
               Paramiko channels
                      |
                SSH/SFTP servers
```

大块文件内容通过 HTTP 流式传输。Socket.IO 承载终端流量、控制事件以及有界的编辑器内容，而不是整块的批量传输载荷。

## 应用入口点

- `start.py` 通过 `app/__init__.py` 中的 `create_app()` 创建应用。
- 各专门化的 blueprint 实现传输、主机密钥、审计导出、备份/恢复、恢复码、WebAuthn、OIDC、LDAP 以及健康/就绪检查。
- `app/socket_events.py` 定义用于终端、SFTP、profile、密钥、命令、诊断与传输的已认证实时契约。
- `app/ssh_manager.py` 持有进程本地的 SSH 状态。
- `app/paramiko_channels.py` 集中创建有界的 Paramiko 通道。

## 单 worker 契约

生产环境使用：

```bash
gunicorn --worker-class gthread --workers 1 --threads 64 \
  --bind 0.0.0.0:5000 start:app
```

仅支持恰好一个（exactly one）worker。活动的 Paramiko 对象、会话协调以及部分资源准入都是进程本地的。多个 worker 会产生各自隔离的实时状态视图，并可能违反所有权、配额、清理与路由方面的假设。

Redis 支持的速率限制仅将计数器外置。它不会外置 SSH 通道，也不会使应用变成多 worker 架构。

## Socket 准入与 HTTP 预留（HTTP reserve）

`app/socket_capacity.py` 在全局与每用户两个维度限制已准入的 socket。容量必须为常规 HTTP 工作保留至少四个 Gunicorn 线程：

```text
GUNICORN_THREADS - MAX_SOCKET_CONNECTIONS >= 4
```

默认值为 64 个线程与 48 个 socket，每个用户最多八个 socket。Socket.IO 使用原生线程化（threading）与 simple-websocket；Eventlet、greenlet 与 monkey patching 不属于受支持的运行时。

## 后台工作

`app/runtime_lifecycle.py` 持有一个有界的 `ThreadPoolExecutor`。任务具有取消状态、所有权以及显式的终结化。LDAP 缓存清理、传输、SSH/SFTP 辅助工作以及其他后台任务必须共享这一有界生命周期，而不是创建无限制的线程循环。

## SSH 与 SFTP 生命周期

SSH 连接归属于某个已认证用户并消耗配额。Paramiko 通道通过既有的辅助函数创建，并带有超时与取消机制。文件工作区使用的快速 SFTP 连接会在排队中或活动中的传输仍然引用它们时保持存活，随后在所有权可以安全结束时断开。

持久化的 tmux 元数据可在浏览器断开后继续存在，但底层的远程 tmux 会话位于 SSH 服务器上。WebSSH 的本地连接对象无法在进程重启后继续存在。

## 优雅关闭

关闭时 WebSSH 会：

1. 关闭新运行时工作的准入；
2. 向可取消的任务发出信号；
3. 在配置的时间窗口内停止或终结其所属操作；
4. 关闭 SSH/SFTP 与 Socket.IO 资源；
5. 退出，以便进程监督器完成替换或重启。

一旦运行时不再接受工作，就绪性即报告失败。请让代理/负载均衡器的排空时间与 `RUNTIME_SHUTDOWN_GRACE_SECONDS` 保持一致。

## 维护模式

恢复操作在替换持久状态之前进入维护模式。`/health` 仍是存活性检查，而 `/ready` 会失败，以便流量被排空。随后恢复会有意终止进程，以保证替换后处于干净的应用状态。

## 前端架构

前端使用原生 JavaScript 与 CSS，不依赖构建期应用框架。浏览器库在 `package.json` 中固定版本，本地 vendored，并进行完整性校验。运行时 CDN 依赖被有意去除，因此前端保持离线可用并与 Content Security Policy 兼容。
