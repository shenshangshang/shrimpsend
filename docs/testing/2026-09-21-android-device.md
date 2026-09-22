# Android 真机验证（2026-09-21）

## 环境与启动

- Xiaomi 25113PN0EC，Android 16 / API 36，arm64，通过 USB 调试连接。
- Android 本地包：`dev.ultrasend.app.local`；Mac 使用本地 Flutter 客户端；Web 使用 `http://localhost:3000/chat`。
- API / 信令通过 USB 端口转发访问本机 Docker 服务；文件通过手机与 Mac 的真实局域网地址传输。
- Android 默认接收位置为 `/storage/emulated/0/Download`；Mac 保留用户已选目录 `/Users/chengming/Documents/calshot`。
- 启动入口：`FLUTTER_BIN=/Users/chengming/dev/flutter/bin/flutter ./scripts/flutter-local.sh android`，配置集中在忽略的 `.local/flutter.json`。
- 最终普通 Android 和 Mac 客户端已启动，API / 信令端口转发已恢复。

## 已修复的问题

1. **默认 Downloads 无法直接写入及完成路径错误。** Android 11+ 通过 MediaStore 创建本应用拥有的待完成文件，传输内容由 Dart 直接写入该目标，完成并核验长度后发布。系统发布时会改变文件路径，现在重新读取最终路径后再记录文件、确认接收；默认流程不再复制一份缓存文件。重复完成请求保持幂等。
2. **断流后文件句柄未可靠关闭。** HTTP 接收在异常退出时也刷新并关闭文件，恢复查询能看到实际已落盘偏移，避免丢失断点或残留占用。
3. **启动时重复连接。** Android 生命周期恢复和网络事件曾打断尚未完成的 WebSocket 握手；现在已有连接请求进行时复用该过程。
4. **离线时自动配对异常反复冒泡。** 自动发现触发的后台配对现在合并并发请求，成功短期复用，失败冷却重试并捕获异常；显式配对保留错误反馈，设置请求超时。
5. **Android 设备图标。** 本机设备按实际平台显示手机图标。
6. **本地安装保护。** Debug 增加独立应用 ID；脚本先构建、执行 `adb install -r`，成功后才启动 Flutter。签名不兼容直接失败，避免 Flutter 自动卸载回退。

## 实际测试结果

| 场景 | 结果与证据 |
|---|---|
| Android 页面 | 真机集成测试遍历并截图 14 个主要页面，无布局异常；截图位于 `.local/android-qa/android-qa/` |
| Android → Mac | 实际输入并发送文本；HTTP 发送 1 MiB 文件；另外通过真实 WebRTC 会话发送 3 MiB，收到接收确认，内容与预期字节一致 |
| Mac → Android | 实际输入并发送文本；真实 WebRTC 发送 5 MiB，手机处于后台仍成功接收并确认，文件哈希一致 |
| Web → Android | 浏览器操作发送文本及 42,000 字节文件，页面显示已发送；手机 Downloads 文件与发送源 SHA-256 一致 |
| 默认接收目录 | MediaStore 创建、写入、查询断点、发布、读取最终路径及重复完成通过；接收数据库记录为 done，直接下载记录无缓存路径 |
| HTTP 中断续传 | 主动断开 TCP，保留 1 MiB 前缀，再次请求从断点完成 4 MiB 文件；前台与后台均校验通过 |
| 服务不可达时续传 | 移除 API / 信令转发并重启 Flutter 运行时，64 MiB 文件保留的 1 MiB 断点仍可查询，通过 LAN 完成剩余数据并校验哈希 |
| 连接恢复 | 恢复转发后自动连接并恢复在线；最终运行时重启之后未发现未捕获异常 |
| 保留数据安装 | 最终使用安全脚本安装、启动成功，当前独立测试包的设备 ID 和已有接收文件保留 |

64 MiB 测试的剩余 63 MiB 从请求到完成耗时 **2.612 秒，约 24.12 MiB/s**，不含事后通过 USB 读取文件做哈希校验的时间。该数据仅代表本次局域网条件，不作为其他网络的速度保证。文件 SHA-256：`281e519df3077b557c6b03f5da83c4e8d397219259615dd7c3308f89cae8f2a6`。记录：`.local/android-restart-resume.json`。

## 自动化验证

- 29 项回归测试通过，覆盖后台配对合并与冷却、启动连接竞争、传输确认、文件导出及存储、HTTP 服务绑定、设备详情和 WebDAV。
- Android 真机集成测试通过：`app/integration_test/android_device_test.dart`。
- Mac 对 Android 的原生集成测试通过：`app/integration_test/native_peer_transfer_test.dart`。
- 修改范围静态检查无 error / warning，存在少量 info 级提示；本地启动脚本语法检查和差异空白检查通过。
- 可复用 LAN 中断续传检查：`scripts/smoke-native-lan.py`，支持指定 Android 设备读取实际接收文件并校验，以及调整测试文件大小。
- 日志位于 `.local/android-regression-final.log`、`.local/android-integration-final.log`、`.local/mac-android-integration.log`、`.local/android-normal-final.log`，不提交含本地设备资料的原始运行产物。

## 尚未覆盖的边界

- Android 10 及以下和用户选择的 SAF 文档目录仍使用原暂存后导出流程；本轮直写修复限定 Android 11+ 默认 Downloads。
- 重启续传测试为 Flutter 运行时重启，未模拟完整 Android 进程被系统杀死、手机重启或存储空间耗尽。
- 未模拟全部厂商省电限制、蜂窝网络切换和跨公网 NAT。后台测试仅代表当前 Xiaomi 设置。
- S3 接收已接入同一目标文件适配，但没有配置云端凭据做真机端到端测试；WebDAV 的相关回归通过，未在 Android 自定义文档目录实测。
- 文件长度检查和测试时哈希比对均已完成；不要将测试中的哈希验证描述为所有传输协议都已实现端到端哈希校验。

## 安装异常记录

首次启动时，手机原有 `dev.ultrasend.app` 调试包与本机构建签名不一致。Flutter 安装失败后自动卸载旧包，并在重装时被系统 USB 安装限制拦截；已确认旧包当时被移除，旧应用内数据可能已清除，未恢复旧包数据。该情况已向用户说明。

随后改用 `dev.ultrasend.app.local` 独立测试包，并增加上述先安装检查、失败即中止的启动流程。最终安装验证保留的是这个新测试包的数据，不能据此推断旧包数据已保留或恢复。
