# HarmonyOS (Flutter ohos)

虾传鸿蒙端走 **现有 Flutter 工程** 的 `ohos/` 平台，不再扩展 [`app_ohos/`](../../app_ohos/) ArkTS 客户端。

## SDK

使用社区 OpenHarmony Flutter SDK（与官方 Android/iOS SDK **分开**）。本仓库验证过的版本：

`Flutter 3.41.10-ohos-1.0.1`（`/Users/cmlanche/sourcetree/flutter_flutter`）

```bash
export PATH="/Users/cmlanche/sourcetree/flutter_flutter/bin:$PATH"
cd app
flutter --version   # 期望 3.41.x-ohos
flutter devices            # hdc 无设备时列表为空，需先 USB 调试真机
flutter run -d <ohos-device>
# 或
flutter build hap --debug --target-platform ohos-arm64
```

签名：把 DevEco 的 `build-profile.json5` 签名段拷进本目录（可参考 ops 仓 `harmonyos/`）。`local.properties` 指向 DevEco SDK，已 gitignore。

```
hwsdk.dir=/Applications/DevEco-Studio.app/Contents/sdk
```

## 能力分层

悟空 JSON-RPC / 登录 / 文字聊天 / S3 云传：纯 Dart，鸿蒙直接复用。

当前 **关掉**（待社区插件）：

- mDNS（bonsoir）
- WebRTC（flutter_webrtc）
- 系统分享入站
- 原生应用内购（RevenueCat / 支付宝 SDK）
- 相册 photo_manager、APK 安装

鸿蒙先走 **账号 + 悟空 + S3/云中继**；局域网 HTTP 服务仍尝试 `dart:io`，发现需手动填 IP。

## 依赖：一份 pubspec，不用换来换去

大家**不是**打包前改依赖、打完再改回去。联邦插件的做法是：

- `path_provider` 等 **主包仍用 pub.dev**（Android / iOS / 桌面）
- 另外再声明 `path_provider_ohos` 等 **ohos 实现包**
- 官方 Flutter 看不到 `ohos` 平台就跳过；鸿蒙 SDK 会注册它们
- 一次 `flutter pub get` 两边都能用

已经写在 [`pubspec.yaml`](../pubspec.yaml) 里，不要覆盖主包、也不要跑切换脚本。

缺鸿蒙实现的插件（bonsoir、WebRTC、内购…）保持原依赖，HAP 链接跳过，运行时 [`OhosCapabilities`](../lib/utils/runtime_platform.dart) 门控。

只有一种情况才需要 vendor 成本地 path：Hvigor 报 `srcPath` 必须相对路径（git 缓存在用户目录是绝对路径）。那时把 TPC 包放进仓库 `third_party/`，仍是一份 pubspec。

可选更激进：团队只用鸿蒙 Flutter SDK 打全平台（3.41-ohos 接近官方 3.41）。能省一个 SDK，但 Android/iOS 要单独验收，这里不默认这么做。

TPC：[flutter_packages](https://gitcode.com/openharmony-tpc/flutter_packages) · [plus_plugins](https://gitcode.com/openharmony-tpc/flutter_plus_plugins) · [CPF-Flutter packages](https://gitcode.com/CPF-Flutter/flutter_packages)

## 插件覆盖（Spike）

| 能力 | 插件 | 鸿蒙 |
|------|------|------|
| HTTP / WS | `http`, `web_socket_channel` | 纯 Dart，可用 |
| 悟空 | `wukongim_jsonrpc.dart` | 纯 Dart，可用 |
| 偏好 / 路径 / sqlite | shared_preferences, path_provider, sqflite | 需社区 ohos 实现；构建时由 Flutter 工具注入 |
| 安全存储 | flutter_secure_storage | 同上 |
| 设备信息 | device_info_plus | 有 ohos 子包则用，否则 UUID |
| mDNS | bonsoir | 无，已门控 |
| WebRTC | flutter_webrtc | 无，已门控，走 S3 |
| 相册 | photo_manager / wechat_assets_picker | 无，改 file_picker |
| 分享 | flutter_sharing_intent / fl_shared_link | 无，已跳过 |
| IAP | purchases_flutter / tobias | 无，走网页支付 |
| APK | installed_apps | Android only |

`Platform.operatingSystem` 在社区引擎上为 `ohos`；业务层统一成 `harmonyos`（见 `RuntimePlatform.osName`）。
