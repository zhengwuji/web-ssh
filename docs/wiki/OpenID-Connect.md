# OpenID Connect

WebSSH 提供可选的、带 PKCE 的 OIDC 授权码认证。它
默认禁用，并且绝不会自动配给 WebSSH 账户。

## 身份模型

已登录的用户或管理员将精确的提供方身份关联到
既有的本地账户：

```text
(normalized issuer, subject) -> WebSSH user
```

邮箱地址和用户名不是身份键。可选的 subject 和邮箱
域允许列表是额外的策略检查。

OIDC 身份无法关联到由 LDAP 管理或由 GitHub 配给的
账户。

## 提供方要求

- OIDC 发现（discovery）和授权码流程。
- 精确的 HTTPS issuer。
- 已注册的 WebSSH 客户端 ID。
- 客户端密钥存储在一个私有的只读文件中。
- 以 `/oidc/callback` 结尾的精确回调 URL。
- 声明中包含稳定的 `sub` 以及预期的 issuer。

回环 HTTP 回调仅在家庭实验室配置中被接受。对于
真实部署请使用 HTTPS。

## 配置

```bash
OIDC_ENABLED=true
OIDC_ISSUER=https://idp.example.com
OIDC_CLIENT_ID=webssh
OIDC_CLIENT_SECRET_FILE=/run/secrets/webssh_oidc_client_secret
OIDC_REDIRECT_URI=https://ssh.example.com/oidc/callback
OIDC_ALLOWED_SUBJECTS=
OIDC_ALLOWED_DOMAINS=example.com
OIDC_LOGIN_RATE_LIMIT=10 per minute
OIDC_MFA_AMR_VALUES=
OIDC_MFA_ACR_VALUES=
OIDC_PHISHING_RESISTANT_AMR_VALUES=
OIDC_PHISHING_RESISTANT_ACR_VALUES=
OIDC_STEP_UP_ACR_VALUES=
STEP_UP_MAX_AGE_SECONDS=300
```

| 变量 | 用途 |
|---|---|
| `OIDC_ENABLED` | 注册并暴露 OIDC 集成 |
| `OIDC_ISSUER` | 精确的提供方 issuer URL |
| `OIDC_CLIENT_ID` | 已注册的客户端 ID |
| `OIDC_CLIENT_SECRET_FILE` | 私有密钥文件的绝对路径 |
| `OIDC_REDIRECT_URI` | 精确的已注册回调 |
| `OIDC_ALLOWED_SUBJECTS` | 可选的、以逗号分隔的 subject 允许列表 |
| `OIDC_ALLOWED_DOMAINS` | 可选的邮箱域策略 |
| `OIDC_LOGIN_RATE_LIMIT` | 按 IP 的启动与回调限制 |
| `OIDC_MFA_AMR_VALUES` | 被视为 MFA 的精确已签名 `amr` 取值 |
| `OIDC_MFA_ACR_VALUES` | 被视为 MFA 的精确已签名 `acr` 取值 |
| `OIDC_PHISHING_RESISTANT_AMR_VALUES` | 被视为抗钓鱼的精确已签名 `amr` 取值 |
| `OIDC_PHISHING_RESISTANT_ACR_VALUES` | 被视为抗钓鱼的精确已签名 `acr` 取值 |
| `OIDC_STEP_UP_ACR_VALUES` | 为管理员 Step-up 请求的、提供方特定的保证等级 |
| `STEP_UP_MAX_AGE_SECONDS` | 可被复用的近期强认证的时效（60-900 秒） |

不要将客户端密钥直接放入 `.env` 或 Compose 环境变量。请以只读方式
挂载该文件，并将其限制给服务账户。

部署配置本身并不会激活登录按钮。在
成功重启并通过就绪检查之后，请在 **Admin → Settings
→ Authentication features** 下激活 OIDC。如果 `OIDC_ENABLED` 为 false，或提供方启动
校验失败，该开关会被锁定；选择它也无法从浏览器启动或修复
OIDC。

## 保证等级与 MFA 声明

`acr` 和 `amr` 取值是提供方特定的。WebSSH 绝不猜测其
含义。它只会归一化有界的已签名令牌声明，并将其与上文
运维人员配置的精确集合进行比较：

- 匹配 `OIDC_PHISHING_RESISTANT_*` 会产生抗钓鱼保证等级；
- 否则匹配 `OIDC_MFA_*` 会产生 MFA 保证等级；
- 缺失、格式错误、相互冲突或未映射的证据仍保持为基础等级。

请只依据该精确提供方/app 策略的文档以及实际观测到的已签名令牌来
配置取值。基础 OIDC 登录无法绕过已在关联的 WebSSH 账户上启用的 MFA；
WebSSH 会继续使用可用的本地 Passkey、
TOTP 或恢复码第二因素。

### 在移动设备上推送

WebSSH 不发送推送通知。当 OIDC 提供方的
认证策略调用其自身的移动应用，并返回运维人员已映射的、已签名 `acr` 或
`amr` 取值时，推送才会生效。这通常需要提供方侧的 MFA
或条件访问策略、应用注册以及一个允许的回调。在信任该映射之前，
请分别测试一次成功的推送和一次仅密码登录。

## OIDC 管理员 Step-up

对于敏感的管理操作，WebSSH 可以使用
`prompt=login`、`max_age=0` 以及 `OIDC_STEP_UP_ACR_VALUES` 打开提供方重新认证。该回调必须：

- 属于当前已认证的管理员；
- 返回相同的已关联 issuer 和 subject；
- 包含当前的 `auth_time`；
- 满足所请求的精确已签名保证等级；
- 成功消费一次性 state。

只有在这之后，WebSSH 才会创建一份绑定到精确
管理操作和精确目标的一次性五分钟授权。弹出窗口不会在其 URL 中返回授权；
打开方只轮询一次，并在受保护的请求中直接发送该授权。

## 协议防护

WebSSH 为每次登录创建随机 state、nonce、PKCE verifier 和浏览器
会话绑定。state 记录存储在服务端，仅被消费一次，
并在身份被接受之前即被删除。回调会验证 state 绑定、
过期时间、令牌声明、nonce、issuer、subject 策略、域策略、账户关联
以及账户状态。

提供方故障会返回通用的不可用响应，不会暴露令牌
或密钥细节。

## 关联身份

推荐路径不需要复制提供方 subject：

1. 启用并激活 OIDC。
2. 使用既有的登录方法登录目标 WebSSH 账户。
3. 打开 **Settings → Security methods → Identity provider**。
4. 选择 **Connect identity provider** 并完成操作绑定的 WebSSH
   确认。
5. 登录所配置的提供方。

该回调绑定到同一个浏览器会话和本地账户。WebSSH 仅在
state、nonce、PKCE、允许列表和域检查全部成功之后，
才存储提供方验证过的 issuer 和 subject。它绝不会搜索匹配的
用户名或邮箱地址。重复该流程可以将来自
同一提供方的另一个身份附加到该账户。

### 管理员回退方案

1. 启用 OIDC 并重启 WebSSH。
2. 以本地管理员身份登录。
3. 创建或选择目标本地账户。
4. 在管理面板中，选择 OIDC 关联操作。
5. 提供精确的提供方 subject。
6. 完成管理员可用的 Step-up 方法。
7. 确认精确的目标用户名。
8. 注销并使用该目标身份测试 OIDC 登录。

手动输入适用于恢复场景，或目标用户无法
完成自助关联流程的提供方。请从受信任的提供方
文档或运维工具中获取精确的 subject；邮箱地址或显示名称不能
替代它。该映射是唯一的，因此一个提供方身份不能附加到
多个用户。

对于其 subject 取决于提供方用户名
和 OIDC 客户端 ID 的提供方（例如 Tinyauth），请优先使用自助关联流程。它会直接捕获已签名的
subject，并避免依赖特定版本的 subject 重建。

## 解除身份关联

管理员必须完成操作绑定的 Step-up，并确认精确的
目标用户名。
解除关联只会移除该映射；底层的本地账户仍然保留。

在解除用户唯一实用登录方法的关联之前，请先验证本地
密码、passkey 或恢复路径。

## 允许列表

### Subject 允许列表

`OIDC_ALLOWED_SUBJECTS` 限制可接受的稳定 subject。当
提供方拥有一组可管理的固定用户时，它最为有效。

### 邮箱域策略

`OIDC_ALLOWED_DOMAINS` 要求匹配的邮箱声明和域。它仅是一个
准入条件。关联和登录仍然通过 issuer
和 subject 来解析身份。

## 失败行为

| 症状 | 检查项 |
|---|---|
| OIDC 按钮缺失 | `OIDC_ENABLED` 和启动日志 |
| 管理面板开关被禁用 | 部署标志或提供方就绪状态失败；修复 Compose/密钥/发现配置并重建容器 |
| 提供方不可用 | discovery URL、DNS、TLS、密钥文件、出站 |
| 回调被拒绝 | 精确回调、state cookie、代理源、系统时间 |
| 身份未关联 | 本地登录并使用 **Settings → Security methods → Identity provider**，或核对针对精确 issuer 和 subject 的管理员映射 |
| 域被拒绝 | 邮箱声明与 `OIDC_ALLOWED_DOMAINS` |
| 关联后用户被拒绝 | 账户处于已锁定、由 LDAP 管理或由 GitHub 配给的状态 |

运维审计事件会区分映射缺失（`unlinked`）、目标被锁定
（`account_locked`）以及不兼容的外部管理目标
（`externally_managed`）。浏览器响应保持通用，以免泄露
账户状态。

## 恢复

请保留一个本地应急管理员。如果提供方发生故障，本地账户
会继续使用其已配置的因素。OIDC 不会引入自动
账户创建或权限映射。

在管理面板中禁用 OIDC 会阻止后续的 OIDC 启动，但不会强行
终止既有的浏览器或 SSH 会话。既有工作会达到其正常的
配置生命周期。显式的账户锁定、删除和 MFA 重置仍会
撤销目标账户。

## 升级兼容性

自助关联不需要任何新的环境变量或提供方
注册。这次增量式数据库迁移只为短时效的 OIDC state 表
添加了可空的账户和会话绑定。既有用户、OIDC
身份映射、待处理的登录或 Step-up state，以及管理员关联与
解除关联流程都保持兼容。
