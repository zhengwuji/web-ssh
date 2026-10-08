# 配置文件、跳板主机与命令

已保存的连接数据对每个 WebSSH 账号都是私有的。配置文件有意
排除 SSH 与跳板主机密码。

## 已保存的配置文件

一个配置文件可以存储：

- 显示名称；
- 主机名、端口与远程用户名；
- 选定的已存储密钥；
- 选定的跳板主机；
- tmux 偏好；
- 允许时的 Tailscale 授权模式；
- 连接后启动行为；
- 扁平分组与排序位置；
- 收藏状态。

依赖密码的配置文件会在所需字段处打开连接表单。
不需要密码的配置文件（例如可用的已存储密钥或已授权的
Tailscale 模式）可以直接从空面板启动。

在主机管理器中使用 **Duplicate**，基于现有配置文件创建新草稿。该草稿会复制连接、认证引用、跳板主机、
分组与连接后设置，为有界名称添加本地化的“副本”后缀，
并且没有源配置文件 ID。因此保存会创建一个独立
配置文件，绝不会覆盖原文件。密码仍然被排除，因为它们
从不存储在配置文件中。

## 收藏与分组

连接管理器提供：

- 一个 Favorites 区域；
- 具名的扁平分组；
- 一个 Ungrouped 区域；
- 按名称、主机、用户或分组搜索；
- 浏览器中的分组折叠状态；
- 拖放排序以及在分组之间移动。

分组是扁平标签，而不是嵌套文件夹。收藏的配置文件会被提升到
Favorites 区域。在依赖常规分组排序之前，请先将该配置文件移出收藏。

将最后一个配置文件移出某个真实分组需要显式确认，
因为空分组将不复存在。

## 跳板主机

跳板主机单独保存，因此多个目标配置文件可以复用同一个
堡垒机。在编辑配置文件时选择跳板主机。

在堡垒机和目标上使用最小权限。存在跳板主机
并不会绕过目标网络策略、会话所有权或主机密钥校验。

已保存的配置文件与跳板主机具有按字段、记录数与序列化字节的
预算。默认值允许 500 个配置文件、100 个跳板主机、每个存储 2 MiB 以及
合计 4 MiB。变更操作共享每用户速率限制。常规 UI
会将超出这些限制的旧版存储隔离，以免大型载荷通过 Socket.IO 被展开。停止所有 WebSSH 进程，然后使用有界
恢复 CLI 发现非密钥的记录摘要与不透明选择器，随后
删除精确记录：

```bash
python -m flask --app start connection-store list \
  --username USER --kind profiles --confirm-offline
python -m flask --app start connection-store delete \
  --username USER --kind profiles --selector SELECTOR --confirm-offline
```

跳板主机存储请使用 `--kind jump-hosts`。恢复流程在解析前后都会执行独立的
字节与记录上限，绝不打印启动
命令或未知字段，并保留跳板主机引用保护。不透明选择器会绑定单条记录的当前序号与内容，因此重复或
被截断的显示 ID 不会删除错误的记录；每次成功删除后都要重新列出。任何变更都不得使超限存储继续增长。已存储的密钥
引用必须属于同一个 WebSSH 账号。

对于无法在本地解析的仅限堡垒机使用的 DNS 名称，请配置一个精确的（exact）
`PROXY_JUMP_REMOTE_DNS_ALLOWLIST`。不要使用通配符。

## 命令库

命令库存储具名命令以及可选的操作系统范围：

- Linux
- macOS
- BSD
- Windows

在检测到远程系统后，操作系统感知过滤有助于呈现相关命令。已存储的命令仍是文本；在将其发送到
终端之前请先审查。

## 命令集（Command Sets）

命令集组合有序步骤。一个步骤可以引用库命令，或
包含自由文本。集合可以被复制、重新排序、分配给配置文件，并
为活动会话启动。

![WebSSH command-set workflow from saved connections through ordered steps and profile assignment](https://github.com/zhengwuji/web-ssh/blob/main/assets/command-sets.gif?raw=true)

配置文件使用显式的启动模式：

- `none`
- 一条库命令
- 一个命令集
- 自由文本启动命令

现有的旧版配置文件数据会以增量方式迁移到该模型中。

连接表单在 **Run after connecting** 下暴露这些模式，并在 SSH 连接开始前显示精确的（exact）预览。自由文本（Free text）可以保留
在集合内部，也可以通过 **Save as library command** 移入命令库。库步骤默认使用被引用命令的当前参数；
显式覆盖可以替换它们，包括替换为有意为空的
值。

**Run commands with sudo** 对新命令集是选择性加入的（opt-in for new command sets）。WebSSH 会为每条
非空且尚未以 `sudo` 开头的已解析命令行加上前缀；空行与
仅含注释的行保持不变。现有命令集（Existing command sets）以及由旧版转换创建的集合会保留其已保存的行为（legacy conversion keep their saved behavior）。WebSSH 不会存储或应答 sudo 密码（does not store or answer a sudo password），因此远程账号的常规提示符仍保持可见。解析后的命令文本最大长度为 maximum 4096 characters。

配置文件与命令集可以在不打开 SSH 连接的情况下创建、检查、更新或删除（created, inspected, updated, or deleted without opening an SSH connection）。当有配置文件引用某个命令集时，该命令集无法被删除（cannot be deleted while a profile references it）；当有集合或
配置文件引用某个库命令时，该库命令也无法被删除。界面会指出必须先
更改的引用。

新的 SSH 连接成功之后，WebSSH 会在服务器上解析最新的被引用
定义。命令集步骤之间仅以 `&&` 连接（joined with `&&`）。自由文本步骤内部的换行与 shell 控制流保持
不变（inside a free-text step remain unchanged）。重新附加到已有的持久 tmux 会话不会再次运行它们（persistent tmux session does not run them again）。

包含此前自由文本启动命令的配置文件在更新之后仍可继续工作（containing former free-text startup commands keep working after an update）。它们可以转换为具名集合，同时
旧版启动命令（legacy startup commands）仍作为回退保留存储。无需额外的环境变量、Compose 设置（No additional environment variable, Compose setting）、前端构建或外部服务。

## 活动会话中的命令

聚焦的会话工作区可以为活动终端搜索 Commands 与 Command Sets。
带有操作系统范围的条目会在可能的情况下对照检测到的目标进行过滤。选择 **Insert** 会向终端写入一条可见的
单行命令，但不会按下 Enter，把最终的审查与执行留给运维人员。

可选的 **Insert with sudo** 控件会为插入的命令加上前缀，而不
更改已存储的库条目。WebSSH 不会存储或应答 sudo
密码；交互式提示符仍留在终端中。多行条目
不会通过该活动会话快捷方式插入。

## 连接后行为

当配置文件被分配了连接后动作时，WebSSH 会等待 SSH
通道变为可用，然后提交选定的命令文本或有序
集合。请仅用于在重连之后可安全重复的命令。

避免在命令、配置文件名称或参数中嵌入机密。命令文本
可能出现在终端输出或会话记录中，具体取决于远程 shell
行为。

## 数据完整性

配置文件、跳板主机、命令、命令集与设置都是 JSON 存储，位于
所属用户的数据目录之下。更新会在逻辑存储锁之下执行完整的加载-修改-保存
周期，并以原子方式替换文件。

损坏的 JSON 会被报告为存储损坏，而不会静默变成
空存储。版本化迁移会保留现有安装，并在迁移写入之前创建
私有备份。

## 实用组织模式

对于更大的家庭实验室，请使用基于运维上下文的扁平分组：

- `Production`
- `Lab`
- `Network`
- `Storage`
- `Clients`

对每天访问的少量主机使用收藏。将共享
堡垒机放在 Jump Hosts 中，而不是复制它们的配置。

## 故障排查

### 启动配置文件时仍要求输入密码

该配置文件依赖目标或跳板主机的密码，或者所选的
已存储密钥不可用。密码被有意设计为不持久化。

### 连接后集合没有运行

检查配置文件的启动模式、被引用的命令/集合、远程 shell 状态，
以及所选步骤是否需要交互式输入。

### 分组消失了

分组通过配置文件标签存在。移出最后一个配置文件会在确认之后
移除该空分组。

### 拖拽过程中配置文件发生了变化

服务器会在原子移动之前校验预期的源分组。当另一个浏览器并发更改了该配置文件时，
请重新加载并重试。

## 相关页面

- [SSH 连接与主机密钥](SSH-Connections-and-Host-Keys)
- [终端与持久 tmux 会话](Terminal-and-Persistent-tmux-Sessions)
- [数据存储与持久化](Data-Storage-and-Persistence)
