# 云盘同步 Provider 能力核查 / Cloud-drive provider capability review

> 核查日期 / Checked: **2026-11-14**。以下每条结论都附官方页面 URL；**没有任何一条经过真实账号联调**——本轮没有可用的开发者账号，也没有可注册的应用。页面内容随时会变，接入前需重核。
>
> 用途：决定「普通用户登录自己的云盘即可同步」这件事在六个 Provider 上分别卡在哪里，以及在只能使用官方 OAuth / 官方 API 的前提下哪些能做、哪些不能做。

## 1. 结论矩阵 / Matrix

| Provider | 官方第三方 API | 自助注册 | OAuth + refresh | 条件写（防互覆） | 判定 |
|---|---|---|---|---|---|
| 百度网盘 | 有（pan.baidu.com/union） | 个人实名即可建 1 个应用；公开发布需上线审核，审核期限 10 人 | 授权码模式；**不支持 PKCE**；refresh_token 有效期 10 年、**只能用一次** | 无（仅 `ondup=fail/overwrite/newcopy`） | **GATED** |
| 夸克网盘 | **无** | 无 | — | — | **UNAVAILABLE** |
| 115 | 有（open.115.com） | 个人或企业，人工审核约 7 工作日；应用另审 7 工作日 | 授权码模式 + 手机扫码 PKCE；refresh 1 年 | 无 | **GATED** |
| Google Drive | 有 | 是（Cloud Console） | `drive.file` / `drive.appdata` 为非敏感 scope，只需基础 OAuth 验证；PKCE；refresh 长期 | **无** 文档化的 `If-Match`/ETag | **USABLE** |
| OneDrive（Graph） | 有 | 是（Entra 租户） | PKCE；需 `offline_access` 才有 refresh | **有** `If-Match` → 412 | **USABLE** |
| Dropbox | 有 | 是（App Console） | PKCE；`token_access_type=offline` 长寿命 refresh | **有** `WriteMode.update` + `rev` | **USABLE** |
| WebDAV | 协议标准（RFC 4918） | 不需要注册 | 服务端各自实现（基本认证 / OAuth 视服务而定） | **有** `If-Match` / `If-None-Match` + ETag | **USABLE** |
| DaySpark 自托管 Server | 本项目自有 | 不需要 | 已有 JWT + SSE（P2） | 服务端 rev + LWW | **已完成** |

## 2. 逐条证据 / Per-provider evidence

### 夸克网盘 — UNAVAILABLE（用户明确要求的结论项）

- <https://open.quark.cn/> 是唯一的官方开发者入口，页面标题为「夸克小程序开发者平台」，没有网盘/文件存储 API 文档。
- <https://vt.quark.cn/business/center?entry=allapis> 与 <https://scan.quark.cn/blm/scank-business-docs-703/tech> 是「夸克开放平台」，只提供 OCR / 扫描类企业能力。
- <https://pan.quark.cn/developer> 302 跳回消费端首页——网盘域下没有开发者门户。
- 唯一可查的接口文档来自第三方逆向整理（非官方），其中自述「非官方中文接口文档…静态逆向分析整理」「夸克官方开放平台尚在内测、未公开完整文档」。

**判定**：没有可正式用于第三方 App 的稳定官方文件 API，也没有公开的 OAuth 客户端注册路径。按用户指令**标记为不可用**，不接入任何非官方方案。

### 百度网盘 — GATED

- <https://pan.baidu.com/union> 是官方开放平台；接入流程要求先完成实名认证再建应用。
- 实名认证可「认证成为个人开发者或企业开发者」，个人开发者「在控制台创建 1 个应用」。
- 应用上线审核「仅受理通过实名认证的开发者／企业提交的应用」；个人自用应用「免上线审核」；「首次上线的应用在审核期间支持 10 人使用」；未审核应用「无法对外大规模分发」。
- 授权：`https://openapi.baidu.com/oauth/2.0/authorize` + `/oauth/2.0/token`，无 PKCE 参数；`refresh_token`「只支持使用一次」，有效期 10 年。
- 上传先 `precreate` 再分片（不超过 1024 片）或单步 2GB，必须落在应用自己的 `/apps/{appname}` 目录；文件列表 `xpan/file?method=list` 只有 offset 分页，没有 delta。

**判定**：技术上能做，但「普通用户登录即用」要求应用已上线审核；个人开发者名下只有 1 个应用额度，审核期 10 人上限。**需要真人注册并走审核**。

### 115 — GATED

- <https://open.115.com/> 官方开发者平台；接入流程写明个人或企业入驻（个人需实名材料），「平台将在 7 个工作日内完成审核」，应用另需审核 7 工作日才下发 AppID/AppSecret。
- 授权码模式 token 端点 `https://passportapi.115.com/open/authCodeToToken`（access token 7200s，refresh 1 年）；另有手机扫码 PKCE 模式。
- 上传 `POST https://proapi.115.com/open/upload/init`，OSS 分片；文件列表 `GET https://proapi.115.com/open/ufile/files`（limit 最大 1150，offset 分页，无 delta/cursor）。
- 开发须知：「对所有 API 实施频率控制策略」（细节未公开），并禁止「调用非公开接口」。

**判定**：能力齐备但接入被人工审核挡住，**需要真人提交入驻与两个 7 工作日审核**。

### Google Drive — USABLE（技术面）

- <https://developers.google.com/workspace/drive/api/guides/api-specific-auth>：`drive.file` 为非敏感 scope，只授予应用自己创建/用户共享给应用的文件；非敏感 scope「only require basic OAuth App Verification」。
- <https://developers.google.com/identity/protocols/oauth2/native-app>：授权 `https://accounts.google.com/o/oauth2/v2/auth`，token `https://oauth2.googleapis.com/token`，「Always use PKCE」，安装型应用「refresh tokens are always returned」。
- <https://developers.google.com/workspace/drive/api/guides/appdata>：`appDataFolder` 是隐藏的应用私有目录（`drive.appdata`，非敏感），用户卸载应用即删除——比在用户可见目录里塞一个同步文件更干净。
- 条件写：v3 `files.update` 文档中没有 `If-Match`，`files` 资源没有 `etag`（只有 output-only 的 `version`/`headRevisionId`）→ **按不支持处理**，冲突检测必须自己做。
- 变更流：`changes.getStartPageToken` + `changes.list`，只有 token 游标。

**判定**：技术可用。**未做**：需要在 Cloud Console 建立一个项目并产出 client ID；公开分发到 100 个测试用户之外需要处理验证流程。

### OneDrive / Microsoft Graph — USABLE（技术面）

- <https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow>：PKCE S256；refresh token 仅在请求 `offline_access` 时下发。
- <https://learn.microsoft.com/en-us/onedrive/developer/rest-api/concepts/special-folders-appfolder>：`Files.ReadWrite.AppFolder` scope 给出应用私有 `Apps` 目录（`GET /drive/special/approot`）。
- <https://learn.microsoft.com/en-us/graph/api/driveitem-put-content> 单次 ≤250MB；`createUploadSession` 分片「multiple of 320 KiB」。
- **条件写**：upload session 支持 `if-match`，「mismatch returns 412 Precondition Failed」。
- <https://learn.microsoft.com/en-us/graph/api/driveitem-delta>：`@odata.deltaLink`，`410 Gone` 需全量重同步。
- 发布者验证：<https://learn.microsoft.com/en-us/entra/identity-platform/publisher-verification-overview>，免费但需要 MPN/CPP 账号，且「Apps that are registered by using a Microsoft account can't be publisher verified」。

**判定**：技术可用。**未做**：需要 Entra 租户内注册应用产出 client ID；部分租户对未验证应用强制 step-up consent。

### Dropbox — USABLE（技术面）

- <https://docs.dropboxapi.com/dropbox-api/docs/oauth>：`https://www.dropbox.com/oauth2/authorize`，PKCE 支持，`token_access_type=offline` 下发 refresh。
- <https://docs.dropboxapi.com/dropbox-api/docs/get-started/authorization>：refresh token「long-lived and won't expire automatically」。
- 上传单次 ≤150MiB，session 分片 4MiB 对齐，session 有效期 7 天。
- **条件写**：Files API `WriteMode.update`「Overwrite if the given "rev" matches the existing file's "rev"」，另有 `strict_conflict` → 真正的条件写。
- App Folder 权限只限 `/apps` 下自己的目录。
- <https://docs.dropboxapi.com/dropbox-api/docs/get-started/tutorial/app-console>：应用默认 development 状态，「Apply for production」是人工审核。

**判定**：技术可用，条件写最强。**未做**：需要 App Console 注册应用产出 key；公开分发前过 production review。

## 3. 对实现的影响 / What this means for the feature

1. **共享 Sync Core 与 Provider 无关，可以先做也可以最后做**：六个 Provider 都不能提供「服务端合并」，所以合并必须搬到客户端。现有 `server/lib/src/sync/lww.dart` 的规则（字段级 LWW、tombstone vs upsert、opId 同秒仲裁）可以直接复用，前提是把「服务端接收时间」换成「对云文件的那次成功写入时间」，并用条件写（ETag/If-Match/rev）作为乐观锁，412 时重读重合并。
2. **条件写只有 OneDrive / Dropbox / WebDAV 原生存**；Google 需要在文件内自带 `generation`/`rev` 字段做检测，百度与 115 只能靠「写后读回比对」。这不是可选项：没有它就无法满足「多设备并发结果确定」。
3. **普通用户流程（设置 → 同步 → Provider → 授权 → 自动同步）要求应用内置 client ID**。这六个 Provider 里，除 WebDAV 外都需要先注册应用；夸克连注册入口都没有。**client ID 必须由账号持有人注册并承担审核**，无法在本机凭空产生。
4. **真实账号 E2E（两设备、离线互改、OAuth refresh、Provider 切换）无法在无账号环境完成**，任何声称已通过的结论都不可信。

## 4. 需要人做的事 / Human blockers

| # | 事项 | 谁 | 阻塞什么 |
|---|---|---|---|
| 1 | 百度：注册个人开发者 + 实名认证 + 应用上线审核（个人限 1 应用） | 账号持有人 | 百度网盘 Provider 全部 |
| 2 | 115：入驻（个人/企业）+ 应用审核，各约 7 工作日 | 账号持有人 | 115 Provider 全部 |
| 3 | 夸克：向夸克/阿里确认是否存在未公开的网盘开放接口 | 账号持有人 | 夸克能否接入的最终结论 |
| 4 | Google：Cloud Console 建项目、启用 Drive API、产出 client ID；决定 Testing 还是 In production（`drive.appdata` 非敏感可免验证） | 账号持有人 | Google Drive Provider 全部 |
| 5 | Microsoft：Entra 注册应用、产出 client ID；如需公开分发再做 publisher verification（需 MPN） | 账号持有人 | OneDrive Provider 全部 |
| 6 | Dropbox：App Console 注册应用、产出 app key；公开分发前过 production review | 账号持有人 | Dropbox Provider 全部 |

## 5. 不依赖账号就能推进的部分 / Buildable without accounts

- 把 `lww.dart` 的规则提到 `dayspark_contracts`，让服务端与客户端共用一份合并实现。
- 一个 Provider 无关的「云文件同步核心」：本地 outbox → 读远程状态文件 → 客户端合并 → 条件写 → 412 重试 → 经 `SyncApplier` 落地；幂等靠现有 opId / tombstones。
- WebDAV 作为第一个可端到端验证的后端（无需注册、条件写原生、可用本地 WebDAV 服务做两设备测试）。
- 设置页的 Provider 选择与「唯一活动同步源」迁移逻辑（可先用 WebDAV + 自托管 Server 验证）。
- OAuth 授权流程的抽象（PKCE + 自定义 scheme 回调）；每个 Provider 只差 client ID 与端点常量。

这些做完后，每个云盘 Provider 的接入就退化为「注册应用 → 填 client ID → 跑同一套适配器 + 真实账号 E2E」，而不是从零设计。
