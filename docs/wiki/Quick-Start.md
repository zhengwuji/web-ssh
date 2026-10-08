# 快速开始

本指南会启动一个持久化的 WebSSH 实例，用于评估或家庭实验室用途。
若要安装面向互联网的实例，请在接受用户之前先继续阅读
[生产部署](Production-Deployment)。

## 前提条件

- 受支持的 Linux 发行版（Debian/Ubuntu、RHEL/Fedora/CentOS、openSUSE、
  Arch 或 Alpine）、macOS 或 Windows。
- 带 Compose 插件的 Docker Engine，或安装程序的 `--mode source`
  路径，该路径只需要 Python 3.10 或更高版本。
- 一个空闲的 TCP 端口（默认为 `5000`）。
- 至少一台 WebSSH 能够访问的 SSH 服务器。
- 一个现代浏览器。

安装程序会检测发行版的包管理器，并安装所有缺失的组件：
Python、pip、`venv` 模块、curl、tmux、编译 LDAP 客户端所需的 C 工具链和
OpenLDAP 头文件，以及带 Compose 插件的 Docker。传入 `--skip-system-deps`
可禁用上述行为并自行管理软件包，
传入 `--no-install-docker` 则在需要安装 Docker 时直接失败。

## 方案一：单命令安装程序

仓库附带一个安装程序，可一步准备好部署目录并
启动 WebSSH。它会生成 `SECRET_KEY`，写入 `.env` 和
`docker-compose.yml`，并等待 `/ready`：

```bash
curl -fsSL https://raw.githubusercontent.com/zhengwuji/web-ssh/main/install.sh | sh
```

PowerShell：

```powershell
irm https://raw.githubusercontent.com/zhengwuji/web-ssh/main/install.ps1 | iex
```

常用参数：

```bash
./install.sh --port 8443 --tls self-signed --domain webssh.lan
./install.sh --mode source --dir /opt/webssh --no-start
./install.sh --mode source --from-git https://github.com/zhengwuji/web-ssh.git
./install.sh --allow-internal-ssh
```

该安装程序是幂等的：重复运行会复用现有的 `SECRET_KEY` 和
TLS 材料。它绝不会打印生成的密钥。

### 安装程序命令

```bash
./install.sh status                                  # service state and /ready
./install.sh port --port 9000                        # change the web port
./install.sh reset-password --username admin         # reset a local password
./install.sh reset-password --username admin --generate
./install.sh upgrade                                 # newest image or source
./install.sh uninstall                               # stop and remove (keeps data)
./install.sh uninstall --purge --yes                 # remove everything
```

`port` 会改写服务配置、对外发布的端口以及被接受的
CORS 源，然后重启服务。`reset-password` 还会使该账户的所有
现有浏览器会话失效；它可以通过交互方式读取密码、
从 `--password-file` 读取，或用 `--generate` 生成一个。`uninstall` 会保留
`<dir>/data`，除非指定了 `--purge`。

## 方案二：Docker Compose

下载家庭实验室 Compose 文件并启动 WebSSH：

```bash
mkdir webssh-deployment
cd webssh-deployment
curl -O https://raw.githubusercontent.com/zhengwuji/web-ssh/main/docker-compose.yml
docker compose up -d
```

PowerShell：

```powershell
New-Item -ItemType Directory -Path webssh-deployment
Set-Location webssh-deployment
Invoke-WebRequest `
  https://raw.githubusercontent.com/zhengwuji/web-ssh/main/docker-compose.yml `
  -OutFile docker-compose.yml
docker compose up -d
```

打开 `http://localhost:5000`，或把 `localhost` 替换为主机地址。

## 方案三：Docker run

```bash
docker run -d \
  --name webssh \
  -p 5000:5000 \
  -e CORS_ORIGINS=http://localhost:5000 \
  -v webssh_data:/app/data \
  --restart unless-stopped \
  ghcr.io/zhengwuji/web-ssh:latest
```

这个命名数据卷是必不可少的。它会在容器更新之间保留用户、设置、密钥、主机信任
以及自动生成的应用密钥。

## 创建第一个管理员

数据库为空的全新家庭实验室实例会重定向到 `/register`。
恰好由浏览器创建的第一个账户会成为管理员。该一次性
引导路径会在该账户存在后原子性地关闭。

请在可信网络上立即创建该账户。切勿把尚未认领的全新实例
暴露给不受信任的客户端。

如果你更希望显式地通过 CLI 引导，请禁用浏览器引导并运行：

```bash
docker compose exec webssh \
  /app/entrypoint.sh flask --app start:app create-admin --username admin
```

该命令会提示输入密码且不回显。对
已存在的用户名运行它会把该账户提升为管理员，但不会更改其密码。

## 验证实例

检查容器状态和就绪情况：

```bash
docker compose ps
curl -fsS http://localhost:5000/health
curl -fsS http://localhost:5000/ready
```

预期响应：

```json
{"status":"ok"}
```

```json
{"status":"ready"}
```

然后登录并做一次小规模的功能检查：

1. 打开 **Quick Connect**。
2. 输入 SSH 主机名、端口、远程用户名以及一种身份验证方式。
3. 只有在能够获得该保证时先核对指纹，然后才复核并接受主机密钥。
4. 打开一个终端并运行诸如 `uname -a` 之类的无害命令。
5. 打开 SFTP 工作空间并列出远程主目录。
6. 断开该会话。

## 理解默认的家庭实验室设置

基础 Compose 文件有意配置了：

- `DEPLOYMENT_PROFILE=homelab`
- 为可信网络便利而设的通配 CORS；
- 用于 HTTP 的非安全浏览器 Cookie；
- 启用 tmux 支持并默认选中；
- 一个 Gunicorn worker，配有有界的线程池；
- 持久化状态存放于 `webssh_data` 数据卷。

这些默认值在可信局域网中很方便，但不是生产
安全配置。

单命令安装程序会在保留家庭实验室
配置文件的同时收紧其中三项：使用精确的 `CORS_ORIGINS` 而非通配符、`ALLOW_CORS_WILDCARD=false`，
以及 `BLOCK_INTERNAL_SSH=true`（除非你传入 `--allow-internal-ssh`）。它还会
在启用 TLS 时设置 `SESSION_COOKIE_SECURE=true`。

## 常见的首次启动问题

### 页面无法加载

```bash
docker compose ps
docker compose logs --tail=200 webssh
```

确认没有其他进程已占用端口 `5000`，并且
容器的健康检查没有失败。

### `/ready` 返回 HTTP 503

响应只会列出失败的组件类别。典型原因包括
数据卷不可写、SQLite 故障、维护模式处于激活状态，或
运行时正在关闭。参见[健康检查与故障排查](Health-Checks-and-Troubleshooting)。

### SSH 无法访问主机

请从容器网络验证连通性，而不只是从 Docker 主机验证。
检查 DNS 解析、防火墙规则、SSH 端口以及 `BLOCK_INTERNAL_SSH`。

### 没有使用 tmux

远程 SSH 主机上必须安装 tmux。如果不可用，WebSSH
会回退到普通 shell。

## 后续步骤

- [Docker 与 Docker Compose](Docker-and-Docker-Compose)
- [生产部署](Production-Deployment)
- [用户与账户管理](Users-and-Account-Management)
- [SSH 连接与主机密钥](SSH-Connections-and-Host-Keys)
- [备份、恢复与密钥轮换](Backup-Restore-and-Secret-Rotation)
