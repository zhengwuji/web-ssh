# LDAP and Active Directory

LDAP 认证是可选的，默认禁用。标准 Compose
部署不会创建任何 LDAP 卷、挂载、辅助工具、路由或后台任务。
请通过 `docker-compose.ldap.yml` 选择启用。

## 安全模型

- `ldap://` 在任何绑定之前始终先用 StartTLS 升级。
- `ldaps://` 立即启动 TLS。
- 不支持明文 LDAP 认证以及禁用证书验证。
- 一个最小权限的服务账户执行只读用户搜索。
- 提交的用户密码仅用于最终的用户绑定，绝不
  被存储。
- 用户名会按 RFC 4515 过滤器值进行转义。
- 搜索以子树为范围，限制为两条结果，并且必须解析为
  恰好一条条目。
- 在安全的默认值 `LDAP_AUTO_PROVISION=false` 下，由管理员将一个
  稳定的目录身份关联到某个既有的 WebSSH 账户。显式选择启用则可以在
  目录认证成功之后创建非管理员（non-admin）账户；
  仅凭用户名信任绝不充分。
- 已关联的 LDAP 用户不能成为管理员，也不能回退到本地
  密码或 OIDC。在近期完成目录验证之后，他们可以登记本地
  Passkey 或 TOTP 第二因素，并获得第二因素恢复码。
- LDAP 会话会被周期性重新验证，并失败即关闭（fail closed）。

请至少保留一个未关联的本地应急管理员。

## 所需的目录信息

请从目录管理员处收集以下取值：

1. 一个由服务器证书覆盖的 LDAP 服务器 DNS 名称。
2. `ldap://host:389` 并强制使用 StartTLS（mandatory StartTLS），或 `ldaps://host:636`。
3. 用户搜索基准 DN。
4. 一个只读绑定 DN 和密码。
5. 一个 PEM CA 捆绑包，包含 WebSSH 所需的签发链。
6. 一个用户过滤器，包含恰好一个字面量 `{username}` 占位符。
7. 一个稳定的唯一 ID 属性：通常 OpenLDAP 用 `entryUUID`，
   Active Directory 用 `objectGUID`。
8. 该目录真实的已禁用或已锁定账户规则。

DNS 和系统时间必须在 WebSSH 容器内正常工作。当证书仅包含
DNS 名称时，不要使用 IP 地址。

例如，使用 `ldap://ldap.example.com:389` 并强制使用 StartTLS（mandatory StartTLS），
或使用 `ldaps://ldap.example.com:636` 以便从连接开始就使用 TLS。

## 配置 Compose 叠加文件

编辑 `docker-compose.ldap.yml` 并填写每一个空的目录取值。请使用来自
同一 WebSSH 发行版或提交的基础文件与 LDAP 文件。

### Active Directory 示例

```yaml
services:
  webssh:
    environment:
      LDAP_ENABLED: "true"
      LDAP_PROVIDER_ID: corp-ad
      LDAP_URL: ldaps://dc01.ad.example.com:636
      LDAP_BACKUP_URL: ldaps://dc02.ad.example.com:636
      LDAP_BASE_DN: OU=People,DC=ad,DC=example,DC=com
      LDAP_BIND_DN: CN=svc-webssh,OU=Service Accounts,DC=ad,DC=example,DC=com
      LDAP_USER_FILTER: "(&(objectCategory=person)(objectClass=user)(sAMAccountName={username})(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
      LDAP_UNIQUE_ID_ATTRIBUTE: objectGUID
```

最后一个过滤器子句用于排除已禁用的 AD 账户。如果访问被限制
在某个组，请使用经目录管理员批准的 `memberOf` 规则。嵌套组语义
会有所不同，必须由 AD 管理员验证。

`LDAP_BACKUP_URL` 是可选的，并且必须指向同一逻辑目录的
另一台服务器。它仅在主端点不可用之后才会被尝试。
WebSSH 会直接连接到每个 URL，因此每个端点 DNS 名称都必须与
其自身的 TLS 证书匹配，并受 `LDAP_CA_FILE` 信任；不需要
轮询（round-robin）别名。无效的用户凭据不会针对备份端点重试。

### OpenLDAP 示例

```yaml
services:
  webssh:
    environment:
      LDAP_ENABLED: "true"
      LDAP_PROVIDER_ID: primary-openldap
      LDAP_URL: ldap://ldap.example.com:389
      # LDAP_BACKUP_URL: ldap://ldap-backup.example.com:389
      LDAP_BASE_DN: ou=people,dc=example,dc=com
      LDAP_BIND_DN: cn=svc-webssh,ou=services,dc=example,dc=com
      LDAP_USER_FILTER: "(&(objectClass=inetOrgPerson)(uid={username})(!(pwdAccountLockedTime=*)))"
      LDAP_UNIQUE_ID_ATTRIBUTE: entryUUID
```

如果该操作性属性不可用，请移除或替换 `pwdAccountLockedTime` 子句。

## 配置参考

| 变量 | 默认值 | 要求 |
|---|---:|---|
| `LDAP_ENABLED` | `false` | 启用该子系统 |
| `LDAP_PROVIDER_ID` | `default` | 稳定的 1-64 字符本地提供方标识符 |
| `LDAP_URL` | 空 | 精确的 `ldap://` 或 `ldaps://` 服务器 URL |
| `LDAP_BACKUP_URL` | 空 | 同一目录的可选第二个 URL，在传输失败后尝试 |
| `LDAP_BASE_DN` | 空 | 用户子树基准 |
| `LDAP_BIND_DN` | 空 | 最小权限搜索账户 DN |
| `LDAP_BIND_PASSWORD_FILE` | `/run/webssh-auth/ldap_bind_password` | 私有文件绝对路径 |
| `LDAP_CA_FILE` | `/run/webssh-auth/ldap_ca.pem` | PEM CA 捆绑包绝对路径 |
| `LDAP_USER_FILTER` | 空 | 恰好一个 `{username}` 占位符 |
| `LDAP_UNIQUE_ID_ATTRIBUTE` | 空 | LDAP 属性名或数字 OID |
| `LDAP_CONNECT_TIMEOUT` | `5` | 1-15 秒 |
| `LDAP_OPERATION_TIMEOUT` | `5` | 1-30 秒 |
| `LDAP_SESSION_REVALIDATION_SECONDS` | `300` | 60-3600 秒 |
| `LDAP_LOGIN_RATE_LIMIT` | `5 per minute` | 按 IP 的登录与诊断限制 |

当 LDAP 被禁用时，WebSSH 不会读取这些密钥文件。

`LDAP_ENABLED=true` 只是部署的上限。在容器以有效的目录配置
启动之后，请使用本地应急管理员登录，并在 **Admin → Settings → Authentication
features** 下激活 LDAP。如果 Compose 中 LDAP 保持禁用，管理面板的开关会被锁定，
无法在运行时创建提供方。

## 填充密钥卷

该叠加文件会创建 `webssh_auth_secrets`。WebSSH 将其以只读方式挂载到
`/run/webssh-auth`。辅助服务是唯一具有写访问权限的 Compose 服务；
它没有网络，除该卷之外以只读方式运行，丢弃所有
能力（capabilities），并使用 `no-new-privileges`。

通过隐藏的交互式提示设置绑定密码：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm ldap-tools set-password
```

在 Linux 或 macOS 上安装并校验 CA 捆绑包：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm -T ldap-tools install-ca --stdin < company-ca.pem
```

PowerShell：

```powershell
Get-Content -Raw .\company-ca.pem | docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm -T ldap-tools install-ca --stdin
```

仅检查文件是否存在；内容绝不会被打印：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm ldap-tools status
```

该辅助工具会校验输入、限制文件大小、以原子方式写入，并应用
私有权限。当不完整的 LDAP 配置导致 Flask 应用无法启动时，
它仍然可用。

## 激活 LDAP

1. 确认每一个空的叠加文件取值都已填写。
2. 填充绑定密码和 CA。
3. 检查实际生效的配置：

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.ldap.yml config
   ```

4. 启动或重建 WebSSH：

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.ldap.yml up -d
   ```

5. 查看启动日志：

   ```bash
   docker compose -f docker-compose.yml -f docker-compose.ldap.yml logs webssh
   ```

不安全的 URL、密钥、CA、过滤器、属性和超时设置会阻止启动。
在就绪状态检查成功之后，请在管理面板中激活 LDAP。在部署许可、就绪状态和管理面板激活
三者同时为真之前，登录表单不会出现。

对于生产环境，请最后应用生产叠加文件：

```bash
export WEBSSH_ORIGIN=https://ssh.example.com
docker compose -f docker-compose.yml -f docker-compose.ldap.yml -f docker-compose.production.yml up -d
```

## 关联用户

使用 `LDAP_AUTO_PROVISION=false` 时（推荐用于受控推行）：

1. 使用本地应急管理员登录。
2. 打开 **Admin → Settings → LDAP directory**。
3. 运行 **Check connection**。浏览器只会收到就绪类别、
   传输方式和提供方 ID，绝不会收到密钥。
4. 如果目标标准 WebSSH 账户不存在，则创建它。
5. 在 Users 标签页上，选择 **Link LDAP**。
6. 完成管理员 Step-up 提示，然后输入目录用户名
   和精确的目标 WebSSH 用户名。
7. 注销并测试 **Sign in with LDAP**。

请先从一个非管理员试点开始。

对于较大的目录，`LDAP_AUTO_PROVISION=true` 仅在首次成功的目录密码
绑定之后，才创建一个非管理员（non-admin）的、由 LDAP 管理的 WebSSH 账户。自动配给
never claims an existing local username（绝不会占用既有的本地用户名），绝不会
创建管理员，会拒绝无效或过长的名称而不会静默
截断它们，并且在目录账户后来消失时不会自动删除已存储的数据。

关联会存储稳定的提供方与 subject，以及当前的 DN 和目录
用户名。只要稳定 ID 仍然匹配，重命名后的 DN 就可以在认证成功之后
被更新。

关联会销毁该账户休眠的本地密码，并移除
不兼容的 OIDC 映射。既有的本地 MFA 因素仍归属同一个
WebSSH 账户，并可以保护 LDAP 主登录。关联操作会撤销
目标账户的活跃访问，以便新的身份边界在其
下次登录时生效。

## 搭配可选 MFA 的 LDAP

LDAP 只证明主凭据。如果该 WebSSH 账户尚未启用
MFA，成功的目录验证会像以前一样完成登录。如果用户
已启用 MFA，WebSSH 会创建一个短时效的待处理事务，并给出
该账户当前活跃的 Passkey、TOTP 和恢复方法。LDAP 密码在绑定后
即被丢弃，绝不会为第二步而存储。

由 LDAP 管理的用户可以在近期成功完成目录登录后，在 **Security** 上登记
Passkey 或认证器应用。此后恢复码可以恢复
第二因素，但仅在 LDAP 主验证成功之后。

## 会话重新验证

每个已关联账户都会按配置的间隔被重新验证。在以下情况下，WebSSH 会撤销
浏览器、Socket.IO、SSH、传输和池化连接的访问：

- LDAP 被禁用；
- 目录不可用；
- 证书验证失败；
- 用户消失；
- 稳定 ID 发生变化；
- 账户不再匹配该过滤器；
- 映射缺失或不再具备资格。

因此，LDAP 中断会按设计将用户登出。

## 禁用 LDAP

在重建 WebSSH 时只省略 `docker-compose.ldap.yml`。对于家庭实验室
部署，请使用基础文件：

```bash
docker compose -f docker-compose.yml up -d --force-recreate
```

对于生产部署，请保留生产叠加文件：

```bash
docker compose -f docker-compose.yml -f docker-compose.production.yml up -d --force-recreate
```

这会在不丢弃生产安全配置的前提下移除 LDAP 环境变量与挂载。
具名密钥卷保持分离状态，新的 LDAP 登录
停止，且已关联用户不会重新获得旧密码。容器重建会关闭
打开的 WebSSH 和 SSH 会话，因此请将该变更安排为维护操作。

## 将某个用户恢复为本地认证

在 LDAP 正常工作期间，选择 **Manage LDAP**，完成管理员 Step-up，
提供精确的目标用户名和一个新的本地密码，然后解除
该身份的关联。新密码会建立一个全新的本地凭据。

## 移除 LDAP 密钥

在所有身份都已解除关联且 LDAP 已禁用之后：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm ldap-tools remove
```

不要删除正常的 WebSSH 数据卷。LDAP 映射存放在 SQLite 中，
并受原生备份/恢复覆盖。绑定密码和 CA 保留在
独立的卷中，并被有意排除在外。

## 故障排查

### 应用程序拒绝启动

运行独立的 `status` 辅助工具，然后在 WebSSH 日志中
读取精确的配置错误。

### 证书失败

验证 DNS、证书 SAN、系统时间、完整签发链和 PEM
编码。DER 和 PKCS#12 文件不是用于该设置的 CA 捆绑包。

### 搜索结果为零或多条

与目录管理员一起测试搜索基准和过滤器。WebSSH 绝不会
从有歧义的结果中挑选一条条目。

### 找到了 AD 用户但绑定失败

检查已禁用、已锁定、已过期和登录受限状态，以及域
控制器所接受的用户名流程。

### LDAP 中断会将用户登出

恢复目录和 TLS 服务。周期性的目录重新验证
被有意设计为失败即关闭，并在目录无法验证时撤销受影响的
由 LDAP 管理的账户。不要添加密码回退。

### 提供方 ID 被更改

恢复原始的 `LDAP_PROVIDER_ID`。它是每个映射的一部分，并且必须
在该目录集成存续期间保持稳定。

## 一次性 OpenLDAP 实验室

该集成实验室在没有 AD 域的情况下验证通用 LDAP 行为：

```bash
docker compose -f tests/integration/ldap/docker-compose.yml up --build
```

它在 `http://localhost:5050` 上暴露 WebSSH，并使用仅用于测试的密码。
绝不要将其部署为生产基础设施。

该实验室不能替代针对 `objectGUID`、
已禁用账户过滤器、证书登记或域控制器策略的 AD 专项验收测试。
