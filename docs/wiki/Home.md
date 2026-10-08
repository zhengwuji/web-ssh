# WebSSH Wiki

WebSSH 是一个安全、自托管的工作空间，用于基于浏览器的 SSH 终端和
SFTP 文件操作。它面向家庭实验室、服务器管理以及希望获得多用户浏览器访问、
而不把连接数据发送到托管控制平面的团队。

本 Wiki 是面向运维人员和用户的详细指南。若需精简的项目概览、截图、
发布徽章和源代码，请访问
[WebSSH 代码仓库](https://github.com/zhengwuji/web-ssh)。

## WebSSH 提供什么

- 多个同时进行的 SSH 会话，支持标签页和分屏布局。
- 以源文件为先的 SFTP 工作空间，具有独立标签页、一到两个文件区域、
  预览、行内编辑、上传、下载以及服务器到服务器的传输。
- 每个用户各自的已保存配置文件、SSH 密钥、跳板主机、命令、命令集、
  记事本数据、设置以及 SSH 主机密钥信任。
- 通过 tmux 实现持久化的远程 shell。
- Linux 会话诊断，涵盖资源、进程、systemd 服务和
  Docker 容器。
- 本地账户、可选的 Passkey 与身份验证器应用（TOTP）、恢复码、
  OIDC、GitHub App 登录，以及可选的 LDAP/Active Directory 身份验证，
  并配有保守的身份验证保证。
- 管理性的用户管理、结构化审计日志、备份与恢复，
  以及适合可信自托管部署的安全控制。
- 完全本地的浏览器运行时：前端依赖已本地化，且没有内置
  遥测。

WebSSH 2.0 界面采用响应式、聚焦的会话工作空间：终端、
Files、Commands、Notes 以及受支持的 Linux 洞察，在桌面、平板和移动布局中
都始终与所选 SSH 会话保持一致。

## 选择你的路径

| 目标 | 从这里开始 |
|---|---|
| 在可信网络上试用 WebSSH | [快速开始](Quick-Start) |
| 了解数据卷、镜像和 Compose | [Docker 与 Docker Compose](Docker-and-Docker-Compose) |
| 通过 HTTPS 暴露 WebSSH | [生产部署](Production-Deployment) |
| 配置每一项环境设置 | [配置参考](Configuration-Reference) |
| 安全地连接 SSH 主机 | [SSH 连接与主机密钥](SSH-Connections-and-Host-Keys) |
| 启用 LDAP 或 Active Directory | [LDAP 与 Active Directory](LDAP-and-Active-Directory) |
| 启用 GitHub App 登录 | [GitHub 身份验证](GitHub-Authentication) |
| 执行备份和恢复 | [备份、恢复与密钥轮换](Backup-Restore-and-Secret-Rotation) |
| 诊断不健康的实例 | [健康检查与故障排查](Health-Checks-and-Troubleshooting) |
| 贡献代码或文档 | [开发与测试](Development-and-Testing) |

## 部署模型概览

![WebSSH 从浏览器起、经过单一 WebSSH 进程、直到其所拥有的 SSH 与 SFTP 目标的信任边界](https://github.com/zhengwuji/web-ssh/blob/main/docs/media/diagrams/system-trust-boundaries.png?raw=true)

受支持的路径会把身份验证、归属检查、网络策略、
主机密钥验证、有界的运行时工作、持久化状态和审计记录
都限制在明确的边界之内。可选的 OIDC 或 LDAP 身份绝不会绕过
本地的 WebSSH 账户与资源归属模型。

浏览器通过 HTTP 或 HTTPS 连接到 WebSSH。随后 WebSSH 打开到目标主机的 SSH
与 SFTP 连接。因此 WebSSH 在建立或
维持会话时会处理终端输入/输出、文件数据以及连接凭据。它是可信基础设施，
而不是对会话内容一无所知的端到端加密
中继。

持久化状态保存在 `DATA_DIR` 之下（在容器中通常是 `/app/data`）。
活跃的 Paramiko SSH 传输、活动终端读取器、临时 SFTP
连接以及配额协调都是进程本地的。

> **单 worker 要求：** 生产环境必须只运行一个 Gunicorn
> `gthread` worker。在文档给出的范围内增加线程数是受支持的；
> 在没有外部会话状态架构的情况下，增加应用 worker 或副本
> 是不受支持的。

## 家庭实验室与生产环境

随附的基础 Compose 文件使用 `DEPLOYMENT_PROFILE=homelab`。它让 HTTP
和私有网络的使用保持便捷，并把不安全的组合作为警告报告出来。
它不是推荐的面向互联网的配置。

生产 Compose 覆盖文件会启用 `DEPLOYMENT_PROFILE=production`，把
后端绑定到回环地址，要求特定的公共 HTTPS 源，启用安全
Cookie，关闭浏览器注册，阻止内部 SSH 目标，并要求
明确的受信任代理边界。不安全的组合会阻止启动。

在把 WebSSH 暴露给不受信任的网络之前，请先阅读
[生产部署](Production-Deployment)。

## 安全起点

- 用 HTTPS 和受信任的反向代理保护 WebSSH。
- 限制对主机、数据卷、日志和备份的访问。
- 在启用外部身份的同时，保留一个经过测试的本地应急管理员。
- 首次使用后复核主机密钥指纹，并把其变化视为事件。
- 对于对外暴露的多用户部署，保持 `BLOCK_INTERNAL_SSH=true`，除非
  有经过评审的用例需要私有目标。
- 安全地备份 `DATA_DIR`；一份备份可能同时包含持久化的 `SECRET_KEY`
  和加密后的私钥。
- 把[安全模型与加固](Security-Model-and-Hardening)页面用作
  部署检查清单。

## 文档范围

这些页面跟踪当前 WebSSH 项目，并涵盖公开的、受支持的
行为。被禁用的 UI 占位符不会被记录为可用功能。
当某项功能是可选的时，其页面会说明该功能开关、前提条件、
安全边界、启用步骤和回滚路径。

## 有用的项目链接

- [源代码仓库](https://github.com/zhengwuji/web-ssh)
- [容器镜像](https://github.com/zhengwuji/web-ssh/pkgs/container/webssh)
- [议题](https://github.com/zhengwuji/web-ssh/issues)
- [讨论](https://github.com/zhengwuji/web-ssh/discussions)
- [安全公告](https://github.com/zhengwuji/web-ssh/security/advisories)
- [交互式代码图](https://zhengwuji.github.io/web-ssh/code-graph/)
