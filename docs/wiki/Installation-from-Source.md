# 从源码安装

源码安装适用于开发、调试以及不使用容器的运维人员。
Docker 仍是最简单的受支持部署方式，因为该镜像提供了非 root 运行时、持久化密钥引导、Gunicorn
以及健康检查。

## 要求

- Python 3.11 或更高版本。
- Git。
- 一个能够为所选 Python 版本安装锁定
  二进制依赖的操作系统构建环境。
- 仅在更新或测试前端资源时需要 Node.js。运行时提供 WebSSH 服务
  并不需要 Node。

## 克隆并创建虚拟环境

Linux 或 macOS：

```bash
git clone https://github.com/zhengwuji/web-ssh.git
cd webssh
python3 -m venv venv
source venv/bin/activate
python -m pip install --upgrade pip
python -m pip install --require-hashes -r requirements.txt
```

PowerShell：

```powershell
git clone https://github.com/zhengwuji/web-ssh.git
Set-Location webssh
python -m venv venv
.\venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install --require-hashes -r requirements.txt
```

提交到仓库的 `requirements.txt` 是一个带哈希的完整跨平台锁定文件。
生产环境不要用不受约束的 `pip install`
流程替换这种带哈希的安装方式。

## 开发启动

生成一个强开发密钥并运行应用：

```bash
export SECRET_KEY=$(openssl rand -hex 32)
export DEBUG=True
python start.py
```

PowerShell：

```powershell
$env:SECRET_KEY = python -c "import secrets; print(secrets.token_hex(32))"
$env:DEBUG = 'True'
python start.py
```

打开 `http://127.0.0.1:5000`。

## 非容器生产启动

在容器之外，生产环境必须显式获得一个 `SECRET_KEY`。
配置生产配置文件，并只运行一个 Gunicorn `gthread` worker：

```bash
export SECRET_KEY=$(openssl rand -hex 32)
export DEPLOYMENT_PROFILE=production
export CORS_ORIGINS=https://ssh.example.com
export SESSION_COOKIE_SECURE=true
export REGISTRATION_ENABLED=False
export BOOTSTRAP_REGISTRATION_ENABLED=false
export BLOCK_INTERNAL_SSH=true
export TRUSTED_PROXIES=1

gunicorn \
  --worker-class gthread \
  --workers 1 \
  --threads 64 \
  --bind 127.0.0.1:5000 \
  start:app
```

为 Gunicorn 配置一个服务管理器，并在受信任的反向
代理处终止 TLS。绑定地址和 `TRUSTED_PROXIES` 值必须与真实的网络
边界一致。

## 持久化数据

对于源码检出目录，`DATA_DIR` 默认为 `./data`。它包含数据库、
每用户 JSON 存储、加密密钥、主机信任、日志以及临时工作
目录。对于受管部署，请设置一个由服务所有的绝对目录：

```bash
export DATA_DIR=/var/lib/webssh
```

请使用 WebSSH 自带的备份工具来备份该目录，而不要独立复制
正在使用的文件。参见[数据存储与持久化](Data-Storage-and-Persistence)。

## 前端资源

WebSSH 在正常运行时没有前端构建流水线。浏览器依赖
固定于 `package.json`，被复制到 `static/vendor/`、提交到仓库并
在本地提供。若要刻意刷新它们：

```bash
npm install
npm run vendor
npm run vendor:check
```

不要添加运行时 CDN 依赖；支持离线运行的 CSP 和 vendor
完整性检查都假定资源位于本地。

## 更新依赖

直接的 Python 约束位于 `requirements.in` 和
`requirements-test.in`。用以下命令重新生成带哈希的锁定文件：

```powershell
pwsh -File scripts/lock_requirements.ps1
```

在不修改它们的前提下验证可重现性：

```powershell
pwsh -File scripts/lock_requirements.ps1 -Check
```

## 继续

- [配置参考](Configuration-Reference)
- [开发与测试](Development-and-Testing)
- [生产部署](Production-Deployment)
