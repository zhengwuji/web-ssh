# 一次性 LDAP 集成实验环境

本实验环境仅用于本地集成测试。它使用公开的测试密码、临时 CA 与固定版本的 OpenLDAP
测试镜像。切勿把它部署为真实的身份基础设施。

```bash
docker compose -f tests/integration/ldap/docker-compose.yml up --build
```

打开 `http://localhost:5050`，创建第一个本地管理员，再创建一个名为 `alice` 的非管理员
本地用户，并为该账号选择 **Link LDAP**。

- 目录用户名：`alice`
- 用于登录的目录密码：`alice-password`
- 绑定账号与 CA 会被自动安装到测试密钥卷中。

只清理本一次性实验环境的数据卷：

```bash
docker compose -f tests/integration/ldap/docker-compose.yml down -v
```
