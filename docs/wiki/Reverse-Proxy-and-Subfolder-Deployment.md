# 反向代理与子目录部署

WebSSH 使用常规 HTTP 路由以及 Socket.IO/WebSocket 流量。反向代理必须保留
公开源（origin）并支持连接升级。

## 必需的应用程序设置

对于单个受信任代理层：

```bash
CORS_ORIGINS=https://ssh.example.com
SESSION_COOKIE_SECURE=true
TRUSTED_PROXIES=1
```

`TRUSTED_PROXIES` 是受信任转发层的数量，而不是布尔值。
请确保 WebSSH 后端只能通过这些层访问。

## 位于域名根路径的 Nginx

```nginx
location / {
    proxy_pass http://webssh:5000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## 位于域名根路径的 Traefik

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.webssh.rule=Host(`ssh.example.com`)"
  - "traefik.http.routers.webssh.tls.certresolver=letsencrypt"
  - "traefik.http.services.webssh.loadbalancer.server.port=5000"
```

## 位于域名根路径的 Caddy

```caddyfile
ssh.example.com {
    reverse_proxy webssh:5000
}
```

## 位于域名根路径的 Apache

Apache httpd 2.4.47 或更高版本可以通过 `mod_proxy_http` 代理 HTTP 和 WebSocket
升级。启用 `mod_proxy`、`mod_proxy_http`、`mod_headers` 和 `mod_ssl`，
然后使用如下 TLS 虚拟主机：

```apache
<VirtualHost *:443>
    ServerName ssh.example.com

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/ssh.example.com/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/ssh.example.com/privkey.pem

    ProxyPreserveHost On
    RequestHeader set X-Forwarded-Proto "https"
    ProxyPass "/" "http://127.0.0.1:5000/" upgrade=websocket
    ProxyPassReverse "/" "http://127.0.0.1:5000/"
</VirtualHost>
```

较旧的 Apache 版本需要 `mod_proxy_wstunnel` 以及一条显式的 WebSocket 规则。
请优先使用受支持的 2.4.47+ 版本，以便 HTTP 与升级流量共用同一映射。

## 在路径前缀下提供 WebSSH

对于诸如 `https://server.example.com/webssh` 这样的公开 URL，请配置：

```bash
APPLICATION_ROOT=/webssh
TRUSTED_PROXIES=1
CORS_ORIGINS=https://server.example.com
SESSION_COOKIE_SECURE=true
```

反向代理必须在转发请求之前剥离 `/webssh`，并将原始前缀通过
`X-Forwarded-Prefix` 发送。

### Nginx 子目录

```nginx
location /webssh/ {
    proxy_pass http://webssh:5000/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Prefix /webssh;
}
```

`location` 和 `proxy_pass` 中的结尾斜杠都是有意的。

### Traefik 子目录

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.webssh.rule=Host(`server.example.com`) && PathPrefix(`/webssh`)"
  - "traefik.http.middlewares.webssh-strip.stripprefix.prefixes=/webssh"
  - "traefik.http.middlewares.webssh-prefix.headers.customrequestheaders.X-Forwarded-Prefix=/webssh"
  - "traefik.http.routers.webssh.middlewares=webssh-strip,webssh-prefix"
  - "traefik.http.services.webssh.loadbalancer.server.port=5000"
```

### Caddy 子目录

```caddyfile
server.example.com {
    handle_path /webssh/* {
        reverse_proxy webssh:5000 {
            header_up X-Forwarded-Prefix /webssh
        }
    }
}
```

### Apache 子目录

除上述模块外，还需启用 `mod_alias`。重定向缺失的结尾斜杠，
并显式转发公开前缀：

```apache
RedirectMatch permanent "^/webssh$" "/webssh/"

<Location "/webssh/">
    RequestHeader set X-Forwarded-Prefix "/webssh"
</Location>

ProxyPass "/webssh/" "http://127.0.0.1:5000/" upgrade=websocket
ProxyPassReverse "/webssh/" "http://127.0.0.1:5000/"
```

请同时在两条代理路径上保留结尾斜杠。并按上文所示在 WebSSH 中设置
`APPLICATION_ROOT=/webssh`。

## 容器化代理

当代理运行在 Docker 中时：

1. 将 WebSSH 和代理接入同一个私有共享网络。
2. 移除 WebSSH 的公开端口发布。
3. 通过私有网络代理到 `webssh:5000`。
4. 将 `TRUSTED_PROXIES` 设为受信任层的真实数量。

不要在启用 HTTPS 代理的同时并行发布 `5000:5000`。那会让客户端绕过 TLS，
并可能绕过受信任代理边界。

## WebSocket 症状

如果登录正常但终端活动断开或始终无法启动：

- 确认上游连接使用 HTTP/1.1；
- 确认已转发 `Upgrade` 和 `Connection`；
- 检查浏览器对 `/socket.io/` 的网络请求；
- 检查代理超时是否足以容纳长连接；
- 验证该前缀在 HTTP 和 Socket.IO 上被一致地应用；
- 验证 `CORS_ORIGINS` 与浏览器可见的源完全匹配，包括
  协议方案和非默认端口。

## 受信任的客户端地址

WebSSH 仅在配置的代理信任深度内使用转发地址。
取值不正确时，要么记录代理地址而非客户端地址，要么
信任攻击者提供的转发头。请优先采用简单拓扑，并保持
后端网络私有。

## 验证

```bash
curl -I https://ssh.example.com/
curl -fsS https://ssh.example.com/health
curl -fsS https://ssh.example.com/ready
```

对于子目录：

```bash
curl -I https://server.example.com/webssh/
curl -fsS https://server.example.com/webssh/health
curl -fsS https://server.example.com/webssh/ready
```

在浏览器中完成检查：登录、打开终端、调整其大小，
并传输一个小文件。
