# Security Policy / 安全策略

## Supported Versions / 支持的版本

| Version / 版本 | Supported / 支持 |
|-------|----------|
| 0.17.x | ✅ |
| < 0.17.0 | ❌ |

> DaySpark is in early development (pre-1.0). Only the latest release receives security fixes.
> DaySpark 处于早期开发阶段（pre-1.0）。只有最新版本接受安全修复。

---

## Reporting a Vulnerability / 报告安全漏洞

**Please do not report security vulnerabilities through public GitHub Issues.**
**请不要通过公开的 GitHub Issues 报告安全漏洞。**

### How to Report / 如何报告

1. **Preferred / 推荐方式**: Open a [GitHub Security Advisory](https://github.com/liuchangchxy/dayspark/security/advisories/new) (private disclosure) / 使用 GitHub Security Advisory（私密披露）
2. **Alternative / 备选方式**: Open a regular issue but mark the title with `[Security]` prefix and **do not include exploit details** — we will follow up privately / 创建普通 issue 但标题加 `[Security]` 前缀，**不要包含漏洞利用细节**

### What to Include / 应包含的信息

- Description of the vulnerability / 漏洞描述
- Affected version / 受影响版本
- Steps to reproduce (if applicable) / 复现步骤（如适用）
- Potential impact / 潜在影响
- Suggested fix (optional) / 建议修复方案（可选）

### Response Time / 响应时间

- **Acknowledgment / 确认**: Within 48 hours / 48 小时内
- **Initial assessment / 初步评估**: Within 7 days / 7 天内
- **Fix timeline / 修复时间**: Depends on severity, critical issues prioritized / 视严重程度而定，关键问题优先处理

---

## Known Security Practices / 已知安全措施

- CalDAV credentials are stored in **FlutterSecureStorage** (not database plaintext) / CalDAV 凭证存储在 FlutterSecureStorage（非数据库明文）
- All CalDAV connections are upgraded to **HTTPS** automatically / 所有 CalDAV 连接自动升级为 HTTPS
- API keys are **masked** in the UI (only last 4 characters visible) / API Key 在 UI 中掩码显示
- Biometric lock available via **local_auth** (Face ID / Touch ID) / 支持生物识别锁
- All data is stored **locally** — no cloud relay by default / 所有数据本地存储，默认不经云端中转
