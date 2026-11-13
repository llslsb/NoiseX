# NoiseX

> 反算法的随机社交应用 · 贯一出品

NoiseX 是一款实验性的随机社交应用：没有推荐、没有排行、没有用户画像，匹配只看空间与时间。

- **声呐**：发出一个不超过 140 字的随机问题，进入随机池，等待附近的人拾起。
- **接收器**：打开收听模式，接收附近（约 1 公里内优先，逐步扩展）的声呐，响应即进入对话。
- **72 小时沙漏**：匹配成功进入仅存活 72 小时的匿名对话房间——没有昵称头像，只有随机信号代号（如 RX-4711）；到期后房间与对话在服务器和本机一并清除。
- **三条原则**：反算法（只依赖时空坐标）、反囤积（关系自然消亡）、反表演（无粉丝数、无历史动态）。

## ⚠️ 当前状态（先读这段）

- **官方托管服务已停止运营**，本仓库按「原样」（AS IS）开源，仅供学习与自建。
- 应用是强联网产品，**必须自建后端才能使用**（教程见下）。
- 如你在境内对公众提供服务，备案等合规手续需自行办理，责任自负。

## 架构

```
noisex/
├── flutter_app_home/flutter_app/   # Flutter 双端工程（Android APK + 鸿蒙 HAP，业务全 Dart 共享）
├── harmonyos_app/noisex/           # 纯 ArkTS 鸿蒙工程（早期版本，仅存档参考）
└── java_server/                    # 后端：Java / Spring Boot + MySQL + Redis + WebSocket
.github/workflows/ci.yml            # 后端测试流水线
```

聊天内容端到端加密：服务器只转发与暂存密文，72 小时后销毁。安全设计细节见 [AGENTS.md](AGENTS.md)。

## 快速开始（自建后端）

```bash
cd noisex/java_server
cp .env.example .env        # 逐项填写密码与密钥
docker compose up -d        # 服务监听 7070
```

客户端默认指向本机后端（`lib/models/constants.dart`）：Android 模拟器用 `http://10.0.2.2:7070`；自建域名后改成你的地址，REST 与 WebSocket 同域（建议 Nginx TLS 反代到 127.0.0.1:7070）。

## 构建客户端

完整构建命令、环境变量、签名说明见 [AGENTS.md](AGENTS.md)。要点：

- Android：`flutter build apk --release`（自有 keystore 通过 `android/key.properties` 注入，开发者自备；不配则退回 debug 签名）
- 鸿蒙：两步走——`flutter build hap` 出 Dart 产物，再用 DevEco 的 `hvigorw assembleHap` 出包

## 厂商推送（可选）

- `agconnect-services.json` 含账号级密钥，**不随仓库分发**：需要推送时，从你自己的 AppGallery Connect 控制台下载后放到 `flutter_app/android/app/` 下。
- 服务端推送密钥放 `.env` 的 `PUSH_CLIENT_SECRET`；不配置只影响离线时的推送提醒，应用内功能不受影响。

## License

[MIT](LICENSE) © 2026 李龙生

MIT 授权不包含「NoiseX」名称与「贯一」品牌的使用权。
