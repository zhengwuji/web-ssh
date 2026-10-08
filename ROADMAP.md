# WebSSH 路线图

WebSSH 是一个可私有部署的 SSH 与文件工作区。本路线图说明项目方向、当前发布重点以及已完成工作
的依据。它不是发布日期承诺，也不替代 Issue、Pull Request 与发布说明。

发布状态更新于 **2026-10-05**，v2.5.0 对应
[`07f4726`](https://github.com/zhengwuji/web-ssh/commit/07f472691e61eab6554dd6f75cf56fb8333964ba)。
更新的状态请查看关联的 GitHub 条目。

## 产品方向

- 让终端、文件、命令、诊断与笔记始终与当前活动服务器对齐。
- 保持显式的认证、归属、主机信任、网络策略与资源边界。
- 让同一套工作区在移动设备与多窗格桌面上同样好用。
- 让部署、升级、恢复与容器发布都可验证且可私有部署。

这些主题是对现有产品与已发布历史的概括，不构成新的功能承诺。

## 当前：v2.5.0 已发布，部署验收仍需显式完成

[v2.5.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.5.0) 交付了可选的 Warpgate 支持、
工作区连续性、主机/命令/移动端易用性、tmux 目录同步、粘贴与会话记录修复、更快的主题背景，
以及经过评审的依赖更新。[版本对比](https://github.com/zhengwuji/web-ssh/compare/v2.4.0...v2.5.0)
包含 17 个已合并的 PR。

[标签 CI 与原生镜像发布](https://github.com/zhengwuji/web-ssh/actions/runs/37276528581) 已
在 `07f472691e61eab6554dd6f75cf56fb8333964ba` 上通过。两种运行时架构都保留了 SBOM 与来源证明。
发布记录为 [#248](https://github.com/zhengwuji/web-ssh/issues/248)，
[v2.5.0 里程碑](https://github.com/zhengwuji/web-ssh/milestone/11) 已关闭。

发布是在「真实 Warpgate 环境、部署金丝雀、升级/恢复/回滚以及适用的环境专项验收尚未验证」
的情况下被授权的。这些检查在 [#254](https://github.com/zhengwuji/web-ssh/issues/254) 中仍然开放，
不计入已通过项。Warpgate 仍默认关闭。未承诺任何新的功能版本或日期。

## 下一步：从已验证的反馈中选择

请从可复现的缺陷、用户反馈与经过验证的安全/依赖发现中挑选一个小范围。在把实质性工作
分配到下一个里程碑之前，请先在 Issue 中说明收益、优先理由与验收标准。

此处不承诺额外的功能版本、日期或大型架构迁移。紧急安全修复可以走单独的补丁路径，
而不必等待功能版本；私下上报漏洞请遵循 [SECURITY.md](SECURITY.md)。

## 更远期：提案不等于承诺

在范围与约束经过评审之前，探索性的集成与架构提案请留在
[Discussions](https://github.com/zhengwuji/web-ssh/discussions)。例如
[#62](https://github.com/zhengwuji/web-ssh/issues/62) 中的 PostgreSQL 提案已被转为讨论；
其关闭并不能作为支持 PostgreSQL 的依据。仅更换外部数据库并不能解决进程内的 SSH 状态问题，
也无法让多 worker/高可用部署变得受支持。不要通过在本文件中列出某个想法，就把它提升为已承诺的版本。

## 已完成的方向

| 阶段 | 交付重点 |
| ---- | -------- |
| [v1.0.0](https://github.com/zhengwuji/web-ssh/releases/tag/v1.0.0) | 首个正式版本：终端/SFTP、tmux、多用户与 Docker 基线 |
| [v1.1.0](https://github.com/zhengwuji/web-ssh/releases/tag/v1.1.0) | 线程化运行时、现代身份、隔离、备份/恢复与供应链门禁 |
| [v1.2.0](https://github.com/zhengwuji/web-ssh/releases/tag/v1.2.0) - [v1.3.0](https://github.com/zhengwuji/web-ssh/releases/tag/v1.3.0) | 活动会话诊断、导航、命令、主机组织与密钥维护 |
| [v2.0.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.0.0) | 认证保证等级与自适应上下文工作区 |
| [v2.1.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.1.0) | 可选启用的加密 SMB，以及重设计后的工作流修复 |
| [v2.2.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.2.0) - [v2.2.1](https://github.com/zhengwuji/web-ssh/releases/tag/v2.2.1) | 终端优先的移动端、GitHub 认证与聚焦的触控滚动修正 |
| [v2.3.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.3.0) | 移动端/输入、账号关联、笔记/传输与已验证的安全修复 |
| [v2.4.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.4.0) | 自适应的多会话高输出恢复、目录同步与经过验证的镜像晋升 |
| [v2.5.0](https://github.com/zhengwuji/web-ssh/releases/tag/v2.5.0) | 可选 Warpgate、工作区连续性、主机/命令/移动端易用性、终端正确性与更快的背景 |

## 维护方式

- [项目历史](docs/project-history.md)：交付了什么、记录在案的原因与经验教训。
- [规划与发布流程](docs/project-planning.md)：Issue、PR 与里程碑如何协同。
- [里程碑](https://github.com/zhengwuji/web-ssh/milestones)：原生发布分组，已有十一个发布里程碑关闭。
- [回溯映射](docs/release-history.json)：版本/PR/Issue 归属、里程碑编号与回填校验。

原生里程碑回填于 2026-10-04 执行：185 个条目已分配并校验。PR #98 不可访问（HTTP 404），
已在清单中记录为例外。2026-10-05 的发布更新把 PR #249-#252 归入 v2.5.0，关闭了发布就绪
Issue #248，并把运维验收的后续工作保留在 #254。

历史映射重建于 2026-10-03。它并不意味着这些里程碑或本路线图在当时就已存在。
GitHub 上里程碑的实际创建与关闭日期必须保持不变；原始发布日期已记录为证据。
本路线图不会替换或重整现有的 GitHub Projects。
