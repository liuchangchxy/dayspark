# CalDAV Setup Guide / CalDAV 配置教程

DaySpark supports calendar synchronization via the CalDAV protocol. Below are configuration steps for common providers.
DaySpark 支持通过 CalDAV 协议同步日历数据。以下是常见服务商的配置步骤。

---

## General Steps / 通用步骤

1. Open DaySpark → Settings → Add CalDAV Account / 打开 DaySpark → 设置 → 添加 CalDAV 账户
2. Enter server address, username, and password / 填写服务器地址、用户名和密码
3. Tap Save — the app will auto-discover available calendars / 点击保存，应用会自动发现可用的日历
4. After setup, sync can be manual or automatic / 配置成功后可以手动同步或自动同步

## Common Providers / 常见服务商配置

### iCloud

- **Server / 服务器地址**: `https://caldav.icloud.com`
- **Username / 用户名**: Your Apple ID (email) / 你的 Apple ID（邮箱）
- **Password / 密码**: Requires an App-Specific Password / 需要生成「App 专用密码」
  1. Go to / 前往 [appleid.apple.com](https://appleid.apple.com)
  2. Sign in, select App-Specific Passwords / 登录后选择「App 专用密码」
  3. Generate a new password — use this instead of your Apple ID password / 生成一个新密码，用这个密码代替 Apple ID 密码

### Google Calendar / Google 日历

- **Server / 服务器地址**: `https://calendar.google.com/calendar/dav/YOUR_EMAIL@gmail.com/events`
- **Username / 用户名**: Your Gmail address / 你的 Gmail 地址
- **Password / 密码**: Requires an App Password (if 2FA is enabled) / 需要生成「应用专用密码」（如果启用了两步验证）

> **Note / 注意**: Google's CalDAV support is limited. Import/export is recommended instead. / Google 的 CalDAV 支持有限，推荐使用日历导入/导出功能替代。

### Nextcloud

- **Server / 服务器地址**: `https://YOUR_SERVER/remote.php/dav/calendars/USERNAME/`
- **Username / 用户名**: Your Nextcloud username / 你的 Nextcloud 用户名
- **Password / 密码**: Your Nextcloud password or app password / 你的 Nextcloud 密码或应用密码

### Synology Calendar / 群晖日历

- **Server / 服务器地址**: `https://YOUR_NAS/caldav/`
- **Username / 用户名**: DSM account name / DSM 账户名
- **Password / 密码**: DSM password or app password / DSM 密码或应用密码

### Radicale (Self-hosted / 自建)

- **Server / 服务器地址**: `https://YOUR_SERVER/`
- **Username / 用户名**: Username set in Radicale config / 你在 Radicale 配置中设置的用户名
- **Password / 密码**: Corresponding password / 对应的密码

### Baikal (Self-hosted / 自建)

- **Server / 服务器地址**: `https://YOUR_SERVER/dav.php`
- **Username / 用户名**: Baikal username / Baikal 用户名
- **Password / 密码**: Baikal password / Baikal 密码

## FAQ / 常见问题

**Q: Connection timeout? / 连接超时怎么办？**
A: Check the server address and ensure HTTPS is used. For self-hosted servers, check firewall and port settings. / 检查服务器地址是否正确，确保使用 HTTPS。如果是自建服务器，检查防火墙和端口。

**Q: Why can't I see my calendars? / 为什么看不到日历？**
A: Make sure the calendar is enabled on the server and your account has access. / 确保服务器上的日历已经启用，并且你的账户有访问权限。

**Q: Incomplete sync? / 同步不完整？**
A: First sync may take time. Try tapping "Sync Now" in settings to trigger manually. / 首次同步可能需要一些时间。可以尝试在设置中点击「立即同步」手动触发。

**Q: Does it sync todos? / 支持待办同步吗？**
A: DaySpark syncs calendar events (VEVENT) via CalDAV. Todos (VTODO) are stored locally for now. / 目前 DaySpark 通过 CalDAV 同步日历事件（VEVENT），待办事项（VTODO）存储在本地。
