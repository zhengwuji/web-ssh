# 一次性 Warpgate 参考测试

请在一个专用的本地 Warpgate 0.29.0 实例与一个 OpenSSH 目标上，串行运行
`tests/integration/test_warpgate.py`。该夹具必须只监听回环地址，并且只包含合成账号。
切勿把这些测试指向任何现有网关：它们会修改夹具用户的 SSH 凭据策略与目标的审批要求，
并在结束后把两者恢复。主机密钥测试只会临时移除并恢复那个一次性目标的受信任密钥。

无需改动应用的 Compose 配置。测试前置条件：

- Warpgate 0.29.0，并已校验其发布二进制的校验和。
- 一个运行在非特权回环端口上的本地 OpenSSH 守护进程，具备一次性主机密钥、
  写入临时 authorized-keys 文件的网关公钥、启用 PTY/exec 与 SFTP，并允许两个会话通道。
- 一个具有合成密码与已知 TOTP 密钥的 Warpgate 用户；一个授予该用户访问 SSH 目标的角色；
  该目标的主机密钥已在该一次性网关中审阅并信任。
- 仅用于测试的 Warpgate 管理员令牌、其精确的 TLS 证书，以及固定的公网网关 SSH 主机密钥。
  本测试套件不使用任何「信任全部」的主机密钥策略。

创建一个被忽略的 JSON 夹具描述文件（例如放在 `.test-tmp/` 下）：

```json
{
  "disposable": true,
  "host": "127.0.0.1",
  "port": 12222,
  "sftp_only_port": 12224,
  "selector": "probe:probe",
  "password": "<synthetic password>",
  "api_url": "https://127.0.0.1:18443/@warpgate/admin/api",
  "certificate": "<absolute path to the disposable TLS certificate>",
  "admin_token": "<disposable admin token>",
  "user_id": "<fixture user UUID>",
  "target_id": "<fixture target UUID>",
  "otp_secret_hex": "<hexadecimal bytes of the fixture TOTP secret>",
  "host_key_type": "ssh-ed25519",
  "host_key": "<base64 public gateway host key>"
}
```

对于可选的「仅 SFTP」场景，请在 `sftp_only_port` 上再运行一个回环 OpenSSH 守护进程，
使用同一份生成的主机密钥与 `ForceCommand internal-sftp`。PTY 请求与两个通道必须仍然被允许。
省略该字段即可跳过此场景。

把 `WEBSSH_WARPGATE_FIXTURE` 指向该文件并运行：

```sh
python -m pytest tests/integration/test_warpgate.py -q
```

未设置该变量时，这些集成测试会被跳过。它们覆盖密码、OTP、密钥与组合因子策略；
终端与 SFTP 就绪状态；管理员待审批与浏览器审批取消；管理员审批成功；显式目标主机密钥确认；
仅 SFTP 目标；以及网关主机密钥变更后的拒绝。通过真实身份提供方完成浏览器审批，
需要另做部署专项验收测试。
