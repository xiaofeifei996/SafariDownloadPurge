# 星标收藏 (StarFav)

在 iOS 16 的锁屏播放器与控制中心播放器上加入 iOS 17 风格的 ☆ / ★ 收藏按钮。

## 原理

- 注入 `com.apple.springboard`（锁屏 + 控制中心紧凑播放器）与 `com.apple.MediaRemoteUI`（展开播放器）。
- Hook `MediaControlsTransportStackView` 与 `MRUNowPlayingTransportControlsView` 的 `layoutSubviews`，在原生 `leftButton` 左侧摆放自绘星标按钮（与 iOS 17 位置一致）。
- 点击时调用 MediaRemote 的 `MRMediaRemoteSendCommand(21 /* LikeTrack */)`，由当前播放 app 执行收藏/取消收藏。
- 状态读取 `MRMediaRemoteGetNowPlayingInfo` 的 `kMRMediaRemoteNowPlayingInfoIsLiked` / `SupportsIsLiked`；app 未提供该字段时按曲目唯一标识本地记忆（CFPreferences `com.axs.starfav`）。
- 监听 `kMRMediaRemoteNowPlayingInfoDidChangeNotification` 等系统通知，实时刷新星标状态。

## 构建

CI：GitHub Actions `Build Theos Projects`（roothide Theos + iPhoneOS16.5 SDK，rootless arm64 / roothide arm64e 双架构）。
