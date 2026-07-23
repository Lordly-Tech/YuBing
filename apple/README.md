# 鱼饼 Apple 工程

项目功能、许可证、致谢和使用说明见仓库根目录的 [`README.md`](../README.md)。

## 打开工程

1. 使用 Xcode 26 或更高版本打开 `YuBing.xcodeproj`。
2. 为 `YuBing`、`YuBingMac` 和 `YuBingWatch` 目标选择开发团队。
3. 如需修改 Bundle Identifier，请保持 Watch 标识以 iOS 标识为前缀。
4. iPhone / iPad 最低 iOS 17，Mac 最低 macOS 14，Watch 最低 watchOS 10。

安装 XcodeGen 后可在当前目录重新生成工程：

```bash
xcodegen generate
```

## 目录

- `App/`：应用入口。
- `Views/`：本地音乐库、发现页、专辑页、播放器、横屏播放器与歌词动效界面。
- `Models/`：媒体资料、歌词、MeloX 音乐数据模型。
- `Services/`：本地播放队列、音频控制器、MeloX 接口适配。
- `Resources/`：本地化、图标、隐私清单和第三方许可证说明。
- `Config/Signing/`：本地签名证书、描述文件和 CSR/key。
- `Watch/`：Apple Watch 独立资料库、播放器、歌词和阅读器。
- `Config/`：应用沙盒、网络、后台播放和签名配置。
