# GitHub 认证

WebSSH 可以使用 GitHub App 作为可选的登录提供方。该集成
仅验证身份：它不会浏览仓库、执行 Git 操作、
读取 issue、使用 Actions、同步 SSH 密钥，也不会保留 GitHub 访问令牌。

GitHub 认证完全在运行时通过 **Settings →
Administration → Authentication → GitHub authentication** 配置。无需添加
任何 `GITHUB_*` 环境变量、Compose 叠加文件、Docker 密钥或额外
挂载。在管理员保存一份完整配置并启用该提供方之前，
现有部署保持不变。

## 创建 GitHub App

### 1. 确定该 app 的归属者

当要通过组织成员允许列表来控制 WebSSH 访问时，
请使用由组织拥有的 GitHub App。对于私有测试或不涉及组织策略的
仅身份登录，个人 app 就足够了。

默认情况下，只有组织所有者才能创建并安装由组织拥有的 app。
被指定的 GitHub App manager 可以创建和编辑 app，但仅凭该
角色并不授予安装它的权限。

### 2. 打开 GitHub App 注册页面

对于个人 app：

1. 在 GitHub 中，选择右上角的头像。
2. 打开 **Settings**。
3. 在左侧边栏中，打开 **Developer settings**。
4. 打开 **GitHub Apps**。
5. 选择 **New GitHub App**。

个人注册的直达 URL 为
<https://github.com/settings/apps/new>。

对于由组织拥有的 app：

1. 在 GitHub 中，选择头像并打开 **Your organizations**。
2. 在拥有该 app 的组织旁边，选择 **Settings**。
3. 在左侧边栏中，打开 **Developer settings**。
4. 打开 **GitHub Apps**。
5. 选择 **New GitHub App**。

组织注册 URL 的形式为
`https://github.com/organizations/ORGANIZATION/settings/apps/new`。

### 3. 填写 Basic information

在 GitHub 的注册表单上使用以下取值：

| GitHub 字段 | WebSSH 对应的取值 |
|---|---|
| **GitHub App name** | 一个唯一的描述性名称，例如 `WebSSH – Example Org` |
| **Homepage URL** | 公开的 WebSSH 基础 URL，例如 `https://ssh.example.com/` |
| **Callback URL** | 精确的 WebSSH 回调地址，例如 `https://ssh.example.com/auth/github/callback` |
| **Request user authorization (OAuth) during installation** | 保持未勾选；WebSSH 会在用户登录或关联账户时启动授权流程 |
| **Setup URL** | 留空 |
| **Webhook → Active** | 清除该选项；WebSSH 不接收 webhook |

避免使用通配符回调匹配。WebSSH 始终发送所配置的精确
回调 URL。当 WebSSH 运行在 `APPLICATION_ROOT` 之下时，请在 GitHub 和管理面板中
都在 `/auth/github/callback` 之前包含该前缀。生产环境的
回调必须使用 HTTPS；明文 HTTP 仅在家庭实验室配置中
用于回环主机时被接受。

### 4. 选择最小权限

将每一项 **Repository permission** 和 **Account permission** 都保持为 **No
access**。WebSSH 不读取仓库、邮箱地址、SSH 密钥、issue、
Actions 或其他账户数据。

对于组织允许列表为空的仅身份登录，也请将每一项
**Organization permission** 保持为 **No access**。

当 **Allowed organizations** 将包含一个或多个组织登录名时：

1. 在 GitHub App 注册表单上，找到 **Permissions & events**。
2. 在 **Organization permissions** 下，找到 **Members**。
3. 选择 **Read-only**。GitHub 将这一实际生效的权限描述为
   **Members: read**。
4. 将其他所有权限保持为 **No access**。

这是 GitHub 的组织成员关系端点用来证明私有成员身份
以及公开成员身份所需的权限。已登录用户还必须
是所允许组织中的活跃成员。

### 5. 创建并安装该 app

1. 在 **Where can this GitHub App be installed?** 下，对于私有的、限定在所有者范围内的部署，
   优先选择 **Only on this account**。仅当该 app 必须安装在拥有它的账户之外时，
   才选择更宽泛的选项。
2. 选择 **Create GitHub App**。
3. 在新 app 的设置页面上，打开 **Install App**。
4. 在应使用其资源和成员策略的个人账户或组织旁边，
   选择 **Install**。
5. 检查确认该安装不请求任何仓库访问权限，并且在使用
   组织允许列表时，仅请求对成员的只读访问权限。

GitHub 区分安装与用户授权。安装会根据该 app 声明的
权限，授予它访问所选账户或组织的权限。每个 WebSSH 用户会在登录或
关联账户时单独授权该 app。组织所有者必须批准一项
请求组织权限的安装。

### 6. 复制 Client ID 并创建客户端密钥

返回 **Developer settings → GitHub Apps**，在该 app 旁边选择 **Edit**。
在其 **General** 页面上：

1. 复制 **Client ID**。不要复制 **App ID**；它们是不同的值。
2. 滚动到 **Client secrets**。
3. 选择 **Generate a new client secret**。
4. 立即复制生成的密钥并粘贴到 WebSSH 中。请将其视为
   密码，绝不要放入 Compose、源代码管理、截图或
   issue 文本中。

WebSSH does not need（不需要）私有密钥、PEM 下载、webhook 密钥或 OAuth App
客户端凭据。它只需要 GitHub App 的 **Client ID** 和一个生成的
**Client secret**。

## 配置 WebSSH

保留一个经过测试的本地应急管理员，然后在管理面板中
打开 GitHub 部分。输入：

- GitHub App 客户端 ID
- 客户端密钥
- 精确的公开 HTTPS 回调 URL
- 可选的、以逗号分隔的组织允许列表
- 是否允许自动配给未知的 GitHub 身份

然后选择 **Enable GitHub sign-in** 和 **Save GitHub configuration**。WebSSH
会针对这一受保护变更请求管理员重新认证。按钮旁边的
状态必须报告 **GitHub sign-in is active**，用户才会
看到 GitHub 登录选项。

客户端密钥字段是只写的。将其留空会保留现有
密钥；输入某个值则会替换它。WebSSH 使用由既有持久化 `SECRET_KEY`
派生的、按域分隔的密钥对其静态加密。
因此备份仍然敏感，受支持的密钥轮换命令
也会重新加密已存储的 GitHub 密钥。

保存配置需要管理员 Step-up。提供方变更会
使未完成的 GitHub OAuth state 失效。不完整或无法解密的
配置会使 GitHub 失败即关闭，同时本地 WebSSH 登录仍然
可用。

## 登录与账户绑定

GitHub OAuth 使用授权码流程、PKCE S256、随机的、绑定会话的
一次性 state、五分钟的服务端 state 记录、精确的回调，
以及有界的本地续接。WebSSH 使用不可变的数字 GitHub 用户
ID 作为身份键；登录名、显示名称和邮箱绝不是持久键。

GitHub 授权仅被接受用于主登录和账户关联。
它无法满足 passkey 登记、恢复码
变更、提供方配置、恢复或其他敏感账户操作所要求的新鲜 Step-up，
因为该回调不会向 WebSSH 提供已签名的近期认证
证据。对于这些 Step-up 检查，请使用本地密码、既有 passkey、TOTP 或符合条件的
恢复方法。下文所述范围极窄的初始因素
引导，是 WebSSH 自身从 GitHub 自动配给的、尚无任何因素的账户的唯一例外。

现有用户在完成一次 WebSSH
Step-up 检查和一次成功的 GitHub 授权之后，从其安全设置中连接 GitHub。一个 GitHub 身份
只能关联到一个 WebSSH 账户，且每个 WebSSH 账户只能有一个
GitHub 身份。更改 GitHub 用户名不会破坏该绑定。

断开连接也需要 Step-up。由 GitHub 配给的账户必须首先
添加并测试一个 Passkey，这样移除 GitHub 就不会移除其唯一可用的
主认证方法。

## 自动配给

自动配给默认禁用。禁用时，未知的 GitHub
身份会被拒绝，且不会按用户名或邮箱进行匹配。启用时，
WebSSH 会原子性地创建一个新的非管理员账户及其身份绑定。
GitHub 元数据绝不能创建或提升管理员。

### 引导第一个独立因素

自动配给的账户没有已知的本地密码。在该用户可以
断开 GitHub 之前，受信任的主机运维人员必须通过一个短时效、一次性代码，
授权登记第一个 Passkey（或 TOTP 认证器）。例如：

```bash
docker compose exec webssh /app/entrypoint.sh flask --app start:app \
  issue-factor-bootstrap --username ACCOUNT --action passkey.enroll
```

请在验证所请求的 WebSSH
账户之后，仅在受信任的主机上运行此命令。该命令会拒绝本地、已锁定、已启用 MFA 或已具备因素的
账户。它会打印一个随机代码，该代码在十分钟后过期，并绑定
到精确的账户、当前认证代数和登记
操作。签发新代码会使该账户此前的所有代码失效；
代码本身绝不会被写入数据库或审计日志。

随后用户使用 GitHub 登录，打开 **Security**，启动对应的
Passkey 或认证器登记，并在提示时输入运维人员签发的代码。
WebSSH 会在签发正常的、绑定会话的
一次性登记授权之前消费该代码。用户应在
断开 GitHub 之前登记并测试一个 Passkey，因为仅靠 TOTP 无法替代主登录。

## 组织策略

在允许列表为空时，WebSSH 不执行任何组织检查。在配置了一个
或多个组织时，临时用户访问令牌必须证明在
至少一个条目中是活跃成员。非成员会被拒绝。超时、
权限失败、格式错误的响应以及 GitHub API 中断都会失败即关闭。

用户访问令牌的存在时间仅够用于获取 `/user`，以及在
已配置时获取成员关系。WebSSH 绝不持久化访问令牌、刷新令牌、
授权码或 OAuth 响应，也绝不将其写入审计日志。

## 故障排查

- **登录按钮缺失：** 该提供方被禁用，或所需配置
  不完整。请查看管理保存按钮旁边的状态。
- **登录无效或已过期：** 重新启动该流程。OAuth state 被有意设计为
  一次性、绑定浏览器、绑定配置代数和短时效。
- **组织被拒绝：** 确认精确的组织名称、活跃
  成员关系、**Members: read** 权限、在该组织上已批准的安装，
  以及对任何已变更权限的批准。
- **回调被 GitHub 拒绝：** 使 GitHub App 回调与管理
  面板回调完全一致，包括协议方案、主机、端口和应用根路径。
- **Client ID 被拒绝：** 从该 app 的 General 页面复制 **Client ID**，而不是
  **App ID**、OAuth App 凭据或安装 ID。
- **客户端密钥被拒绝：** 在 GitHub App 的 General 页面的 **Client secrets** 下
  生成一个新值。不要使用 webhook 密钥或私有密钥。
- **私有组织成员身份始终不被接受：** 将该 app 安装到该
  组织上，授予 **Organization permissions → Members → Read-only**，并
  由组织所有者批准该权限或安装请求。
- **提供方不可用：** 使用本地应急管理员，并检查
  到 `github.com` 和 `api.github.com` 的出站 HTTPS 连通性。

## GitHub 参考资料

- [注册 GitHub App](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app)
- [关于用户授权回调 URL](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/about-the-user-authorization-callback-url)
- [为 GitHub App 选择权限](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app)
- [安装 GitHub App](https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party)
- [组织成员 API 权限](https://docs.github.com/en/rest/orgs/members)
