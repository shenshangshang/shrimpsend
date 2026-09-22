# 本机 Docker 部署

本机配置：仓库根目录 `.env.local-deploy`，文件权限 `0600`，已被 Git 忽略。数据库密码、JWT 和加密密钥独立随机生成，不要删除后重新生成密钥再复用旧数据卷。

## 地址

- Web：<http://localhost:3000/chat>
- 后端健康检查：<http://localhost:9000/>
- 悟空 IM WebSocket：`ws://localhost:5200`

服务端口仅绑定 `127.0.0.1`；当前供这台电脑访问。MySQL 与 IM 管理 API 不映射到宿主机。手机或其他电脑访问需要另行配置局域网地址。

## 启停

```bash
# Docker 虚拟机已安装并创建；重启电脑后先启动它。
colima start shrimpsend

# 查看 / 启动已有镜像（首次构建已执行后适用）
./scripts/deploy-docker-local.sh status
./scripts/deploy-docker-local.sh apply

# 代码或 NEXT_PUBLIC_* 配置变化：重新构建并启动
./scripts/deploy-docker-local.sh up

# 查看日志 / 停止容器（保留数据）
./scripts/deploy-docker-local.sh logs backend
./scripts/deploy-docker-local.sh stop

# 暂时不用时释放虚拟机内存，磁盘数据保留
colima stop shrimpsend
```

本地入口固定使用 `colima-shrimpsend` Docker context，避免全局 context 切换后误操作其他 Docker 服务。需要使用其他本机引擎时显式指定 `LOCAL_DOCKER_CONTEXT`。项目名为 `shrimpsend-local`，数据卷为 `shrimpsend-local_mysql_data` 和 `shrimpsend-local_wukongim_data`。

## 配置和依赖

- `.env.local-deploy`：唯一需要人工修改的本地应用配置；沿用 `compose.production.yml` 的四容器拓扑，使用 `prod` profile 验证国内生产逻辑。
- `scripts/deploy-docker-local.sh`：选择本地配置、Docker context；在 macOS 上沿用系统已配置的 HTTP(S) 代理供镜像构建访问。
- Colima 虚拟机：4 核、8 GiB 内存、40 GiB 数据磁盘；按需启动，不注册开机自启。
- Docker CLI、Compose、Buildx：使用 Docker 官方发布的二进制；Colima/Lima 通过 Homebrew 安装。
- 本机代理：已有系统代理 `127.0.0.1:7897`；Docker VM / 构建访问对应网关 `192.168.5.2:7897`。Docker client 中的代理设置只针对本项目 daemon。若代理端口改变，需同步修改本机 Colima 配置和 `~/.docker/config.json` 中对应 daemon 的代理配置。

邮件、短信、支付、S3 未填写第三方凭据，因此先验证游客配对及 HTTP / WebRTC 互传。需要测试相应集成时，将自己的测试凭据填入本地配置，运行 `apply`；修改 Web 公开变量则运行 `up`。

完整部署参数和旧实例迁移规则见 [SELF_HOST.md](SELF_HOST.md)。

## 验证结果（2026-09-20）

四个服务均通过 Docker 健康检查。`/chat`、API 根路径、`/zh/docs/intro` 均返回 HTTP 200；浏览器游客设备连接成功并显示“在线”。已完成双 Web 文字 / WebRTC 文件、Web → macOS HTTP 文件、离线文字与真实中断续传验证。邮件、支付、云存储尚未配置测试凭据。完整记录见 [本地验证报告](testing/2026-09-20-local-validation.md)。

## Flutter macOS 本地端

```bash
FLUTTER_BIN=/Users/chengming/dev/flutter/bin/flutter ./scripts/flutter-local.sh run --no-pub
```

运行配置独立放在 `.local/flutter.json`，首次由 `app/config/local.example.json` 生成。可修改 `API_URL`、`WUKONGIM_WS` 和本地设备命名空间。Debug 应用标识为 `dev.ultrasend.app.local`，与已安装正式版的数据分开；构建产物在 `app/build/macos/Build/Products/Debug/Shrimpsend.app`。

本机已准备 Flutter 3.41.3、macOS 插件和依赖。鸿蒙 Git 依赖通过忽略的 `app/pubspec_overrides.yaml` 指向 `.local/flutter-deps/` 的浅克隆，以避开上游仓库完整克隆失败；这些本机路径没有写入正式依赖锁。换机器时先准备 Flutter 依赖，再运行本地入口。空第三方密钥模板只用于本地启动，不会伪造邮件、分析或支付服务。

桌面接收默认 `/Users/<当前用户>/Downloads`；在客户端设置中可选择目录。未完成传输的部分文件也保存在目标目录，方便续传；完成后不再复制到第二个目录。

## Flutter Android 本地端

手机连接 USB 并允许调试后运行：

```bash
FLUTTER_BIN=/Users/chengming/dev/flutter/bin/flutter ./scripts/flutter-local.sh android
```

同样读取 `.local/flutter.json`。脚本将手机的 9000、5200、3000 端口转发到电脑，本地 API 和信令不必暴露给整个局域网；文件直传仍使用手机与电脑的真实局域网地址。多台手机时用 `FLUTTER_DEVICE` 指定设备编号。

Android Debug 使用 `dev.ultrasend.app.local`，与发行包分开安装。首次安装需在手机上允许 USB 安装；不要为解决签名冲突卸载已有发行包。拔掉 USB 后本地信令不可达，局域网直传仍可用；重新连接后再次运行脚本恢复端口转发。

Android 11 及以上的默认接收目录通过系统 Downloads 创建目标文件，数据直接写入该目标，完成前保持待完成状态，完成后使用系统返回的最终路径。Android 10 及以下和自定义文档目录目前仍先暂存、再通过文档接口导出；这些兼容场景尚未实现直接写入目标目录。

## 设备授权配置

本地已配置独立 `DEVICE_LICENSE_SECRET` 与发行前缀 `L`；不要随 JWT 轮换或丢弃已用码指纹。有效期和换机频率可在 `.env.local-deploy` 调整。Flutter 的授权链接站点由 `.local/flutter.json` 的 `WEB_URL` 指定。本机 `/authorize` 可免登录授权，购买者在 `/settings/membership` 管理名额。详见 [设备授权](DEVICE_LICENSES.md)。
