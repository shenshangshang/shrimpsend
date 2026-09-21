# 现有页面与设计画板对应清单

日期：2026-09-21。用户已确认，Flutter、Web、官网及管理后台已按统一规范完成实现；鸿蒙不在本轮范围。

设计阶段盘点覆盖 24 个 Web 页面路由文件和 35 个 Flutter 页面/内部视图文件；实现新增的页面列在文末。17 张画板、69 个画面包含页面、弹层、跨端变体和状态；不表示 69 个互不重复的路由。页面容器、地区与语言变体共用对应模板。

## Web

| 当前页面文件 | 设计画板 |
| --- | --- |
| `web/src/app/(auth)/login/page.tsx` | [05 首次使用与账号](index.html#05-account) |
| `web/src/app/(auth)/register/page.tsx` | [05 首次使用与账号](index.html#05-account) |
| `web/src/app/[lang]/docs/[...slug]/page.tsx` | [11 官网、文档与法律页面](index.html#11-public) |
| `web/src/app/[lang]/page.tsx` | [11 官网、文档与法律页面](index.html#11-public) |
| `web/src/app/admin/page.tsx` | [12 管理后台](index.html#12-admin) |
| `web/src/app/admin/versions/page.tsx` | [12 管理后台](index.html#12-admin) |
| `web/src/app/authorize/page.tsx` | [03 本机授权](index.html#03-authorization)、[16 空状态与操作反馈](index.html#16-feedback) |
| `web/src/app/chat/page.tsx` | [00 传输首页](index.html#00-overview)、[01 连接设备](index.html#01-connect)、[13 移动端核心页面](index.html#13-mobile)、[14 连接与接收的关键状态](index.html#14-states) |
| `web/src/app/devices/page.tsx` | [01 连接设备](index.html#01-connect)、[04 会员与设备名额](index.html#04-membership)、[16 空状态与操作反馈](index.html#16-feedback) |
| `web/src/app/legal/cn/privacy/page.tsx` | [11 官网、文档与法律页面](index.html#11-public) |
| `web/src/app/legal/cn/terms/page.tsx` | [11 官网、文档与法律页面](index.html#11-public) |
| `web/src/app/legal/intl/[lang]/privacy/page.tsx` | [11 官网、文档与法律页面](index.html#11-public) |
| `web/src/app/legal/intl/[lang]/terms/page.tsx` | [11 官网、文档与法律页面](index.html#11-public) |
| `web/src/app/page.tsx` | [11 官网、文档与法律页面](index.html#11-public) |
| `web/src/app/search/page.tsx` | [02 文件与搜索](index.html#02-files) |
| `web/src/app/settings/about/page.tsx` | [10 帮助、更新与权益迁移](index.html#10-help) |
| `web/src/app/settings/account/page.tsx` | [05 首次使用与账号](index.html#05-account) |
| `web/src/app/settings/appearance/page.tsx` | [06 设置基础](index.html#06-settings)、[15 深色模式](index.html#15-dark) |
| `web/src/app/settings/fonts/page.tsx` | [07 偏好与存储连接](index.html#07-preferences) |
| `web/src/app/settings/language/page.tsx` | [06 设置基础](index.html#06-settings) |
| `web/src/app/settings/membership/page.tsx` | [04 会员与设备名额](index.html#04-membership)、[10 帮助、更新与权益迁移](index.html#10-help) |
| `web/src/app/settings/page.tsx` | [06 设置基础](index.html#06-settings) |
| `web/src/app/settings/s3/page.tsx` | [07 偏好与存储连接](index.html#07-preferences) |
| `web/src/app/settings/shortcuts/page.tsx` | [07 偏好与存储连接](index.html#07-preferences) |

## Flutter

| 当前页面或内部视图 | 设计画板 |
| --- | --- |
| `app/lib/screens/account_screen.dart` | [05 首次使用与账号](index.html#05-account) |
| `app/lib/screens/apk_picker_screen.dart` | [09 传输任务与辅助工具](index.html#09-tools) |
| `app/lib/screens/app_entry_screen.dart` | [05 首次使用与账号](index.html#05-account)、[01 连接设备](index.html#01-connect) |
| `app/lib/screens/app_log_screen.dart` | [09 传输任务与辅助工具](index.html#09-tools) |
| `app/lib/screens/chat_screen.dart` | [00 传输首页](index.html#00-overview)、[01 连接设备](index.html#01-connect)、[13 移动端核心页面](index.html#13-mobile)、[14 连接与接收的关键状态](index.html#14-states) |
| `app/lib/screens/device_authorization_screen.dart` | [03 本机授权](index.html#03-authorization)、[16 空状态与操作反馈](index.html#16-feedback) |
| `app/lib/screens/devices_screen.dart` | [01 连接设备](index.html#01-connect)、[04 会员与设备名额](index.html#04-membership)、[16 空状态与操作反馈](index.html#16-feedback) |
| `app/lib/screens/product_feedback_screen.dart` | [09 传输任务与辅助工具](index.html#09-tools) |
| `app/lib/screens/file_manager_screen.dart` | [02 文件与搜索](index.html#02-files)、[13 移动端核心页面](index.html#13-mobile) |
| `app/lib/screens/file_preview_screen.dart` | [02 文件与搜索](index.html#02-files) |
| `app/lib/screens/font_settings_screen.dart` | [07 偏好与存储连接](index.html#07-preferences) |
| `app/lib/screens/locale_region_gate_screen.dart` | [05 首次使用与账号](index.html#05-account)、[06 设置基础](index.html#06-settings) |
| `app/lib/screens/login_screen.dart` | [05 首次使用与账号](index.html#05-account) |
| `app/lib/screens/membership_migration_screen.dart` | [10 帮助、更新与权益迁移](index.html#10-help) |
| `app/lib/screens/membership_screen.dart` | [04 会员与设备名额](index.html#04-membership)、[10 帮助、更新与权益迁移](index.html#10-help) |
| `app/lib/screens/message_search_screen.dart` | [02 文件与搜索](index.html#02-files) |
| `app/lib/screens/qr_display_screen.dart` | [01 连接设备](index.html#01-connect)、[04 会员与设备名额](index.html#04-membership) |
| `app/lib/screens/qr_scanner_screen.dart` | [13 移动端核心页面](index.html#13-mobile) |
| `app/lib/screens/s3_settings_screen.dart` | [07 偏好与存储连接](index.html#07-preferences) |
| `app/lib/screens/settings_screen.dart` | [06 设置基础](index.html#06-settings)、[07 偏好与存储连接](index.html#07-preferences)、[10 帮助、更新与权益迁移](index.html#10-help)、[13 移动端核心页面](index.html#13-mobile) |
| `app/lib/screens/shortcut_settings_screen.dart` | [07 偏好与存储连接](index.html#07-preferences) |
| `app/lib/screens/version_history_screen.dart` | [10 帮助、更新与权益迁移](index.html#10-help) |
| `app/lib/screens/webdav/webdav_browsable_tab.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav/webdav_entry_actions.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav/webdav_entry_browser.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav/webdav_view_mode.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav_browser_screen.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav_connection_screen.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav_file_detail_screen.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav_files_tab.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav_recent_favorites_tab.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav_settings_screen.dart` | [07 偏好与存储连接](index.html#07-preferences) |
| `app/lib/screens/webdav_settings_tab.dart` | [07 偏好与存储连接](index.html#07-preferences) |
| `app/lib/screens/webdav_shell_screen.dart` | [08 WebDAV 云端文件](index.html#08-webdav) |
| `app/lib/screens/webdav_transfer_list_screen.dart` | [09 传输任务与辅助工具](index.html#09-tools) |

## 共用状态与边界

- 设备/文件为空、加载中：16；首次进入：01、05。
- 本地与跨网连接、单向访问、断线恢复、目录权限：14。
- 授权码过期、在线额度不足、会员到期：16、10。
- 文件重名、解除会员授权、移除传输连接：16。
- 核心手机页面与扫码：13；Android 安装包选择：09。
- 浅色和深色组件：00、06、15；其余页复用同一主题规范。
- 官网语言变体、文档不同文章、不同地区法律页面共用 11 的阅读模板；本轮不更改法律文案。
- `layout.tsx`、Flutter shell/tab/view helper 使用对应外层导航和内容样式，不作为额外独立用户页面。

页面均已落到产品代码。图片中的示例账号、价格、文件、二维码与订单不用于运行数据。浏览器目录权限、Android 安装包选择等按平台能力呈现。验证范围及未覆盖的外部环境见 `../../docs/testing/2026-09-21-redesign-implementation.md`。


## 实现新增入口

| 产品入口 | 页面 / 组件 | 对应画板 |
| --- | --- | --- |
| Web 文件六组 | `/files`、`/files/cloud`、`/files/recent`、`/files/favorites`、`/files/tasks`、`/files/connections` | 02、07、08、09 |
| Web 接收与保存 | `/settings/receiving` | 06、14 |
| Web 帮助详情 | `/settings/help/versions`、`/settings/help/feedback`、`/settings/help/logs` | 09、10 |
| Flutter 连接设置 | `app/lib/screens/file_connections_screen.dart` | 07、08 |
| Flutter 统一传输任务 | `app/lib/screens/transfer_activity_screen.dart` | 09、14 |
| Flutter 本机反馈草稿 | `app/lib/screens/product_feedback_screen.dart` | 09 |
| 两端订单列表 / 详情 | `OrderHistory.tsx`、`membership_order_history.dart`，在会员页「订单」中打开 | 04 |

原 `feedmatter_feedback_screen.dart` 保留兼容入口，新界面使用本机反馈草稿。登录、扫码和文件预览等专注场景允许独立布局；其余页面共享三入口导航。
