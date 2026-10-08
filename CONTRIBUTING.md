# 为 WebSSH 贡献代码

感谢你有兴趣参与贡献！本项目欢迎各种形式的贡献：缺陷报告、功能建议、文档改进与代码提交。

## 快速链接

- [报告缺陷](https://github.com/zhengwuji/web-ssh/issues/new?template=bug_report.md)
- [提出功能建议](https://github.com/zhengwuji/web-ssh/issues/new?template=feature_request.md)
- [安全问题](SECURITY.md)——请不要为漏洞提交公开 Issue
- [路线图](ROADMAP.md) 与[规划流程](docs/project-planning.md)

## 开始之前

### 环境要求

- Python 3.11 或更高版本
- Docker（可选，用于测试）

### 本地开发环境搭建

```bash
# 克隆仓库
git clone https://github.com/zhengwuji/web-ssh.git
cd web-ssh

# 创建虚拟环境
python -m venv venv
source venv/bin/activate  # Linux/macOS
# 或：venv\Scripts\activate  # Windows

# 安装依赖
pip install -r requirements.txt

# 设置必需的环境变量
export SECRET_KEY=$(openssl rand -hex 32)
export DEBUG=True

# 启动应用
python start.py
```

打开 http://localhost:5000 并创建一个测试账号。

### 项目结构

```
web-ssh/
├── app/                    # Flask 应用（按域划分的模块）
│   ├── __init__.py        # 应用工厂、路由、安全响应头
│   ├── auth.py            # 认证与限流
│   ├── models.py          # SQLAlchemy 数据模型
│   ├── socket_events.py   # WebSocket 事件处理器
│   ├── ssh_manager.py     # SSH 连接管理
│   ├── sftp_handler.py    # SFTP 文件操作
│   ├── connection_pool.py # SSH 连接池
│   ├── key_manager.py     # SSH 密钥存储
│   ├── key_encryption.py  # SSH 密钥静态加密
│   ├── profile_manager.py # 连接配置档案
│   ├── command_manager.py # 命令库
│   ├── binary_transfer.py # 二进制文件传输协议
│   ├── user_settings.py   # 用户偏好设置
│   ├── audit_logger.py    # 安全审计日志
│   └── decorators.py      # 共享装饰器
├── static/
│   ├── css/               # 样式表
│   └── js/                # 前端 JavaScript 模块
├── templates/             # Jinja2 模板
├── config.py              # 集中式配置
├── start.py               # 入口文件
├── requirements.txt       # Python 依赖
└── install.sh             # 一键安装脚本
```

## 如何贡献

### 报告缺陷

提交 Issue 之前：

1. 确认该问题是否已被报告
2. 先尝试最新版本
3. 收集相关信息（浏览器、操作系统、错误信息、日志）

缺陷报告中请包含：

- 你期望发生什么
- 实际发生了什么
- 复现步骤
- 环境信息（浏览器、操作系统，以及适用时的 Docker 版本）

### 提出功能建议

欢迎提出功能建议！请包含：

- 对该功能的清晰描述
- 使用场景——它为什么有用？
- 可能的实现思路（可选）

### Pull Request

#### 动手之前

1. **先查已有 Issue/PR**——可能已经有人在处理
2. **较大的改动先开 Issue**——我们先讨论方案
3. **小而聚焦的 PR 更好**——更容易评审与合并

对于较大的改动，请在关联的 Issue 或提案中说明用户问题、预期结果与验收标准。
在 PR 中说明所选方案的理由、验证方式、兼容性与安全影响，以及剩余的发布前检查项。
维护者会把已接受的改动归入某个发布里程碑；合并本身并不会发布版本。
轻量协作流程见[规划与发布流程](docs/project-planning.md)。

#### 开发流程

1. Fork 本仓库
2. 从 `main` 创建功能分支
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. 修改代码
4. 在本地测试你的改动
5. 使用清晰的提交信息提交
6. 推送到你的 Fork
7. 发起 Pull Request

#### 代码风格

**Python：**

- 遵循 PEP 8
- 使用有意义的变量名
- 函数保持聚焦且简短
- 精简代码：不写多余注释，只在逻辑不直观处写文档字符串

**JavaScript：**

- 只使用原生 JavaScript（不使用框架——这是有意的架构决定）
- 统一缩进（4 个空格）
- 优先使用 `const` 而非 `let`，避免 `var`

**通用：**

- 不要有行尾空格
- 文件以换行符结尾
- 尽量把单行控制在 100 字符以内

#### 提交信息

请写出清晰的提交信息：

```
Add SFTP directory creation support

- Implement mkdir operation in sftp_handler.py
- Add socket event handler for create_directory
- Update file manager UI with create folder button

Fixes #42
```

格式：

- 第一行：简要说明（祈使语气，不超过 50 字符）
- 空行
- 正文：解释改了什么以及为什么（每行不超过 72 字符）
- 如适用，引用对应 Issue

#### 安全注意事项

本项目会处理 SSH 凭据。贡献代码时请：

- 绝不记录密码或私钥
- 校验并清洗所有用户输入
- 操作前检查会话归属
- 使用参数化查询（SQLAlchemy 已处理）
- 用完即从内存中清除敏感数据
- 文件操作时考虑路径穿越

如果你的改动涉及认证、加密或会话处理，请在 PR 中注明，以便额外评审。

#### 公开仓库卫生

提交到这里的内容都会被公开。请不要提交本地开发说明、工具配置、私人笔记、
开发过程截图、临时测试输出、工作站路径、凭据或未被引用的媒体文件。
可复用的产品与运维文档请放在公开文档区域。

提交前请运行与 CI 相同的仓库守卫：

```bash
python scripts/check_repository_hygiene.py
```

该守卫直接检查已跟踪文件，因此强制添加被忽略的文件也无法绕过。
新增被禁止的路径、内部指令标记、工作站专用工具路径，或 `assets/` 下未被引用的文件，
都会导致必需的 `dispatch-integrity` 检查失败。

#### 测试你的改动

提交之前：

1. **手工测试**——确认改动按预期工作
2. **测试边界情况**——空输入、特殊字符、大文件
3. **检查不同浏览器**——至少覆盖 Chrome、Firefox、Safari
4. **用 Docker 测试**——确保容器化部署可用
   ```bash
   docker build -t webssh:test .
   docker run -p 5000:5000 -e SECRET_KEY=$(openssl rand -hex 32) -e CORS_ORIGINS=http://localhost:5000 webssh:test
   ```

### 文档

文档改进永远欢迎：

- 修正笔误或表述不清之处
- 补充示例
- 改进 README
- 增加代码内的行内注释

## 目前最需要什么

以下方向尤其欢迎贡献：

- [ ] 自动化测试（pytest、Playwright）
- [ ] 国际化（新增语言翻译）
- [ ] 无障碍改进
- [ ] 性能优化
- [ ] 更多主题
- [ ] 文档

## 行为准则

请保持尊重与建设性。我们都在为做出有用的东西而努力。

- 对新人友好
- 坦然接受建设性批评
- 以项目整体利益为先
- 对他人保持同理心

## 有问题？

请通过仓库的 Issue 跟踪器联系我们：https://github.com/zhengwuji/web-ssh/issues

## 许可证

参与贡献即表示你同意以 MIT 许可证授权你的贡献。
