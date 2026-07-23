# 鱼饼 YuBing

[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue.svg)](LICENSE)
[![Apple platforms](https://img.shields.io/badge/platforms-iPhone%20%7C%20iPad%20%7C%20Mac%20%7C%20Apple%20Watch-black.svg)](#运行环境)

鱼饼是一款使用 SwiftUI 构建的 Apple 平台文件与媒体资料库。它把本地阅读、图片、视频、音乐和 Apple Watch 离线传输放在同一个应用中，并提供由 [MeloX](https://github.com/youshen2/MeloX) 改编的音乐发现、专辑、播放器和同步歌词体验。

> 鱼饼不是网易云音乐官方客户端，与网易云音乐及其关联公司不存在隶属、合作或授权关系。在线内容与播放能力可能随服务端接口、账号权限、地区和版权策略变化。

## 主要功能

### 文件与阅读

- 导入、搜索、排序、新建文件夹、重命名、移动、收藏、删除和系统分享。
- 阅读 TXT、Markdown、EPUB、MOBI、AZW3、DOC、DOCX 与 PDF。
- 支持章节、书签、阅读进度、自动翻页、亮度、边距、文本偏移和阅读时长。
- 查看本地图片、PDF 与视频。

### 音乐

- 管理本地歌曲、专辑和自建歌单，读取封面、艺人、专辑、音质及内嵌歌词元数据。
- 发现推荐歌单、排行榜、精品歌单、分类歌单和新碟，并查看在线歌单与专辑详情。
- 完整播放队列、随机播放、列表循环、单曲循环、进度、音量、倍速、睡眠定时和 AirPlay。
- 支持后台播放、锁屏信息、系统媒体控制、耳机控制和播放状态恢复。
- iPhone 竖屏播放器，以及 iPhone、iPad 和 Mac 的自适应横屏播放器。

### 同步歌词

- LRC、YRC、逐字歌词、翻译歌词和无逐字时间时的模拟进度。
- Apple Music 风格的焦点滚动、距离模糊和点击跳转。
- 错峰歌词移动、逐字辉光、逐字抬升与长音节轻微放大。
- 30 / 60 / 90 / 120 FPS 刷新率，以及字号、行距、辉光和错峰参数设置。
- 本项目不包含 MeloX 的 EVA 歌词样式或全屏天际歌词。

### Apple Watch

- 从 iPhone 接收并离线管理音乐、图片、视频、PDF 和鱼饼书籍包。
- 独立播放本地音乐，支持封面、歌词、队列、进度、倍速、随机与循环。
- 小屏专用的逐字符换行、逐字辉光、逐字抬升和错峰歌词焦点。
- 离线章节阅读、书签、自动翻页和阅读时长记录。

## 运行环境

- Xcode 26 或更高版本
- iOS / iPadOS 17.0 或更高版本
- macOS 14.0 或更高版本
- watchOS 10.0 或更高版本
- 真机安装需要可用于代码签名的 Apple Developer 账号

在 iOS 18、macOS 15 及更高版本上，歌词使用 SwiftUI `TextRenderer` 提供完整逐字动效；较低系统使用渐进高亮回退。iOS、iPadOS、macOS 和 watchOS 26 及以上会自动使用系统 Liquid Glass，较低系统使用原生材质回退。

## 构建

1. 使用 Xcode 打开 `apple/YuBing.xcodeproj`。
2. 为 `YuBing`、`YuBingMac` 和 `YuBingWatch` 目标选择自己的开发团队。
3. 如果默认 Bundle Identifier 已被占用，请同时修改手机、Mac 和 Watch 标识；Watch 标识必须使用手机标识作为前缀。
4. 选择 iPhone、iPad、Mac 或配对的 Apple Watch 设备后构建运行。

工程定义保存在 `apple/project.yml`。安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 后，可以在 `apple/` 目录运行：

```bash
xcodegen generate
```

## 音乐与歌词文件

本地音乐支持 MP3、M4A、AAC、WAV、AIFF、CAF、FLAC、ALAC、DSD、DSF、DFF、APE、OGG、Opus 和 WMA。部分格式会在本机缓存转码后播放。

歌词可以来自音频内嵌元数据，也可以与歌曲同名放置：

```text
Song.flac
Song.lrc
Song.yrc
Song.tlrc
Song.tyrc
```

受 DRM、密码或平台账号保护的文件不能作为普通本地文件导入。在线曲目是否可完整播放取决于网易云音乐服务端返回结果。

## Watch 传输

`WCSession.transferFile` 由系统后台排队，不保证即时送达。Apple 模拟器不支持完整文件传输流程，请使用已配对的 iPhone 与 Apple Watch 真机验证。

Watch 收到文件后会在系统临时 URL 失效前复制到自身 Documents 容器。之后的阅读和音乐播放不需要 iPhone 在线，应用也不会读取其他应用的数据。

## 项目结构

```text
apple/
├── App/                     # 应用入口
├── Models/                  # 文件、阅读、歌词与 MeloX 音乐模型
├── Services/                # 播放、资料库、解析、传输与 MeloX 接口适配
├── Views/                   # 阅读、图库、设置、发现、专辑、播放器与歌词
├── Components/              # 复用界面组件
├── Design/                  # 视觉样式
├── Resources/               # 本地化、图标、隐私清单与许可证说明
├── Watch/                   # Apple Watch 独立应用
├── Widget/                  # iOS 小组件扩展
├── Config/                  # 权限、签名配置与本地签名材料
└── project.yml              # XcodeGen 工程定义
```

## 致谢

音乐体验的重要部分改编自 [youshen2/MeloX](https://github.com/youshen2/MeloX)，包括发现与专辑交互、播放页结构、横屏布局、播放队列、歌词时间线、错峰焦点和逐字渲染思路。鱼饼将这些代码改造成支持本地文件、iPhone、iPad、macOS 与 watchOS 的实现，并移除了 EVA 和全屏天际歌词。

MeloX 上游还致谢了以下项目，鱼饼保留这些来源说明：

- [jayfunc/BetterLyrics](https://github.com/jayfunc/BetterLyrics)：逐字歌词渲染、辉光与动画参考。
- [WXRIW/Lyricify-Lyrics-Helper](https://github.com/WXRIW/Lyricify-Lyrics-Helper)：网易云 YRC 逐字歌词解析参考。
- [qier222/YesPlayMusic](https://github.com/qier222/YesPlayMusic)：网易云接口与播放器实现参考。

完整第三方说明见 [`apple/Resources/ThirdPartyNotices.md`](apple/Resources/ThirdPartyNotices.md)。各上游项目的代码与资源仍分别受其原始许可证约束。

## 许可证

鱼饼以 [GNU General Public License version 3](LICENSE) 发布。复制、修改或分发本项目时，必须依照 GPL-3.0 提供对应源代码、保留版权与许可证声明，并以兼容方式分发衍生作品。

本项目按许可证原样提供，不附带任何担保。使用者应自行遵守所在地法律法规、在线音乐服务条款以及音乐、图书和其他内容的版权要求。
