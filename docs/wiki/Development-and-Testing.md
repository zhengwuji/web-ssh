# 开发与测试

WebSSH 支持 Python 3.11 及更新版本。生产容器当前使用 Python 3.14。前端为原生 JavaScript 与 CSS，依赖库在本地 vendored。

## 开发环境搭建

在 Windows PowerShell 上：

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --require-hashes -r requirements-test.txt
$env:SECRET_KEY = '<strong local development secret>'
.\.venv\Scripts\python.exe start.py
```

在类 Unix 系统上，请使用相应的 `.venv/bin/python` 解释器与环境变量语法。

不要在开发与测试中复用生产环境的 `DATA_DIR`、凭据或密钥。

## 依赖管理

直接的 Python 依赖位于 `requirements.in`；经哈希锁定的运行时与测试文件由以下命令生成：

```powershell
.\scripts\lock_requirements.ps1
```

在不修改锁文件的情况下校验它们：

```powershell
.\scripts\lock_requirements.ps1 -Check
```

不要手工编辑生成的锁文件。依赖变更必须更新输入文件、两个锁输出（如适用）以及相关的兼容性测试。

## Python 测试

使用以下命令运行测试套件：

```powershell
.\.venv\Scripts\python.exe -m pytest tests --ignore=tests/integration -q -n 2 --dist=loadscope
```

pytest 测试装置使用降低后的 bcrypt 工作因子，以保持认证密集型测试的速度。一个隔离的子进程契约会验证正常应用进程仍保留 bcrypt 的生产工作因子。受维护的门禁在 Python 3.14 上执行完整单元测试套件，并在 Python 3.11 上执行具有代表性的兼容性套件。另有独立任务检验 Redis 7/8 速率限制以及一次性 OpenSSH 与加密 SMB 服务器。针对性测试在开发期间很有用，但它们不能替代发布前相关的完整门禁。

## 前端依赖

固定版本的浏览器库在 `package.json` 中声明，并通过 vendor 工作流复制到仓库中。当前契约包括 xterm.js、fit/search 插件、Socket.IO client、highlight.js 与 Material Icons。

```bash
npm ci
npm run vendor
npm run vendor:check
```

不要添加运行时 CDN 脚本、字体或样式。应用必须保持离线可用，并满足 CSP 与 vendor 完整性测试。
主题背景原图归档在服务树之外的
`assets/theme-backgrounds/`，因此随附的 `static/` 树只包含
派生出的 WebP 文件。请保留这些 PNG 源文件以供将来重新生成：
`arctic-frost.png`、`carbon-glass.png`、`matrix-signal.png`、
`navy-topography.png`、`neon-circuit.png`、`noir-architecture.png`、
`obsidian-glass.png`、`paper-blueprint.png`、`retro-amber.png` 以及
`rose-brushed-metal.png`。

## JavaScript 与 E2E 测试

```bash
npm run lint:js
npm run test:js
npm run test:e2e
```

`test:e2e` 始终运行完整套件。CI 使用两台相互隔离的服务器，各一个
worker，并按记录的执行时长分配测试：

```bash
npm run test:e2e:ci -- --shard=1/2
npm run test:e2e:ci -- --shard=2/2
```

运行器在分区之前先发现当前的测试套件。每个被发现的
测试恰好属于一个分片；新测试会获得一个回退权重。测试
身份基于文件与完整标题，因此移动源码行不会改变
分配。共享的账户与会话 fixture 要求每台服务器一个 worker；
在不隔离该状态的情况下增加 worker 可能使结果失效。

CI 会从每个分片上传 `test-results/e2e-timing-*.json`，包括失败的运行。
请从一次具有代表性的成功运行下载报告到 `test-results/`，并使用以下命令
刷新已检入的时长基线：

```bash
npm run test:e2e:timings:refresh
# Or pass the downloaded report paths explicitly:
npm run test:e2e:timings:refresh -- path/to/shard-1.json path/to/shard-2.json
```

请结合套件变更一起审查基线差异。刷新时不要混用来自
不同修订版本的报告。时长权重只影响调度；
它们不决定哪些测试会运行。

成功截图与动画帧是可选启用的（opt-in）：

```bash
npm run test:captures
```

这会为捕获套件设置 `WEBSSH_CAPTURE_ASSETS=1`。它们的功能、
可访问性与几何断言也会在常规 CI 中运行。失败截图
与 trace 无需该标志也仍然可用。README 或
产品站点使用的捕获会更新其在 `assets/` 之下声明的文件；额外的 QA 捕获
会写入被忽略的 `.test-run.tmp/captures/` 目录。

当前端默认状态发生变化时，必须更新 Playwright 假设。
请同时测试新的默认值以及用户的显式覆盖。

## 容器与运行时门禁

相关的发布验证包括：

- 容器构建与启动；
- Gunicorn `gthread`、恰好一个 worker 以及线程/socket 预留；
- `/health` 与 `/ready` 行为；
- 优雅关闭与传输清理；
- AMD64 与 ARM64 镜像；
- SPDX SBOM 与 provenance；
- 针对可修复 High/Critical 发现项的 Trivy 结果；
- 针对 Python、JavaScript/TypeScript 与 Actions 的 CodeQL。

务必将 CI 证据与正在审查的确切 commit 关联起来。来自较旧 SHA 的绿色运行并不是较新变更的证据。

## 不可变镜像发布

Main 推送与版本标签会以确切的源码 SHA 调用一次完整的 `Tests` 工作流。
`Tests` 没有单独的 main 推送触发器。PR 仍测试其
自身的合并修订版本，手动指定确切 SHA 的运行仍然可用，
包括 Dependabot vendor 刷新工作流。每个必需的任务都必须成功完成；
缺失、跳过、取消或失败的任务会阻止发布。

同时，独立的原生 AMD64 与 ARM64 任务在 `ubuntu-24.04` 与 `ubuntu-24.04-arm` 上构建仅含 digest 的
候选镜像。它们保留软件包刷新、
SBOM 与 provenance，验证源码与平台身份，扫描确切运行时
digest 以查找可修复的 High/Critical 发现项，并运行兼容性以及可选启用的
加固启动、备份/恢复与关闭检查。PR 镜像扫描同样使用
原生 runner。被取代的 PR 扫描会被取消；发布运行保持独立。

每个平台仅在其扫描与运行时
检查通过后才上传其候选身份。该交接绑定到仓库、源码 SHA 与工作流运行。
重试失败的任务可以复用同一次运行较早尝试中成功的平台；
成功重建的平台会替换其自身的交接。不同的
运行、修订版本、将来的尝试以及不匹配的 registry 证据都会被拒绝。

发布任务会等待两个平台任务与完整测试门禁。它会
重新检查不可变候选镜像，并在运行特定的 `candidate-*` 标签下
组装其完整的 manifest 描述符，包括 attestation。
只有经过校验的组合索引才会被复制到既有的分支/版本标签
（`main`、`latest`，或版本号与 major.minor 系列）。每个目标标签
都必须解析到该原始索引 digest。提升（promotion）过程绝不重新构建镜像。

成功的平台交接会保留 14 天。按平台的扫描证据
以及成功的 `image-release.json` 会保留 90 天；发布
记录包含受测的修订版本、索引 digest、平台 digest 与已验证的
标签。交接过期后的重试需要重新进行平台构建。

Registry 标签写入不是事务性的：registry/网络故障可能留下
部分标签已更新，因此失败的提升需要将所有标签与
候选 digest 对照检查后再重试。发布者任务被串行化，最多有 100 个
待处理任务排队。队列到达顺序遵循校验完成顺序，因此 main 推送
在提升之前也会立即重新检查当前的远程 main SHA。
被取代的 main 候选会失败而不更新发布标签；版本标签
发布仍可独立于当前的 main SHA 而符合条件。

PR 还会针对一个一次性的、仅回环的本地
registry 演练提升辅助程序，使用带有 attestation 载荷的微小合成平台镜像：

```bash
python scripts/check_release_promotion.py
```

这需要 Docker 与 Buildx。它会验证原生候选组装、
每个目标标签处的整索引保留，以及对不同
源码 SHA 的拒绝。它会创建一个具有唯一名称的 registry 容器，并在校验其所有权标签后
仅移除该容器及其匿名卷。该
契约不能替代真实的候选扫描或应用运行时检查。

### 测试选择与必需检查

受保护的 PR 检查是 `all-tests` 与 `security-scan / image-security`。
它们始终会报告结果。前者要求完整的测试任务集，
包括 SMB 与发布契约；后者要求两个原生镜像
扫描。缺失、失败或取消的任务会阻止其聚合结果。较旧的
成功运行无法满足较新的修订版本。

| 变更或触发器 | 测试 | 容器扫描与发布 |
|---|---|---|
| 代码、测试、依赖、工作流或混合 PR | 完整的 Python 3.14 套件；Python 3.11 兼容性；Redis 7/8；OpenSSH；SMB；JavaScript、vendor 与 lint 检查；两个浏览器分片；运行时与发布契约 | 原生 AMD64 与 ARM64 扫描；不发布 |
| 仅文档 PR | 确切修订版本分类、文档契约以及两个必需的聚合结果 | 有意跳过两个镜像扫描；不发布 |
| Main 推送或版本标签 | 完整地调用一次可复用的 Tests 工作流 | 原生候选镜像与测试并行构建；仅在所有门禁通过后发布 |
| 手动指定确切 SHA 的测试运行 | 完整测试，无论变更路径如何 | Tests 工作流不发布 |
| 计划或手动的 Container Security 运行 | 独立的镜像校验 | 两个原生架构扫描；不发布 |

`scripts/ci_change_scope.py` 持有文档允许列表：`README.md`、
`docs/` 之下的 Markdown 文件，以及 `docs/media/` 之下的文档媒体。
`static/` 之下的运行时资产、测试、脚本、工作流、锁文件与未知
路径始终会选择完整路径。分类器检查确切的检出、
将 PR 基线与被测的合并修订版本进行比较，并包含被删除的路径
以及重命名两侧的路径。它读取完整的 Git diff，不受 API 文件数量
限制。缺失的历史、空 diff 或不确定的 Docker 排除项会选择
完整校验。工作流摘要会记录该决定及其原因。

现有的文档契约通过
`python -m unittest discover -s tests -p test_documentation_surface.py -v` 在初始测试任务中运行。
这 33 项检查涵盖 Wiki 链接、页面覆盖、README 结构、文档
媒体、LDAP 与 Command Set 说明、运行时版本一致性以及
生产 Compose 命令，且无需安装应用依赖。
请将所有读取 README 或允许的文档路径的测试保留在此模块中，
包括将文档与运行时或工作流文件进行比较的契约。完整 pytest 会排除该模块
以避免重复运行。

同一初始任务会针对完整的受跟踪树运行 `python scripts/check_repository_hygiene.py`。
这会阻止本地 agent 指令、内部审查
产物、瞬时开发输出、工作站特定的 AI 工具路径以及
`assets/` 之下未被引用的文件，包括那些在忽略规则下仍被强制添加的文件。请在打开或更新 pull request 之前在本地运行它。

只有成功的 `docs` 分类才允许跳过所指定的昂贵任务。
意外的结果、缺失的任务或缺失的范围都会使
聚合失败。工作流级别的路径过滤器被有意避免，以便必需的
检查不会仅仅因为文档发生变更而一直处于待处理状态。

Main 与标签推送始终运行完整的发布流水线，包括文档合并。
因此每个已发布的镜像都归属于其经过完整测试的源码修订版本。
这也在文档合并于较早的代码发布期间到达时保留了当前的 main 提升防护。
Pages、Wiki 发布与 CodeQL 保留其自身的触发器，不使用 PR 文档快捷路径。

在新增测试任务时，请将其加入 `all-tests.needs` 以及
`scripts/check_release_gates.py` 中相应的必需集合。保持选择条件
同步，并同时测试完整模式与文档模式。不要通过接受任意被跳过的任务
或移除必需检查来解决失败的聚合结果。

## 存储与并发规则

在更改 JSON 持久化时：

- 为完整的加载-修改-保存序列持有 `storage_lock`；
- 使用 `atomic_write_json`；
- 为便于诊断而保留损坏数据，而不是覆盖它；
- 让 schema 迁移保持增量式并做好备份。

在更改 SSH/SFTP 或传输时：

- 保留用户所有权检查；
- 使用既有的 Paramiko 通道辅助函数；
- 保持超时、取消与配额准入；
- 确保快速连接的生命周期长于排队中/活动中的传输引用；
- 测试优雅关闭与断开竞态。

## 贡献

保持变更聚焦，并与相邻模块的风格和错误契约保持一致。功能提案请提交到 GitHub Discussions。安全漏洞必须遵循 `SECURITY.md` 中的私密流程，而不是公开 issue。

在提交变更之前，请运行与其实际影响范围相关的检查，并记录任何无法执行的门禁。
