# LOL 游戏服检测脚本

通过分析 `netstat` 输出的 UDP/TCP 连接，识别当前 LOL 客户端所连接的服务器 IP 及所属地区。

## 文件

- `lol_check_final.bat` — 主脚本（v6，Claude Code 诊断修复版）
- `test_netstat.bat` — 核心逻辑测试脚本（不需要 LOL）
- `review-report.md` — 审查记录

## 使用

在 Windows CMD 中运行：

```cmd
lol_check_final.bat
```

先跑 `test_netstat.bat` 验证核心逻辑，再进游戏跑主脚本。

## 版本历史

| 版本 | 改动 |
|------|------|
| v3 | 原始版本 |
| v4 | 去掉 ESTABLISHED + 端口过滤，添加 UDP 支持 |
| v4c | CRLF 行尾修复 |
| v5 | Claude Code 诊断修复（UDP tokens + server_region + findstr escape） |
| v6 | test 闪退修复 + UDP `*:*` 无法获取 IP 修复 |
