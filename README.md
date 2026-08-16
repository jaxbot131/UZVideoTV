# UZVideoTV

UZVideoTV 是由 [jaxbot131](https://github.com/jaxbot131) 面向 Apple TV（tvOS）开发的 UZ 生态客户端，使用 SwiftUI 针对电视端交互与播放体验重新实现。UZ 播放器原项目由 [YYDS678](https://github.com/YYDS678) 开发和维护。本项目兼容 UZ 原生分享代码，可导入用户自己的视频源，并提供跨源搜索、推荐浏览、收藏、播放历史和剧集播放等功能。

## 原项目与致谢

- UZ 播放器原项目：[YYDS678/uzVideo](https://github.com/YYDS678/uzVideo)
- UZ 播放器原作者：[YYDS678](https://github.com/YYDS678)
- Apple TV/tvOS 版本由 [jaxbot131](https://github.com/jaxbot131) 开发和适配。
- 感谢原作者对 UZ 播放器、分享代码使用方式和相关生态的开发与维护。

## 功能

- 使用 UZ 原生分享代码导入和管理视频源
- 选择视频源并搜索内容
- 多源快速推荐搜索
- 豆瓣推荐与分类筛选
- 收藏与播放历史
- 播放线路和剧集选择
- 播放进度记录与跳过片头片尾设置
- 面向电视遥控器的 SwiftUI 界面

## 系统要求

- macOS
- Xcode 15 或更高版本
- tvOS 17.0 或更高版本
- Apple 开发者账号（免费账号可用于个人设备调试，具体限制以 Apple 当前政策为准）

## 构建与运行

1. 在 macOS 上使用 Xcode 打开 `UZVideoTV.xcodeproj`。
2. 选择 `UZVideoTV` Target，在 Signing & Capabilities 中选择自己的 Development Team。
3. 如 Bundle Identifier 已被占用，将 `com.uzvideo.tv` 修改为你自己的唯一标识。
4. 选择 Apple TV 真机或模拟器，然后点击 Run。

## 使用 ATVLoadly 部署与续签

UZVideoTV 可配合 [ATVLoadly Remote Registry](https://github.com/jaxbot131/ATVLoadly-Remote-Registry) 使用。将自行构建的 IPA 添加到 ATVLoadly 后，可以远程部署到 Apple TV；在 ATVLoadly 中配置有效的 Apple 签名账号或证书后，还可由 ATVLoadly 执行自动续签和重新部署，减少应用签名到期后的手动操作。

自动续签属于 ATVLoadly 的部署能力，并非 UZVideoTV 客户端自身功能。签名账号、证书、设备授权和续签周期请按 ATVLoadly 的说明配置，并妥善保护相关凭据。

## 数据与网络

收藏、播放历史、播放进度、视频源选择和播放器设置保存在设备本地的 `UserDefaults` 中。应用会根据用户操作访问以下第三方网络服务：

- 分享码解析服务：`api.616222.xyz`
- 推荐数据：豆瓣移动端接口
- 用户自行导入的视频源及其返回的媒体地址

请在使用前自行审查第三方接口、视频源及媒体内容的安全性、可用性和当地合规要求。

## 内容声明

本仓库只提供客户端源码，不包含任何媒体文件、视频源、订阅、分享码、账号凭据或签名 IPA。项目不托管、上传或分发影视内容，也不隶属于 Apple、豆瓣或任何第三方视频服务商。

使用者应仅接入自己有权访问的内容，并遵守所在地法律、服务条款和版权要求。第三方接口可能随时变更或停止服务。

## 开源许可

本仓库中由 jaxbot131 重新编写的 Apple tvOS 客户端代码使用 [MIT License](LICENSE) 开源。UZ 播放器原项目、名称、设计以及任何属于原作者或第三方的内容仍归各自权利人所有，MIT License 不对这些内容重新授权。详情见 [NOTICE](NOTICE)。
