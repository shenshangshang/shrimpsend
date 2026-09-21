# 虾传 文件传输协议

用户只选「发给谁」，发送时按速度从快到慢探测：HTTP 直推 → HTTP 反向拉取 → WebRTC → S3（仅登录）。浏览器没有 LAN HTTP 服务：Web→App 只直推，App→Web 只反向拉，Web→Web 跳过 HTTP。未登录同样走 HTTP，只是没有 S3。

## HTTP 直传（LAN）

### 直推 (Direct Push)

- `POST /transfer`
  - Headers: `X-File-Name`, `X-File-Size`, `Content-Type: application/octet-stream`
  - 断点续传 Headers (可选): `X-File-Id`, `X-Resume-Offset`
  - Body: 原始文件内容（从 offset 开始）

### 反向拉取 (Reverse Pull)

- `GET /download?offerId=xxx`
  - 支持 `Range: bytes=start-` 请求头进行续传
  - 返回 `206 Partial Content` + `Content-Range` 头
  - 发送端通过云信令 `lan_file_offer` 通知接收端拉取 URL；信封必须带 `toDeviceId`（未登录走 `device-send`，登录账号对网页/访客还要定向发到对端 device channel）
  - LAN HTTP CORS 含 `Access-Control-Allow-Private-Network: true`，否则浏览器从 HTTPS/localhost 拉局域网地址会被预检拦下

### 探测

- `GET /probe` → 200 OK

### 续传状态查询

- `GET /transfer-status?fileId=xxx`
  - 返回 `X-Received-Bytes` 头和已接收字节数
  - `fileId` 由 `hash(fileName)_fileSize` 生成

## S3 云存储传输

### 小文件 (< 5MB)

- `POST /api/s3/presign-upload` → 获取预签名 PUT URL
- `PUT` 预签名 URL 上传
- `GET /api/s3/download-url?key=xxx` → 获取预签名 GET URL

### 大文件 Multipart Upload (≥ 5MB, 支持断点续传)

- `POST /api/s3/multipart/initiate` → 创建分片上传，返回 `uploadId` + `key`
- `POST /api/s3/multipart/presign-part` → 为单个分片生成预签名 URL
- `PUT` 预签名 URL 上传分片，获取 ETag
- `POST /api/s3/multipart/complete` → 提交已完成分片列表，合并文件
- `POST /api/s3/multipart/abort` → 取消分片上传（可选）

下载续传：使用 HTTP `Range: bytes=offset-` 请求头

## WebRTC P2P 传输

### 信令

通过实时控制面发送：`webrtc_offer`, `webrtc_answer`, `webrtc_ice_candidate`, `webrtc_transfer_cancel`

### DataChannel

- `control`: JSON 控制消息
- `file-{fileId}`: 每个文件一个 DataChannel，16KB 分块

### 控制消息类型

| 类型 | 方向 | 说明 |
|------|------|------|
| `file_start` | 发送→接收 | 文件开始，含 fileId, fileName, fileSize, mimeType |
| `file_end` | 发送→接收 | 文件数据发送完成 |
| `file_ack` | 接收→发送 | 文件接收确认 |
| `progress` | 接收→发送 | 已接收字节数（用于端到端流控） |
| `file_resume_request` | 接收→发送 | 断点续传请求，含 fileId, receivedBytes |
| `file_resume_accept` | 发送→接收 | 断点续传确认，含 fileId, offset |
| `session_complete` | 发送→接收 | 会话内所有文件发送完成 |

### 断点续传流程

1. 接收端在 `file_start` 后检查本地是否有部分接收的临时文件
2. 如有，发送 `file_resume_request` 告知已接收字节数
3. 发送端收到后发送 `file_resume_accept` 确认，从 offset 开始发送
4. 接收端的部分数据定期 flush 到磁盘临时文件（每 ~2MB）

## 文件完整性校验

- 上传前计算文件 SHA-256 hash
- 通过 `X-File-Hash` 头传输（LAN 场景）
- S3 场景可用 ETag 校验
- 传输完成后接收端可校验 hash 一致性

## 2026-09 设备授权与传输身份

- 账号仅购买和管理设备服务名额。传输使用 `/api/realtime/device-session` 签发的 `device_access` JWT；授权码不得用作请求令牌。
- `/api/messages/device-send` 和兼容 URL `/api/messages/send` 均要求设备 JWT；`/api/mailbox/pending` 仅允许读取 JWT 对应的 `deviceId`。旧账号 JWT 不再能投递文件或领取其他设备的实时令牌。
- 新的 1:1 `threadKey` 为 `device|d1:<按字典排序较小ID>|d2:<较大ID>`，不包含购买账号。消息必须定向到设备，先验证配对；授权归属不会自动建立配对。
- `/api/devices/paired` 使用设备 JWT 列出配对；`DELETE /api/devices/paired/{peer}` 解除配对，独立于设备会员授权和账号退出。
- 本机状态 `GET /api/device-licenses/me`；激活 `POST /api/device-licenses/redeem`，请求包含 `code` 或 `qrToken`，以及本机备注和平台。六位码等待购买者确认；二维码为高强度一次性凭证。
- 购买者接口、名额规则和兼容迁移详见 [设备授权实现](../docs/DEVICE_LICENSES.md)。
