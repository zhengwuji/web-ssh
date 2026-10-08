# 可选的 LDAP 与 Active Directory 身份认证

LDAP 认证是可选的，默认处于禁用状态。常规的 `docker-compose.yml` 不会创建
任何 LDAP 卷、挂载或辅助工具。启用时需要配合提供的
`docker-compose.ldap.yml` 覆盖文件，并使用相同的 WebSSH 镜像；无需 `.env`
文件，也无需手动编写密钥挂载。

## 安全模型

- `LDAP_ENABLED=false` 不会注册任何 LDAP 路由、不会启动任何 LDAP 任务、不会
  读取任何 LDAP 文件，也不会建立任何目录连接。
- `ldap://` 在任何绑定之前始终执行 StartTLS。`ldaps://` 以 TLS 开始。不支持
  明文 LDAP 认证，也不支持关闭证书校验。
- 使用最小权限服务账号执行只读的用户搜索。提交的用户密码仅用于最终的绑定，
  且永远不会被存储。
- 目录用户名会按照 RFC 4515 过滤器值进行转义。搜索限定在子树范围内、最多返回
  两条结果，并且必须恰好解析为一个条目。
- 默认情况下，由管理员显式地将某个目录身份关联到现有的本地 WebSSH 用户。可选
  的自动配置仍然要求密码绑定成功，绝不单独信任用户名。
- 稳定的 `entryUUID`（OpenLDAP）或 `objectGUID`（Active Directory）是身份键。
  DN 被重命名后可以在认证成功时更新，而不会改变账号归属。
- LDAP 用户不能成为管理员，也不能回退到本地密码、通行密钥（passkey）、恢复码
  或 OIDC。请至少保留一个未关联的本地紧急管理员。
- `LDAP_AUTO_PROVISION=true` 仅在首次成功通过目录登录后创建非管理员的 LDAP
  托管账号。它要求存在一个处于活动状态的本地紧急管理员，并且绝不会把 LDAP
  附加到已存在的本地用户名上。大小写不敏感的重名、控制字符以及超过 80 个
  字符的名称会被拒绝，且不会被截断。
- 关联操作会销毁用户处于休眠状态的本地密码以及所有替代性本地登录因素。解除
  关联则要求提供一个新的本地密码。
- LDAP 会话默认每五分钟重新校验一次。功能被禁用、目录中断、用户缺失、稳定 ID
  发生变化、账号被锁定并被配置的过滤器排除，或证书失败，都会吊销用户的浏览器、
  Socket.IO、SSH、传输以及连接池访问权限。

## 需要向目录管理员获取的信息

在激活之前请收集下列值：

1. 一个主 LDAP 服务器的 DNS 名称，其 TLS 证书与该名称匹配；可选地，再提供
   一个备用服务器，其自身证书也匹配相应的 DNS 名称。
2. 是使用带 StartTLS 的 `ldap://host:389`，还是使用 `ldaps://host:636`。
3. 用户搜索基础 DN。
4. 只读绑定账号的 DN 及其密码。它只需要具备搜索所配置的基础 DN 并读取稳定 ID
   属性的权限。
5. 包含签发根证书以及所有必需中间证书的 PEM CA 证书包。
6. 一个恰好包含一个字面量 `{username}` 占位符的用户过滤器。
7. 一个稳定的唯一 ID 属性（`entryUUID` 或 `objectGUID`）。

DNS 与系统时间必须在 WebSSH 容器内正常工作。当服务器证书只包含 DNS 名称时，
请不要使用 IP 地址。

## 配置 LDAP Compose 覆盖文件

编辑 `docker-compose.ldap.yml`。选择该覆盖文件即会启用 LDAP，因此在启动 WebSSH
之前请先填写每一个空的目录设置项。可以先单独运行密钥辅助工具，而不启动 WebSSH
服务。请始终使用来自同一 WebSSH 版本的基础 Compose 文件和 LDAP Compose 文件。

### Active Directory 示例

```yaml
LDAP_ENABLED: "true"
LDAP_AUTO_PROVISION: "false"
LDAP_PROVIDER_ID: corp-ad
LDAP_URL: ldaps://dc01.ad.example.com:636
LDAP_BACKUP_URL: ldaps://dc02.ad.example.com:636
LDAP_BASE_DN: OU=People,DC=ad,DC=example,DC=com
LDAP_BIND_DN: CN=svc-webssh,OU=Service Accounts,DC=ad,DC=example,DC=com
LDAP_USER_FILTER: "(&(objectCategory=person)(objectClass=user)(sAMAccountName={username})(!(userAccountControl:1.2.840.113556.1.4.803:=2)))"
LDAP_UNIQUE_ID_ATTRIBUTE: objectGUID
```

过滤器末尾的子句用于排除已禁用的 AD 账号。如果组织有专门的 WebSSH 访问组，
请加入一条经目录方批准的 `memberOf` 子句。嵌套组语义因环境而异，必须由 AD
管理员进行验证。

`LDAP_BACKUP_URL` 是可选的，且必须指向与 `LDAP_URL` 相同的逻辑目录。只有在主
端点不可用时，WebSSH 才会尝试它。每个 URL 都是直接连接的，因此 CA 证书包必须
能够校验该端点证书中的 DNS 名称；并不要求使用轮询别名。已完成的绑定如果拒绝了
用户的密码，则该结果具有权威性，不会针对另一个端点重试。请确保两个端点上的
提供方 ID、基础 DN、绑定账号、过滤器以及稳定 ID 属性完全一致。

### 通用 OpenLDAP 示例

```yaml
LDAP_ENABLED: "true"
LDAP_AUTO_PROVISION: "false"
LDAP_PROVIDER_ID: primary-openldap
LDAP_URL: ldap://ldap.example.com:389
# LDAP_BACKUP_URL: ldap://ldap-backup.example.com:389
LDAP_BASE_DN: ou=people,dc=example,dc=com
LDAP_BIND_DN: cn=svc-webssh,ou=services,dc=example,dc=com
LDAP_USER_FILTER: "(&(objectClass=inetOrgPerson)(uid={username})(!(pwdAccountLockedTime=*)))"
LDAP_UNIQUE_ID_ATTRIBUTE: entryUUID
```

如果该操作属性不可用，请移除 `pwdAccountLockedTime` 子句，并替换为目录实际的
禁用账号规则。

## 填充可选启用的密钥卷

LDAP 覆盖文件会创建 `webssh_auth_secrets`，并以只读方式将其挂载到 WebSSH 中的
`/run/webssh-auth`。标准 Compose 部署不会声明或挂载该卷。

使用隐藏的交互式提示设置绑定密码：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm ldap-tools set-password
```

在 Linux 或 macOS 上安装并验证 CA 证书包：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm -T ldap-tools install-ca --stdin < company-ca.pem
```

PowerShell 等价命令：

```powershell
Get-Content -Raw .\company-ca.pem | docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm -T ldap-tools install-ca --stdin
```

仅检查文件是否存在；该辅助工具从不打印文件内容：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm ldap-tools status
```

该辅助工具会校验输入、限制文件大小、原子地写入，并应用私有权限。它是独立运行
的，没有网络访问权限，并且是唯一对 LDAP 卷具有写权限的 Compose 服务。只要选择
了 LDAP 覆盖文件，WebSSH 便会以只读方式挂载该卷。即使因 LDAP 配置不完整导致
Flask 应用无法启动，该辅助工具仍然可以正常工作。

## 激活并关联用户

1. 确认 `docker-compose.ldap.yml` 中的每一个空值都已配置。
2. 使用该覆盖文件启动或重建 WebSSH：
   `docker compose -f docker-compose.yml -f docker-compose.ldap.yml up -d`。
3. 使用
   `docker compose -f docker-compose.yml -f docker-compose.ldap.yml logs webssh`
   查看启动日志。如果密钥、CA、URL、过滤器或超时配置不安全，WebSSH 会特意在
   开始提供服务之前停止运行。
4. 使用本地紧急管理员登录。
5. 打开 **Admin - Settings - LDAP directory** 并运行 **Check connection**。
   浏览器只会收到 ready/unavailable、传输方式以及提供方 ID。
6. 为了显式控制账号生命周期，请保持 `LDAP_AUTO_PROVISION: "false"`。创建目标
   本地 WebSSH 用户，然后在 Users 标签页选择 **Link LDAP**，并提供目录用户名、
   管理员密码以及确切的目标 WebSSH 用户名。
7. 对于规模较大的目录，可选择设置 `LDAP_AUTO_PROVISION: "true"`，并使用该覆盖
   文件重建 WebSSH。此后经过验证的首次登录会创建一个非管理员的 LDAP 托管
   账号。已有的本地用户名仍然需要通过显式的管理员关联流程处理。
8. 注销并测试该目录账号。当 LDAP 被启用时，其 `LDAP_PROVIDER_ID` 是默认的
   **Authentication Source**；本地登录仍然可以选择。

在迁移更多用户之前，请先使用一个非管理员试点账号进行验证。

对于严格的生产配置文件，请将 LDAP 覆盖文件放在生产覆盖文件之前，以便生产设置
保持权威：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml -f docker-compose.production.yml up -d
```

## 回滚与恢复

要立即停止 LDAP，请仅使用标准 Compose 文件重建 WebSSH：

```bash
docker compose -f docker-compose.yml up -d --force-recreate
```

这会从容器中移除 LDAP 环境变量与挂载。具名密钥卷仍会被保留但处于分离状态，
直到再次选择该覆盖文件。已有的 LDAP 会话会被作废。本地账号继续正常工作，但已
关联的 LDAP 账号会刻意不恢复其旧密码。目录被移除或过滤器将其排除时，会在不删除
该账号已存储的 WebSSH 数据的情况下吊销访问权限；请仅通过正常的显式管理员生命
周期操作来删除这些数据。

要在 LDAP 正常运行期间将某个账号恢复为本地认证，请选择 **Manage LDAP**，提供
管理员密码、确切的目标用户名以及新的本地密码，然后解除关联。

要在所有身份均已解除关联且 LDAP 已禁用之后仅删除 LDAP 密钥文件：

```bash
docker compose -f docker-compose.yml -f docker-compose.ldap.yml --profile ldap-tools run --rm ldap-tools remove
```

不要删除常规的 WebSSH 数据卷。LDAP 映射存放在常规数据库中，并包含在原生备份/
恢复之中；绑定凭据与 CA 保留在独立的密钥卷中，并且刻意不包含在备份之内。

## 故障排查

- **应用拒绝启动：** 运行独立的 `status` 辅助工具，并在容器日志中查看确切的
  配置错误。
- **证书失败：** 检查 DNS、证书 SAN、系统时间、完整的 CA 链，以及 CA 是否为
  PEM 格式而非 DER 或 PKCS#12 格式。
- **零个或多个匹配：** 请与目录管理员一起测试搜索基础 DN/过滤器。WebSSH 绝不
  会从有歧义的搜索结果中挑选一个结果。
- **找到了 AD 用户但无法绑定：** 检查其是否已禁用/锁定/过期、登录限制，以及
  域控制器是否接受所提供的用户名形式。
- **LDAP 中断导致用户被注销：** 传输失败后 WebSSH 会尝试可选的备用端点。如果
  两个端点都不可用，则适用刻意的故障关闭（fail-closed）行为。请恢复目录/TLS
  服务；不要启用密码回退。
- **提供方 ID 被更改：** 请恢复原始的 `LDAP_PROVIDER_ID`。它是每个稳定映射的
  组成部分，对于该目录应始终保持不变。

## 本地测试实验室

基本功能测试不需要 Active Directory 域。`tests/integration/ldap/` 下可选启用的
实验环境会启动一个启用了 TLS 的 OpenLDAP 服务器、初始化预先配置的密钥卷、构建
WebSSH，并将其暴露在 `http://localhost:5050`。它使用仅限测试用途的密码，绝不
可作为生产基础设施进行部署。

```bash
docker compose -f tests/integration/ldap/docker-compose.yml up --build
```

该实验环境用于验证通用 LDAP 行为。在生产上线之前，`objectGUID`、AD 禁用账号
过滤器、AD 证书注册以及域控制器策略仍然需要一次针对 AD 的验收测试。
