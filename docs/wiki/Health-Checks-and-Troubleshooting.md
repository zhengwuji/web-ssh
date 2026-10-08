# 健康检查与故障排查

WebSSH 暴露相互独立的存活性与就绪性端点。请同时使用两者；它们回答不同的运维问题。

## 存活性：`/health`

```bash
curl -fsS http://127.0.0.1:5000/health
```

正常运行的进程会返回 HTTP 200 及：

```json
{"status":"ok"}
```

存活性并不能证明数据库、数据目录或运行时准入已就绪。监督器可用它检测已死进程，而不会仅仅因为实例有意处于维护状态就重启该实例。

## 就绪性：`/ready`

```bash
curl -fsS http://127.0.0.1:5000/ready
```

就绪性会校验：

- 维护模式未激活；
- 运行时生命周期接受新工作；
- SQLite 数据库有响应；
- 数据目录通过其读/写探测。

某一类别失败会产生 HTTP 503。请将就绪性用于反向代理或编排器的流量准入，以及优雅关闭期间。

## 容器状态

```bash
docker compose ps
docker compose logs --tail=200 webssh
```

如果服务反复重启，请检查首个启动错误，而不仅仅是最后一次健康检查失败。常见原因是无效的生产配置、密钥权限缺失/不正确、数据卷不可写，或端口冲突。

## 浏览器无法连接

请按以下顺序检查：

1. 应用主机上的 `/health` 与 `/ready`。
2. 反向代理的上游地址与端口。
3. WebSocket/Socket.IO 升级转发。
4. `CORS_ORIGINS` 中确切的公网 scheme 与 host。
5. `TRUSTED_PROXIES` 是否与真实的转发层数一致。
6. HTTPS 下的安全 cookie 行为。
7. 如果设置了 `APPLICATION_ROOT`，子文件夹前缀是否一致。

带有 `Secure` 会话 cookie 的 HTTP 页面无法维持已认证会话。不要为了掩盖损坏的生产 TLS 路径而禁用安全 cookie。

## SSH 连接被拒绝

区分以下失败情况：

- 目标策略：`BLOCK_INTERNAL_SSH` 或某个允许列表拒绝了解析出的地址。
- 容量：全局/每用户 SSH 或 socket 配额已耗尽。
- 网络：从 WebSSH 主机无法访问 DNS、路由、防火墙或 SSH 端口。
- 认证：远程用户名、密码、密钥、agent 或 Jump Host 链失败。
- 主机密钥：服务器未知并等待信任，或已固定的密钥发生了变更。

对于发生变更的主机密钥，请在撤销旧记录之前独立验证新的指纹。不要禁用校验。

## SFTP 或传输问题

批量传输使用 HTTP，因此即使终端 Socket.IO 工作正常，代理的正文大小、缓冲与超时设置也可能导致失败。此外请检查：

- 每用户与全局传输槽位；
- 临时字节配额与可用磁盘空间；
- 远程文件权限与 SFTP 子系统可用性；
- 快速连接的生命周期与远程空闲超时；
- 上传大小与编辑器内容限制。

文件工作区支持 SFTP 来源以及可选的（opt-in）SMB 来源。如果 SMB 控件被禁用，请确认 `SMB_ENABLED=true` 且非空的确切 `SMB_ALLOWED_TARGETS` 允许列表已到达容器。SMB 默认保持关闭。

对于 SMB，请从 WebSSH 容器的网络命名空间进行测试，而不仅仅是从 Docker 主机测试。配置的主机名或 IP 必须能在该处解析，并且可在 TCP 445 上访问。位于不同 Compose 项目中的服务需要共享的外部网络，或由 SMB 主机发布的 LAN 地址；WebSSH 本身不暴露 SMB 端口。

使用工作区结果来缩小故障范围：

- 连接被拒绝：验证允许列表、DNS、TCP 445、凭据、SMB 3.1.1、签名、加密与安全协商；对于 Active Directory 或 TrueNAS，可尝试 DNS 域 `example.com` 与用户名 `alice`，或保持域为空并使用诸如 `alice@example.com` 的 UPN；NetBIOS 名称可能不被接受；
- 连接已建立但列举失败：验证共享名以及 list/read ACL；
- 根目录被标记为只读：该账户可以列举根目录，但服务器拒绝了在该处创建文件和目录；
- 根访问权限未知：服务器无法就一项或多项非变更性访问检查给出确定答复；请测试预期的操作；
- 在嵌套文件夹中上传或复制失败：即使根写入权限已确认，也请检查该文件夹的 ACL、配额、可用空间以及删除/重命名权限；
- replace 不可用：授予原子重命名/删除子项权限，或另选一个新文件名；WebSSH 不会先删除旧目标。
- 编辑器报告需要手动恢复：保留被命名的临时文件与备份文件，恢复较新的已校验内容，然后才移除这些产物；
- 移动操作超时：在重试前刷新源和目标文件夹，因为服务器可能在浏览器丢失确认之后已完成重命名；
- 取消操作仍处于待处理状态：检查传输原因与服务器日志；第一个请求是幂等的，其确认具有权威性，因此重复点击既无必要也无用处。

对于服务器端 SMB 连接失败，对话框会包含诸如 `SMB-A1B2C3D4E5F6` 的参考号。请在 `DATA_DIR/logs/app.log` 或结构化容器日志中搜索该确切参考号。匹配的记录包含稳定的结果码以及已脱敏的诊断字段：

- `target_resolution`：允许列表、DNS 或解析后目标处理；
- `transport_negotiate`：TCP 445 或 SMB 协商；
- `security_requirements`：SMB 3.1.1、签名、加密或安全协商；
- `session_authentication`：域、用户名、密码或账户状态；
- `share_access`：共享名、可用性或根 ACL；
- `lifecycle`：配额预留、发布、关闭或清理处理。

`cause_type` 仅标识异常类，`nt_status`（在存在时）是定宽的 SMB 状态码。WebSSH 有意不返回或记录后端异常消息，因为它可能包含凭据、服务器名或共享路径。支持报告应包含参考号、结果码、阶段、原因类型、NT 状态、WebSSH 版本或 commit、SMB 服务器产品与版本以及复现步骤，但绝不包含 SMB 密码。

传输队列显示服务器返回的稳定原因。仅有的通用失败表示未分类的后端问题，应与已脱敏的服务器日志字段 `operation`、`result_code` 和 `exception_type` 关联起来。

## LDAP/AD 登录失败

请查看专门的 [LDAP 故障排查流程](LDAP-and-Active-Directory#troubleshooting)。最重要的区分是：服务 bind/search 失败、用户未匹配过滤器、TLS 校验失败、用户凭据 bind 失败，还是没有已启用的本地账户与最终得到的目录身份相关联。

LDAP 自动预置（auto-provisioning）是可选的，且默认通过 `LDAP_AUTO_PROVISION=false` 禁用。当被显式启用时，WebSSH 只会在成功完成目录 bind 后创建一个非管理员账户。已存在的本地用户名绝不会被自动占用，含糊或冲突的身份会按失败关闭（fail closed）处理，并且运维人员应保留一个经过测试的本地应急（break-glass）管理员。

## OIDC 登录失败

请校验签发方发现、确切的 redirect URI、client secret 文件权限、state/nonce 生命周期、系统时钟以及任何允许的 subject/域策略。电子邮件匹配不能替代确切的 issuer 加 subject 身份关联。对于 MFA 或管理员提权失败，还请校验已签名的 `acr`/`amr` 声明、配置的保障映射，以及提供方对请求的 `prompt=login`、`max_age=0` 与 `acr_values` 参数的支持。

## 容量症状

工作缓慢或被拒绝可能源于线程、socket、SSH、传输、临时字节或后台 worker 准入。请将实时诊断与各项相关限制进行比较。至少保留四个 HTTP 线程，且不要将 socket 提高到可用 Gunicorn 容量之上。

## 安全取证信息收集

在请求帮助时，请包含：

- 确切的 WebSSH 版本或 commit；
- 部署配置档（profile）与已脱敏的生效 Compose 配置；
- `/health` 与 `/ready` 状态；
- 相关日志时间戳、诊断参考号、阶段与错误类；
- 反向代理产品与 URL 路径；
- 目标是本地、私有、公网、LDAP、OIDC 还是 Tailscale；
- 复现步骤。

请移除密码、cookie、令牌、私钥、恢复码、bind 凭据以及敏感的主机名/IP 地址。疑似漏洞请按 `SECURITY.md` 中所述以私密方式上报。
