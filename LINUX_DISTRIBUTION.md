# DaySpark Linux 分发问题全记录

## 背景

DaySpark 是 Flutter 开发的跨平台日历待办应用。在 Linux 上分发时遇到了典型的"依赖地狱"问题——在作者开发机（较新发行版）上正常编译运行，但在目标用户机器（Ubuntu 22.04）上无法启动。

此文档记录完整的排查、修复过程、根因分析和解决方案。

---

## 问题与修复记录

### 问题 1：GLIBC_2.38 未找到

**现象**：
```
/lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.38' not found
```

**根因**：
- 开发机 GCC/GLIBC 版本较新（Ubuntu 24.04+，GLIBC 2.38）
- 目标机器 Ubuntu 22.04 仅有 GLIBC 2.35
- 插件 `flutter_secure_storage` 的 `.so` 引用了 `__isoc23_strtoll` / `__isoc23_strtoull`（GLIBC 2.38 新增的 C23 版本函数）
- 插件 `sqlite3_flutter_libs` 的 `.so` 引用了 `fmod`，但 ELF 版本标记要求 GLIBC_2.38

**修复方法**（对已编译产物的后处理）：

1. **清除符号版本要求**：用 `patchelf --clear-symbol-version` 去掉 `__isoc23_strtoll`、`__isoc23_strtoull`、`fmod` 的版本标记
2. **降级版本需求字符串**：将 `.so` 文件中的 `GLIBC_2.38` 替换为 `GLIBC_2.35`（两者等长 11 字符）
3. **修正 ELF Hash**：更新 `.gnu.version_r` 表中对应的 `vna_hash` 字段，匹配新字符串的 ELF hash 值

**涉及文件**：
- `libflutter_secure_storage_linux_plugin.so`
- `libsqlite3_flutter_libs_plugin.so`

---

### 问题 2：g_once_init_enter_pointer 未定义

**现象**：
```
undefined symbol: g_once_init_enter_pointer
```

**根因**：
- `g_once_init_enter_pointer` / `g_once_init_leave_pointer` 是 GLib 2.76 新增的 C11 原子操作版本
- Ubuntu 22.04 仅有 GLib 2.72

**修复方法**：创建 LD_PRELOAD 补丁库，提供兼容实现

```c
/* 64 位系统上 gsize == gpointer，直接委托给已有函数 */
int g_once_init_enter_pointer(void *volatile *location) {
    static g_once_init_enter_t real_func = NULL;
    if (!real_func)
        real_func = dlsym(RTLD_NEXT, "g_once_init_enter");
    return real_func ? real_func(location) : (*location == NULL);
}
```

**涉及文件**：
- `calendar_todo_app`（主程序）
- `libflutter_secure_storage_linux_plugin.so`
- `liburl_launcher_linux_plugin.so`

---

### 问题 3：__isoc23_strtoll / __isoc23_strtoull 未定义

**现象**：GLIBC 2.38 才有这两个符号，系统 GLIBC 2.35 不存在。

**修复方法**：LD_PRELOAD 补丁库中委托给标准 `strtoll`/`strtoull`：

```c
long long __isoc23_strtoll(const char *nptr, char **endptr, int base) {
    return strtoll(nptr, endptr, base);
}
```

C23 标准下这两个函数的行为变化（locale 无关解析）实际不影响 DaySpark 的使用场景。

---

### 最终解决方案架构

```
dayspark.sh（启动包装脚本）
  ├── LD_PRELOAD=libglibc_shim.so    ← 提供缺失的符号
  ├── LD_LIBRARY_PATH=lib/           ← 让主程序找到插件 .so
  └── exec calendar_todo_app
```

---

## 根因分析：为什么 Flutter Linux 应用容易遇到这个问题

### 技术层面

| 原因 | 说明 |
|------|------|
| **GLIBC 向前不兼容** | GLIBC 只保证向后兼容（新版本跑旧程序），不保证向前兼容（旧版本跑新程序）。而 Linux 各发行版 GLIBC 版本不同。 |
| **Flutter 插件生态不成熟** | 插件作者通常只在最新 Ubuntu 上测试，不考虑 GLIBC 兼容性。如果插件包含原生代码（.so），就会锁定 GLIBC 版本下限。 |
| **Flutter Linux 构建产物是"裸奔"的** | `flutter build linux` 只是生成二进制 + 零散 .so，没有任何依赖捆绑或版本校验机制。对比 Electron 直接内嵌 Chromium，Flutter 假设系统已经有所需的 GTK/GLib/GLIBC。 |
| **不存在统一的 Linux ABI 基线** | Windows 有 Windows SDK 版本约定，macOS 有 macOS SDK 版本。Linux 没有类似"最低 GLIBC 版本"的行业标准。 |

### 对比其他方案

| 方案 | 依赖处理 | 体积 | 性能 | 原生感 |
|------|---------|------|------|--------|
| **Electron** | 自带 Chromium + Node.js，百毒不侵 | ❌ 大 | ❌ 重 | ❌ Web 感 |
| **Flutter Linux** | 依赖系统，裸奔 | ✅ 小 | ✅ 快 | ✅ 接近原生 |
| **Tauri** | 系统 WebView + 可选捆绑 | ✅ 极小 | ✅ 快 | ⚠️ 取决于 WebView |
| **GTK 原生** | 系统自带 | ✅ 极小 | ✅ 快 | ✅ 原生 |

---

## 推荐解决方案：Flatpak 分发

### 为什么 Flatpak 是最优解

1. **运行时隔离**：Flatpak 自带 Freedesktop SDK 运行时，GLIBC、GLib、GTK 版本完全由你控制，不依赖用户系统
2. **一次构建，到处跑**：不管用户是 Ubuntu 20.04 还是 Arch Linux，行为一致
3. **沙箱安全**：应用默认隔离，需要访问文件/网络等需声明权限
4. **Flathub 生态**：上架后可被数百种 Linux 发行版的用户通过软件中心安装
5. **CI 友好**：可在 GitHub Actions 中自动构建并发布

### 实现步骤

#### 1. 安装工具
```bash
sudo apt install flatpak flatpak-builder
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install flathub org.freedesktop.Platform//24.08 org.freedesktop.Sdk//24.08
```

#### 2. 创建 Flatpak 清单

在项目 `linux/` 目录下创建 `io.github.liuchangchxy.dayspark.yml`：

```yaml
id: io.github.liuchangchxy.dayspark
runtime: org.freedesktop.Platform
runtime-version: '24.08'
sdk: org.freedesktop.Sdk
command: dayspark

finish-args:
  - --socket=wayland
  - --socket=fallback-x11
  - --share=ipc
  - --share=network
  - --device=dri
  - --filesystem=home  # 用于 CalDAV 配置和文件操作

modules:
  - name: dayspark
    buildsystem: simple
    build-commands:
      - flutter build linux --release
      - install -Dm755 build/linux/*/release/bundle/dayspark /app/bin/dayspark
      - cp -r build/linux/*/release/bundle/lib /app/lib/
      - cp -r build/linux/*/release/bundle/data /app/data/
    sources:
      - type: dir
        path: ..
```

> **注意**：需要在 Flatpak SDK 中安装 Flutter SDK。更推荐的做法是在 CI（GitHub Actions）中：
> 1. 在宿主机构建 Flutter Linux 产物
> 2. 用 `flatpak build-finish` 打包成 Flatpak
> 3. 参考 Flathub 上已有的 Flutter 应用（如 `com.github.GradienceTeam.Gradience`）

#### 3. 构建与测试
```bash
flatpak-builder --force-clean build-dir io.github.liuchangchxy.dayspark.yml
flatpak-builder --run build-dir io.github.liuchangchxy.dayspark.yml
flatpak-builder --install --user build-dir io.github.liuchangchxy.dayspark.yml
```

#### 4. 发布到 Flathub
- Fork [flathub/flathub](https://github.com/flathub/flathub)
- 在 `flatpak/` 目录下创建应用条目
- 提交 PR，Flathub 的 CI 会自动构建和发布

### Flatpak 架构示意

```
用户系统（GLIBC 2.35, GLib 2.72）
  └── Flatpak 运行时（Freedesktop 24.08: GLIBC 2.38, GLib 2.80）
        └── DaySpark 应用
              ├── calendar_todo_app
              ├── lib/*.so
              └── data/
```

---

## 临时修复文件（如果选择继续使用裸二进制分发）

当前已生成的修复文件位于用户 `~/.local/share/dayspark/`：

| 文件 | 用途 |
|------|------|
| `libglibc_shim.c` | 补丁库源码，提供缺失的 GLIBC/GLib 符号 |
| `libglibc_shim.so` | 编译好的补丁库 |
| `dayspark.sh` | 启动包装脚本，设置 LD_PRELOAD + LD_LIBRARY_PATH |

启动命令：`dayspark`（通过 `~/.local/bin/dayspark` 软链接指向包装脚本）

---

## 下一步方向（按推荐优先级）

1. **🥇 Flatpak 打包** —— 从根本上解决依赖问题，适合 Linux 桌面分发
2. **🥇 GitHub Actions CI 集成 Flatpak 构建** —— 每次发布自动打包
3. **🥈 CI 构建基线降级** —— 在 CI 中使用 Ubuntu 22.04 镜像构建，产物天然兼容旧系统（作为 Flatpak 的补充或低成本替代方案）
4. **🥉 上架 Flathub** —— 让所有 Linux 用户都能从软件中心安装
5. **🏅 其他平台同理** —— macOS 用 `.dmg`/Homebrew，Windows 用 MSIX/NSIS，移动端走应用商店

---

## 经验教训

1. **Flutter Linux 的"构建"不等于"分发"**：`flutter build linux` 只是第一步，分发需要额外处理依赖绑定
2. **GLIBC 版本是 Linux 桌面分发的第一道坎**：发布前应在最旧的 LTS 发行版上测试
3. **LD_PRELOAD 是瑞士军刀但不是银弹**：它能修补部分符号缺失问题，但 GLIBC 版本校验在动态链接器层面，LD_PRELOAD 无法绕过
4. **插件生态是风险点**：任何包含原生代码的 Flutter 插件都可能引入 GLIBC/GLib 版本依赖。发布前需要审查插件的 `linux/` 目录下的 `.so` 文件的最低 GLIBC 要求
5. **测试矩阵**：至少应该在 Ubuntu 22.04 LTS 和 24.04 LTS 上各跑一次集成测试

---

*文档生成日期：2026-05-14*
*环境：Ubuntu 22.04.5 LTS, GLIBC 2.35, GLib 2.72*
