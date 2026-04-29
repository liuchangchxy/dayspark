# CalDAV 配置教程

DaySpark 支持通过 CalDAV 协议同步日历数据。以下是常见服务商的配置步骤。

## 通用步骤

1. 打开 DaySpark > 设置 > 添加 CalDAV 账户
2. 填写服务器地址、用户名和密码
3. 点击保存，应用会自动发现可用的日历
4. 配置成功后可以手动同步或自动同步

## 常见服务商配置

### iCloud

- **服务器地址**: `https://caldav.icloud.com`
- **用户名**: 你的 Apple ID（邮箱）
- **密码**: 需要生成「App 专用密码」
  1. 前往 [appleid.apple.com](https://appleid.apple.com)
  2. 登录后选择「App 专用密码」
  3. 生成一个新密码，用这个密码代替 Apple ID 密码

### Google Calendar

- **服务器地址**: `https://calendar.google.com/calendar/dav/你的邮箱@gmail.com/events`
- **用户名**: 你的 Gmail 地址
- **密码**: 需要生成「应用专用密码」（如果你的账户启用了两步验证）

> 注意：Google 的 CalDAV 支持有限，推荐使用日历导入/导出功能替代。

### Nextcloud

- **服务器地址**: `https://你的服务器/remote.php/dav/calendars/用户名/`
- **用户名**: 你的 Nextcloud 用户名
- **密码**: 你的 Nextcloud 密码或应用密码

### Synology Calendar

- **服务器地址**: `https://你的NAS地址/caldav/`
- **用户名**: DSM 账户名
- **密码**: DSM 密码或应用密码

### Radicale (自建)

- **服务器地址**: `https://你的服务器/`
- **用户名**: 你在 Radicale 配置中设置的用户名
- **密码**: 对应的密码

### Baikal (自建)

- **服务器地址**: `https://你的服务器/dav.php`
- **用户名**: Baikal 用户名
- **密码**: Baikal 密码

## 常见问题

**Q: 连接超时怎么办？**
A: 检查服务器地址是否正确，确保使用 HTTPS。如果是自建服务器，检查防火墙和端口。

**Q: 为什么看不到日历？**
A: 确保服务器上的日历已经启用，并且你的账户有访问权限。

**Q: 同步不完整？**
A: 首次同步可能需要一些时间。可以尝试在设置中点击「立即同步」手动触发。

**Q: 支持待办同步吗？**
A: 目前 DaySpark 通过 CalDAV 同步日历事件（VEVENT），待办事项（VTODO）存储在本地。
