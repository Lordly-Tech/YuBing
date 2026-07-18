# 鱼饼 YuBing

鱼饼是一个只面向 Apple 平台的 SwiftUI 文件与媒体资料库，包含 iPhone、iPad、Mac 和 Apple Watch 三个应用目标。

## 当前能力

- iPhone / iPad / Mac：导入、搜索、排序、新建文件夹、重命名、移动、收藏、删除与系统分享。
- 阅读：TXT、EPUB、MOBI、AZW3、DOC、DOCX 使用章节化阅读器；PDF 使用系统 PDFKit 保留原页面。支持章节识别与智能分章、上下章、自动翻页、书签、阅读亮度、常驻亮屏、上下边距、文本偏移进度和阅读时长。
- 音乐：本地队列、进度控制、上一首/下一首、后台播放和系统正在播放控制。
- 图库：从照片或文件导入、缩略图、全屏查看与缩放。
- iPhone 到 Watch：复杂电子书会先在手机端转换为带章节、封面和阅读位置的鱼饼离线书籍包，再由 WatchConnectivity 后台传输；PDF、图片和音频保持原文件传输。
- Apple Watch：只管理鱼饼的私有资料库，可建文件夹、重命名、移动、收藏和删除；可离线选章阅读、自动翻页、管理书签、查看封面和记录时长，也可独立播放已经收到的音乐。
- iOS、iPadOS、macOS、watchOS 26 及以上使用 SwiftUI 原生 Liquid Glass；较低系统使用系统材质和原生控件回退。

## 运行

1. 使用 Xcode 26 或更高版本打开 `YuBing.xcodeproj`。
2. 在 `YuBing`、`YuBingMac`、`YuBingWatch` 三个目标的 Signing & Capabilities 中选择开发团队。
3. 如默认标识已被占用，请一起修改 `top.lordly.yubing` 和 `top.lordly.yubing.watchkitapp`。Watch 标识必须以 iOS 标识为前缀。
4. iOS / iPadOS 最低版本为 17，macOS 最低版本为 14，watchOS 最低版本为 10。

仓库同时保留了 `project.yml`。安装 XcodeGen 后可在本目录运行 `xcodegen generate` 重新生成工程。

## Watch 传输说明

`WCSession.transferFile` 由系统排队并在后台择机传输，不保证即时送达。Apple 的模拟器不支持该文件传输 API，必须使用已经配对的 iPhone 与 Apple Watch 真机验证。

收到文件时，Watch 应用会在系统临时 URL 失效前立即复制到自己的 Documents 容器。之后的阅读与音乐播放不需要 iPhone 在线。应用不会读取或展示 Watch 上其他应用与系统的文件。

## 格式边界

手机 / iPad / Mac 阅读支持：

- 章节化电子书：`.txt`、`.epub`、`.mobi`、`.azw3`、`.doc`、`.docx`（以及 `.md`、`.markdown`）
- 原页面阅读：`.pdf`
- EPUB 会读取内嵌目录与封面；TXT 可在阅读菜单中手动设置封面。

Watch 离线支持：

- 电子书：由 iPhone 转换的 `.ybbook` 章节包
- 漫画 / 文档：`.pdf` 及单张 `.jpg`、`.png`、`.heic` 等图片
- 音乐：`.mp3`、`.m4a`、`.aac`、`.wav`、`.caf`、`.flac`、`.alac` 等 AVFoundation 可解码格式

受 DRM、密码或平台账号保护的电子书与音乐无法作为普通文件导入。老式 DOC 的复杂排版、文本框和嵌入对象可能无法完整转换；建议优先使用 DOCX。扫描版 PDF 可以按原页面查看，但没有可用于自动分章的文本。

## 工程结构

- `Shared/`：iOS、iPadOS、macOS 共用的数据层、媒体服务、设计系统与界面。
- `Watch/`：Watch 私有资料库、接收服务、阅读器和本地播放器。
- `Config/`：各目标的沙盒与签名能力文件。
- `YuBing.xcodeproj/`：可直接打开的多目标 Xcode 工程。
