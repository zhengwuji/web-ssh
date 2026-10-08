# WebSSH 项目历史

本回顾性文档解释了已交付的内容，以及所记录的变更为何重要。
它是根据公开发布版本、PR 描述、issue 链接和 Git 祖先关系重建的，
而非源自原始项目计划。重建日期：**2026-10-03**。

## 如何阅读证据

- **已交付：** 已发布的 tag 包含该实现的合并提交。
- **有记录的缘由：** 某个来源明确描述了该问题、根本原因或目标。
- **回顾性经验：** 面向未来规划的一种解读，而非对当时已记录决策的主张。
- 历史验证是所链接条目中报告的证据，而不是今天重新运行的测试。
  一个历史版本并不能证明每一位操作者的真实环境都能通过验收。

下文的发布日期是 GitHub 公布日期。它们不是重建后的截止日期。
回填的里程碑创建/关闭元数据必须反映实际执行的回填操作。

## 首个正式发布之前

可用的 Git 历史始于 **2026-01-23**，即
[`2fcd38a`](https://github.com/zhengwuji/web-ssh/commit/2fcd38ad12cc1cf6d36563aace320ecb8a94e040)。
初始提交提到了 `v1.0.0`，但该信息并不是已发布的 GitHub Release。
首个正式发布的版本是 **2026-07-23 的 v1.0.0**。

早期工作已经混合了安全修复、依赖更新和可用性改进：
[#5](https://github.com/zhengwuji/web-ssh/pull/5) 加固了日志、密码、配置文件和
网络控制；[#20](https://github.com/zhengwuji/web-ssh/pull/20) 处理了 SSRF、登录
计时、上传限制以及一个 Socket.IO 依赖问题；
[#36](https://github.com/zhengwuji/web-ssh/pull/36) 添加了持久化 tmux、回放和回滚缓冲。
这些属于首个正式发布版本的基线，而非虚构的 1.0 之前发布里程碑。

## 已发布的版本阶段

| 发布版本 / 公布日期 | 交付成果 | 有记录的问题或目的 | 首次在此发布的已验证合并 PR 数 |
|---|---|---:|
| [v1.0.0](https://github.com/zhengwuji/web-ssh/releases/tag/v1.0.0) / 2026-07-23 | 多用户终端/SFTP 工作区、tmux、密钥、配置文件和 Docker 部署 | 让家庭实验室和小型团队无需外部服务即可获得浏览器访问能力 | 35 |
| [v1.1.0](https://github.com/zhengwuji/web-ssh/releases/tag/v1.1.0) / 2026-08-03 | 原生线程化运行时、通行密钥/OIDC、有界操作、信任/隔离、备份/恢复和供应链门禁 | [#60](https://github.com/zhengwuji/web-ssh/pull/60)：旧的依赖/运行时组合限制了安全更新，且故障边界需要加固；[#71](https://github.com/zhengwuji/web-ssh/pull/71)：可恢复的原生管理备份/恢复 | 10 |
| [v1.2.0](https://github.com/zhengwuji/web-ssh/releases/tag/v1.2.0) / 2026-08-11 | 活动会话 Linux 遥测、SFTP、诊断、主机分组/收藏和导航 | 将服务器管理保持在一个专注的会话工作区中；[#81](https://github.com/zhengwuji/web-ssh/pull/81) 回应了导航请求 [#75](https://github.com/zhengwuji/web-ssh/issues/75)、[#76](https://github.com/zhengwuji/web-ssh/issues/76)、[#77](https://github.com/zhengwuji/web-ssh/issues/77) | 13 |
| [v1.3.0](https://github.com/zhengwuji/web-ssh/releases/tag/v1.3.0) / 2026-08-12 | 活动会话中的安全命令插入、主机排序和就地密钥替换 | 让日常管理更高效，并让已保存的连接更可预期；[#94](https://github.com/zhengwuji/web-ssh/pull/94)、[#96](https://github.com/zhengwuji/web-ssh/pull/96)、[#97](https://github.com/zhengwuji/web-ssh/pull/97)、[#98](https://github.com/zhengwuji/web-ssh/pull/98) | 6 |
| [v2.0.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.0.0) / 2026-08-21 | 响应式工作区以及安全/管理员中心；TOTP、LDAP/OIDC 和操作绑定式验证 | [#124](https://github.com/zhengwuji/web-ssh/pull/124)：受保护的变更需要与账户和敏感操作相称的验证；上下文工具必须跟随当前活动会话 | 16 |
| [v2.1.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.1.0) / 2026-08-24 | 可选启用的加密 SMB 源和跨源传输、带版本控制的 Wiki、SFTP/主题/登录修复 | [#140](https://github.com/zhengwuji/web-ssh/pull/140)：在不削弱属主关系、目标允许列表和变更边界的前提下扩展文件工作区；[#132](https://github.com/zhengwuji/web-ssh/pull/132)、[#136](https://github.com/zhengwuji/web-ssh/pull/136)：修正 2.0 之后的回归问题 | 9 |
| [v2.2.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.2.0) / 2026-08-30 | 终端优先的移动端/平板 UI、受管的 GitHub 身份验证、统一管理、MFA/文件加固 | [#163](https://github.com/zhengwuji/web-ssh/issues/163)/[#164](https://github.com/zhengwuji/web-ssh/pull/164)：Android 触摸滚动无法使用；[#154](https://github.com/zhengwuji/web-ssh/issues/154)/[#158](https://github.com/zhengwuji/web-ssh/pull/158)：整合管理工作区 | 15 |
| [v2.2.1](https://github.com/zhengwuji/web-ssh/releases/tag/v2.2.1) / 2026-08-30 | 针对常规历史滚动的聚焦修正以及直接的移动端会话工具 | [#165](https://github.com/zhengwuji/web-ssh/pull/165)：合成滚轮事件通过了单元检查，但并未触发实际的浏览器回滚 | 1 |
| [v2.3.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.3.0) / 2026-09-11 | 会话时长控制、经验证的 OIDC 关联、移动端/复制/笔记/传输修复和安全修复 | [#202](https://github.com/zhengwuji/web-ssh/pull/202)：经验证的仓库安全问题；[#208](https://github.com/zhengwuji/web-ssh/issues/208)/[#209](https://github.com/zhengwuji/web-ssh/pull/209)：在不削弱稳定的颁发者/主体绑定的前提下减少关联摩擦；[#210](https://github.com/zhengwuji/web-ssh/issues/210)/[#211](https://github.com/zhengwuji/web-ssh/pull/211)：移动端输入回归问题仍存在 | 27 |
| [v2.4.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.4.0) / 2026-09-21 | 高输出多会话渲染/恢复、终端/文件同步、加固的远程工作和原生镜像发布门禁 | [#221](https://github.com/zhengwuji/web-ssh/pull/221)：隐藏窗格渲染延迟了 ACK 并导致重连循环；[#223](https://github.com/zhengwuji/web-ssh/pull/223)-[#226](https://github.com/zhengwuji/web-ssh/pull/226)：在不破坏部署兼容性的前提下验证不可变镜像候选 | 16 |
| [v2.5.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.5.0) / 2026-10-05 | 可选网关和日常工作区连续性 | [#238](https://github.com/zhengwuji/web-ssh/pull/238)：可选的 Warpgate；#231/#233/#242：工作区和连接可用性；#234-#236/#239/#241：终端正确性；#251：后台加载；#252：依赖更新 | 17 |

这些发布阶段中的 165 个 PR 按其**首次被打 tag 收录**划分，
而不是按它们合并的周次划分。机器可读的
[发布历史](release-history.json) 列出了每个 PR 编号、tag SHA、发布 URL、
对比结果以及经验证的 issue 到实现的链接。直接提交由
Git 对比结果覆盖，尽管它们没有 PR 可挂接到原生里程碑上。

## v2.5.0 的交付与尚待完成的验收

最初的 2026-10-03 规划基线在 v2.4.0 之后包含 13 个已合并 PR。
已发布的 v2.5.0 tag 增加了 #249、#250、#251 和 #252，使该版本共有 17 个已合并 PR。
PR #253 已被 #252 取代，不计为单独合并的 PR。

[Tag CI](https://github.com/zhengwuji/web-ssh/actions/runs/37276528581) 和原生镜像发布在 `07f472691e61eab6554dd6f75cf56fb8333964ba` 上通过。
维护者在剩余部署验收被明确报告之后授权了发布。真实的 Warpgate、部署金丝雀、升级/恢复以及适用的
环境特定检查仍记录在 [#254](https://github.com/zhengwuji/web-ssh/issues/254) 中。
发布收尾并不表示这些检查已通过。

[#237](https://github.com/zhengwuji/web-ssh/issues/237) 和
[#238](https://github.com/zhengwuji/web-ssh/pull/238) 首次发布于 v2.5.0，而非 v2.4.0。
[#245](https://github.com/zhengwuji/web-ssh/issues/245) 由报告者自身的
Warpgate PROXY-protocol 配置解决；它仍是支持性证据，而非已交付的修复。
[#62](https://github.com/zhengwuji/web-ssh/issues/62) 被转为数据库提案
讨论，同样不计为已交付的实现。

## 面向未来规划的经验

以下是回顾性建议，而非虚构的历史决策：

1. **验证可观察的行为。** #165 解释了为什么发出一个事件不足以
   证明滚动可用。验收应检查用户所见的内容，当自动化浏览器覆盖无法复现其输入栈时，
   还应包括真实设备。
2. **将集成与交付分开对待。** 一个已合并的功能或已关闭的 issue 可能
   早于某个带版本号的发布。请保持独立的发布门禁并记录确切的候选版本。
3. **明确保留兼容性。** #225 在加固威胁到既有部署之后，将其移入
   一个可选启用的叠加文件。容量、身份提供方和回滚
   检查属于发布记录的一部分，而不是默认绿色 CI 已覆盖一切。
4. **让理由和推迟的工作保持可见。** #20 明确推迟了大规模的 Paramiko
   升级；#60 后来在更广泛的运行时/安全工作中包含了 Paramiko 5。请记录这类
   权衡取舍，而不是让未来的读者从提交顺序中自行推断。

## 本重建的局限性

没有可用的原始发布截止日期或完整的私有规划历史。该
表格概括的是有记录的意图，而非主张存在预先制定的策略。
Issue 时间线显示使用了 GitHub Projects，但本回顾性文档并不验证或
更改看板的完整结构/状态。清单保留了带日期的原生里程碑回填及后续发布
更新。在做出进一步的指派之前，请检查实时的 GitHub 元数据。
