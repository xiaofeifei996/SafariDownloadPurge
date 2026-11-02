# Safari Download Purge

Safari 的下载列表只保存记录，点「清除」只会删掉那行记录，文件仍然留在「文件」App 的下载目录里。
本插件在清除动作发生前先把对应文件从磁盘删除，做到列表与文件同步。

## 功能

- 单个清除、多选清除、清除全部三种场景都可分别开关。
- 删除前校验：文件必须位于 Safari 的下载目录内，且没有被其它下载记录引用。
- 默认保留 `ipa / deb / dmg / rar / 7z` 等安装包与压缩包，只删记录，避免误删要存档的文件。
- Safari 沙盒内 unlink 失败时，路径进入队列，由 SpringBoard 兜底排空。
- 删除成功后在 Safari 内显示一行轻提示。
- 「只记录不删除」开关可用来先观察路径判断是否正确。

## 设置

设置 → Safari 下载清除同步

| 开关 | 默认 | 作用 |
| --- | --- | --- |
| 启用插件 | 开 | 总开关，关闭后只保留 Safari 原生行为 |
| 单个清除时删除文件 | 开 | `removeDownloads:` 单条 |
| 清除全部时删除文件 | 开 | 全部清除与按日期清除 |
| 保留安装包与压缩包 | 开 | 命中扩展名时不 unlink |
| 只记录不删除 | 关 | 只写日志，便于排查 |

## 技术要点

- Hook 目标：`_SFDownloadManager` 的 `removeDownloads:` 与 `removeDownloadsStartedAfterDate:`，
  通过 `MSHookMessageEx` 在运行时安装，SafariServices 延迟加载时按 0.5 秒重试 20 次。
- 类查找走 `objc_getClass` → `NSClassFromString`，避免对私有框架符号建立硬链接依赖。
- 配置通过 cfprefsd（`CFPreferences*`）读写域 `com.axs.safaridownloadpurge`，并对
  `/var/mobile/Library/Preferences`、`/var/jb/...`、RootHide 的 `.jbroot-*` 目录做文件回退读取。
- 沙盒兜底队列存放在同一偏好域，SpringBoard 侧在启动 3 秒后、以及应用回到前台时排空。

## 打包

CI：`.github/workflows/build-theos.yml`（macos-14 + roothide/theos + iPhoneOS 16.5 SDK），
矩阵输出 rootless `iphoneos-arm64` 与 roothide `iphoneos-arm64e` 两个包。

本地：

```sh
sh build.sh rootless
sh build.sh roothide
```

## 已知边界

- 只在 iOS 15 及以上验证目标；私有类头文件按 iOS 16/17/18 的 runtime dump 对齐。
- 删除动作发生在记录移除之前；若 Safari 之后取消移除，文件已经无法恢复（本插件不做回收站）。
- 未在越狱真机上做过完整回归，安装后建议先用「只记录不删除」确认路径判断。
