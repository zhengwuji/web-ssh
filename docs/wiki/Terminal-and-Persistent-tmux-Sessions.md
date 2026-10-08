# 终端与持久 tmux 会话

WebSSH 在浏览器中使用 xterm.js，在服务器上使用 Paramiko 通道。Socket.IO
承载终端控制与输出事件。

## 会话工作区

终端支持：

- 多个会话标签页；
- 一窗格、两窗格与四窗格布局；
- 在打开的会话之间广播输入；
- 使用 `Ctrl+K` 的命令面板；
- 使用 `Ctrl+F` 的终端搜索；
- 使用 `Ctrl+1` 到 `Ctrl+9` 切换标签页；
- 可在 50 到 10,000 行之间配置的回滚缓冲；
- 会话记录下载；
- 最近连接；
- 持久会话名称；
- 每会话备注；
- 手动重连（manual reconnect）。

在 macOS 上，请使用平台对应的 Command 组合键进行复制和粘贴。

`Ctrl+C` 会复制选中的文本。在没有选中内容时，它向远程进程发送常规的
中断字符。

当 tmux 鼠标模式拥有选中区域时，WebSSH 会为该持久会话接受 tmux 的有界 OSC 52
剪贴板请求。在远程文本到达浏览器
剪贴板之前，需要先有一次新的 **Copy** 点击并伴有可见的 WebSSH 通知。重放输出以及普通的非 tmux SSH 会话无法请求
剪贴板写入。浏览器剪贴板权限仍然适用。

远程 OSC 52 剪贴板请求被限制为 128 KiB 的解码 UTF-8 文本。
超大的 OSC/DCS 控制字符串会在能够累积无界浏览器内存之前被终端解析器
丢弃。

### 远程 tmux 剪贴板配置

WebSSH 在新连接和重连时都会保留远程 tmux 配置。它不会自动更改 `set-clipboard` 或 `allow-passthrough`。
现有的持久会话会继续使用相同的 tmux 服务器与会话名称。

对于 tmux 自身的复制模式，`set-clipboard external` 允许 tmux 在附加终端支持时发送剪贴板
请求，同时阻止 tmux 内部的应用程序设置其剪贴板缓冲区。诸如编辑器之类的会
发出自身 OSC 52 序列的应用程序可能需要额外的运维人员配置。

即使命令中包含 `-t session`，`set-clipboard` 也是**服务器范围**的选项。如果你有意
希望该服务器上每个会话中的应用程序都能设置剪贴板内容，请在远程主机上
进行如下配置：

```tmux
set-option -s set-clipboard on
```

这也会影响使用该 tmux 服务器的其他会话以及附加的原生终端。WebSSH 的 Copy 确认仅保护 WebSSH 浏览器，而不保护那些
其他客户端。如果不需要这种更广泛的影响，请保持现有策略不变。

`allow-passthrough` 仅对使用 tmux 的 DCS 直通包装的应用程序需要，
对普通的 tmux 复制模式则不需要。在支持该选项的 tmux 版本上，希望它在所有窗口生效的运维人员可以显式配置：

```tmux
set-option -gw allow-passthrough on
```

这会更改该服务器上继承该设置的现有窗口与未来窗口的默认值。显式的窗口或窗格覆盖仍然优先；如有需要，请单独检查并
配置它们。仅使用 `-t session` 会更改所选窗口，而不是该会话的所有窗口。直通还允许其他
被包装的终端序列，因此请仅在有意使用的地方启用它。

这些设置属于远程账号的 tmux 配置，或者也可以在不终止会话的情况下
应用于正在运行的服务器。有关终端
capability（能力）检查与应用程序特定的设置，请参阅
[tmux 剪贴板指南](https://github.com/tmux/tmux/wiki/Clipboard)。

## 广播输入

广播模式会把相同的输入发送到每个打开的 SSH 会话。请将其视为
高影响操作：

- 核实可见的目标集合；
- 先用无害的命令开始；
- 避免使用状态可能产生分歧的交互式程序；
- 在预期动作完成后立即禁用广播。

WebSSH 不会解释某条命令对每个目标是否安全。

## 聚焦会话工作区（focused session workspace）

单窗格布局可以把活动会话的 SFTP 浏览器放在
终端旁边，并在备注旁显示 Linux 资源信息。在宽桌面
布局中，SFTP 伴侣可以为单个已连接会话打开；对该会话而言，手动
关闭会被尊重。

上下文区域跟随所选会话，并让 Notes、Commands、Files（文件）以及受支持的诊断信息触手可及。WebSSH 会探测每项能力（capability），而不是假定每个 SSH 目标都是 Linux 或都提供 SFTP。不受支持的工具
保持不可用，而核心终端仍可使用。切换会话
或调整浏览器尺寸会保留当前上下文，而不重新连接 SSH。

### 活动会话的命令

Commands 上下文会搜索用户的 Commands 与 Command Sets，在适用时按检测到的操作系统过滤
条目，并向活动终端插入一条
可审查的文本行。它不会按下 Enter。可选的
`sudo` 控件会为插入的命令加上前缀；WebSSH 从不存储或应答
sudo 密码，因此任何所需的提示符都会在终端中保持可见。

## 诊断

对于受支持的 Linux 目标，WebSSH 可以请求：

- CPU、内存、磁盘、负载与运行时间；
- 进程数与网络吞吐量计数；
- 历史与压力图表；
- CPU 与内存占用最高的进程；
- systemd 服务清单；
- Docker 容器清单。

服务操作控件不会执行命令。它们生成一条加入允许列表的
`systemctl` 命令，并在有可见确认的情况下复制到剪贴板。由
运维人员决定是否执行以及在何处执行。

诊断是当前 SSH 会话之上的便利层，而不是主机
监控或提权代理。

## 浏览器刷新与重连

![WebSSH realtime SSH session and bulk transfer paths with ownership and transport boundaries](https://github.com/zhengwuji/web-ssh/blob/main/docs/media/diagrams/session-and-transfer-lifecycle.png?raw=true)

终端控制与输出使用经过认证的 Socket.IO 事件，围绕一个有归属的、
进程本地的 SSH 会话。批量传输正文走下方所示的独立有界 HTTP
路径；它们不会被编码进终端事件。

每个实时输出事件都会被计入每浏览器、每用户与进程范围的
预算，直到浏览器确认接受它。达到容量时，WebSSH 会停止
读取 Paramiko 通道，从而应用 SSH/TCP 背压。若浏览器
在配置的超时时间内一直阻塞确认预算，该浏览器会被
断开，而其底层 SSH 或持久 tmux 会话仍可用于重连。

浏览器可以在不注入终端输入的情况下，为刷新后的活动会话恢复 UI 状态。底层 SSH 传输保持进程本地；
WebSSH 进程重启会关闭普通 SSH 会话。

手动重连（manual reconnect）行为取决于认证方式：

- 已存储密钥与 Tailscale 会话在获得授权时可以直接重连；
- 密码会话会在密码字段处重新打开一个预填充的连接表单。

密码不会保留在会话对象中用于重连。

## 持久 tmux 会话（persistent tmux）

tmux 运行在远程 SSH 主机上。当浏览器关闭、WebSSH 传输断开或 WebSSH 重启时，
它会让远程 shell 与命令继续存活。

配置：

```bash
TMUX_ENABLED=true
TMUX_DEFAULT=true
TMUX_SESSION_PREFIX=webssh
```

基础 Compose 文件会启用并预选 tmux。源码安装在未配置时默认
为禁用。

### 要求

- 远程主机上已安装 tmux；
- 远程 SSH 用户具有创建会话的权限；
- 可用的 shell 环境；
- 稳定的前缀与远程用户名。

如果 tmux 不可用，WebSSH 会回退到常规 shell。

### 会话身份

WebSSH 使用其配置的前缀与连接身份创建或重新附加远程 tmux 会话。持久显示名称可以跨浏览器保留。

断开 WebSSH 传输与终止远程 tmux
会话不同。仅当远程工作负载应当结束时，才使用故意的终止操作。

## 空闲超时

`SESSION_TIMEOUT` 默认为 1800 秒，会关闭空闲的 WebSSH SSH 会话。
这并不意味着 30 分钟的浏览器 HTTP 会话超时。远程 tmux
会话可以继续存活并稍后重新附加。

## 容量

默认 SSH 配额为全局 10 个会话、每用户 5 个。每个实时终端
读取者都占用有界的运行时容量。默认值会计算足够的
后台 worker，用于清理循环、每个已准入的 SSH 读取者以及允许的
后台作业。

## 故障排查

### 终端打开后一直空白

检查远程 shell 启动、横幅或 MFA 交互、通道日志以及浏览器
Socket.IO 连接性。

### 终端在代理之后断开

核实 WebSocket 升级转发、代理超时、CORS 源以及子目录
前缀处理。

### 持久会话没有被恢复

确认同一远程用户存在 tmux、前缀没有变化，并且
运维人员没有终止该 tmux 会话。常规 shell 无法在
WebSSH 重启后存活。

### 诊断为空

远程系统可能不是 Linux、命令可能缺失，或者 SSH 用户可能
缺少检查所请求数据的权限。核心终端访问仍然
独立可用。

## 相关页面

- [SFTP 文件工作区与传输](SFTP-File-Workspace-and-Transfers)
- [配置文件、跳板主机与命令](Profiles-Jump-Hosts-and-Commands)
- [架构与运行时生命周期](Architecture-and-Runtime-Lifecycle)
