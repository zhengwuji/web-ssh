# 内置 HTTPS 与自动证书

WebSSH 可以自行终止 TLS 并自动保持证书续期，
类似 3x-ui 管理其面板证书的方式。完全通过环境变量进行配置——
无需手动搬运证书。

| `WEBSSH_TLS_MODE` | 作用 |
| --- | --- |
| `off` *（默认）* | 纯 HTTP 监听；在前面放置你自己的反向代理。 |
| `self-signed` | 首次启动时为**域名或裸 IP** 生成私有证书，并**自动轮换**（默认有效期 825 天，到期前 30 天轮换）。 |
| `acme` | 通过 [acme.sh](https://github.com/acmesh-official/acme.sh)（HTTP-01）签发**受公网信任**的证书，并**自动续期**。域名适用于 Let's Encrypt/ZeroSSL；裸 IP 使用 Let's Encrypt 的短期 profile。 |
| `manual` | 提供由运维人员提供的 PEM 文件。 |

所有模式都将材料存放在 `$DATA_DIR/tls/`（默认 `/app/data/tls`）下，
该目录位于你的持久化卷上，并以 TLS 在常规 `PORT`（5000）上启动 gunicorn。

## 域名证书（推荐）

```yaml
# docker-compose.yml
services:
  webssh:
    # ...
    environment:
      WEBSSH_TLS_MODE: acme
      WEBSSH_TLS_DOMAIN: ssh.example.com
      WEBSSH_TLS_EMAIL: you@example.com
    ports:
      - "80:80"      # HTTP-01 challenge, ACME only
      - "443:5000"   # HTTPS
```

要求：

- `ssh.example.com` 能公开解析到本主机。
- 在签发与续期期间，端口 80 可从互联网访问。
- 可访问出站 HTTPS（acme.sh 会在首次启动时安装到
  `$DATA_DIR/tls/acme-home/` 下）。

续期在容器内以看门狗循环运行（默认每 12
小时一次）；acme.sh 仅在证书确实到期时才重新签发，然后
重新安装这些文件并向 gunicorn 主进程发送信号使其加载它们
（`SIGHUP`）。无需重启。

## 裸 IP 地址

公共 CA 仅在短期 profile 下为 IP 标识符签名：

```yaml
environment:
  WEBSSH_TLS_MODE: acme
  WEBSSH_TLS_DOMAIN: 203.0.113.10
  WEBSSH_TLS_EMAIL: you@example.com
```

如果你的 ACME 账户无法签发 IP 证书，请使用 `self-signed` 模式，
它支持 IP（作为 SAN）并自动轮换：

```yaml
environment:
  WEBSSH_TLS_MODE: self-signed
  WEBSSH_TLS_DOMAIN: 192.168.1.10
```

浏览器会对自签名证书显示信任警告；通行密钥
和 SSH 连接不受影响，因为浏览器用户只需接受该
证书一次。

## 调优

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `WEBSSH_TLS_CA` | `letsencrypt` | ACME 服务器（`letsencrypt` 或 `zerossl`）。 |
| `WEBSSH_TLS_RENEW_WITHIN_DAYS` | `30` | 在到期前这么多天轮换自签名证书。 |
| `WEBSSH_TLS_RENEWAL_CHECK_HOURS` | `12` | 续期看门狗的周期。 |
| `WEBSSH_TLS_CERT_DIR` | `$DATA_DIR/tls` | 证书/密钥目录（`fullchain.pem`、`privkey.pem`）。 |
| `WEBSSH_TLS_ACME_PORT` | `80` | acme.sh 为 HTTP-01 挑战绑定的端口。 |

## 说明

- 当某个 TLS 模式处于启用状态时，容器健康探测会自动使用 HTTPS
  （探测本身接受不受信任的证书）。
- `manual` 模式要求 `fullchain.pem` 和 `privkey.pem` 位于
  `WEBSSH_TLS_CERT_DIR` 中，否则会快速失败。
- 密钥文件始终为 chmod 600；目录为 chmod 700。
- 当 TLS 在 WebSSH 内部终止时，通行密钥会自动从
  请求 host 推导其依赖方 ID；如果你以与证书域名不同的
  公开名称提供该面板，请显式设置 `WEBAUTHN_RP_ID` /
  `WEBAUTHN_ORIGIN`。
