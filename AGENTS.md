# AGENTS.md

> NoiseX 项目 · AI 助手通用操作手册(工具无关)
>
> 本文件遵循 [agents.md 约定](https://agents.md/),适用于 Claude Code / Codex / Cursor / Aider / 任何遵循该约定的 AI 助手。
> Claude Code 私有扩展见同目录 [`CLAUDE.md`](CLAUDE.md)。

---

## 1. 项目定位

NoiseX 是一款基于地理位置 + 时间的**反算法、反囤积、反表演、反追踪**匿名社交应用。

- **后端**:Spring Boot 3.2.5 (Java 17),应用端口 `7070`
- **客户端 A**:HarmonyOS NEXT (ArkTS,API 12+)
- **客户端 B**:Flutter (Dart 3.0+,Android / iOS / OpenHarmony)
- **数据**:MySQL 8.0 + Redis 7.0(必须启用 `notify-keyspace-events Ex`)

> 完整产品愿景见 [`noisex/01-项目概述.md`](noisex/01-项目概述.md)。

---

## 2. 仓库结构

```
NoiseX/
├── AGENTS.md                              # 本文件
├── CLAUDE.md                              # Claude Code 私有规则
├── noisex/
│   ├── 01-项目概述.md ~ 09-业务技术文档.md   # 9 篇主文档
│   ├── ADMIN_GUIDE.md                     # 管理后台
│   ├── DEPLOYMENT.md                      # 部署快查
│   ├── java_server/                       # Spring Boot 后端
│   │   ├── CLAUDE.md                      # 后端专用约束
│   │   ├── 启动部署指南.md
│   │   └── src/main/resources/
│   │       ├── application.yml            # 默认配置(server.port=7070)
│   │       ├── application-dev.yml        # 开发覆盖(JWT 内置 / ddl-auto=none)
│   │       └── db/migration/V1~V8__*.sql  # Flyway 迁移
│   ├── harmonyos_app/noisex/              # 鸿蒙端
│   │   ├── CLAUDE.md
│   │   └── entry/src/main/ets/model/Constants.ets   # 后端地址 + 阈值
│   └── flutter_app_home/flutter_app/      # Flutter 端
│       ├── CLAUDE.md
│       └── lib/models/constants.dart      # 后端地址 + 阈值
├── 一、NOSIX当前聊天房间生命周期.md
└── 二、举报提交后在哪看、官方人员怎么查看.md
```

---

## 3. 高频命令

### 3.1 后端 (`noisex/java_server`)

```bash
mvn compile                       # 编译
mvn test                          # 单测(自动排除 e2e 组)
mvn test -Dtest=AuthServiceTest   # 单类测试
mvn test -P e2e                   # E2E(需服务运行)
mvn clean package -DskipTests     # 构建 JAR
mvn spotless:check                # 格式检查
mvn spotless:apply                # 自动格式化

# Docker 一键启动(MySQL + Redis + App + Nginx)
docker compose up -d

# 仅基础设施(IDE 调试用)
docker compose up -d mysql redis
```

环境变量必填项:`JWT_SECRET`(dev profile 有内置开发密钥可省)、`DB_PASSWORD`、`ENCRYPTION_KEY`(≥32 字节,无默认)。

### 3.2 鸿蒙端 (`noisex/harmonyos_app/noisex`)

```bash
ohpm install --all
hvigorw assembleHap --mode module -p module=entry@default
```

DevEco Studio 5.0+ 直接 Run。**项目路径不能含中文/括号/空格**。

### 3.3 Flutter 端 (`noisex/flutter_app_home/flutter_app`)

```bash
flutter pub get
flutter test
flutter analyze
flutter run                       # 当前选中设备
flutter build apk --debug
```

---

## 4. 关键约束(违反 = 拒收)

### 4.1 产品理念(Layer 1)

- **反算法**:无推荐、无排序、无用户画像、无兴趣标签、无粉丝关注
- **反囤积**:关系 72h 自然风干,除非双方主动保存
- **反表演**:无头像、无动态、无个人主页、无声望
- **反追踪**:不收集设备指纹、不做行为分析、不保留历史

### 4.2 安全红线

- ❌ 硬编码密钥、密码、令牌
- ❌ 记录明文 JWT、手机号、推送 token
- ❌ `/api/admin/**` 缺少 `ROLE_ADMIN` 保护
- ❌ 未参数化 SQL、未校验输入、错误暴露堆栈
- ❌ 读取 `~/.ssh/**`、`~/.aws/**`、`*.env`

### 4.3 三端同步

修改 WebSocket payload / DTO / API 接口时,**必须同时**更新:

- 后端 `NoiseXWebSocketHandler.java` + 相关 DTO
- 鸿蒙 `entry/src/main/ets/service/WsService.ets` + `ApiTypes.ets`
- Flutter `lib/services/ws_service.dart` + models
- 相关单元测试

---

## 5. 产品口径速查

| 口径 | 值 | 配置位置 |
|------|---|---------|
| 应用端口 | 7070 | `application.yml: server.port` |
| 房间寿命 | 72h | `unlock-window-hours` / Redis TTL |
| 解锁窗口 | 前 24h | 客户端 UI + 后端配置 |
| 临终保存入口 | 最后 12h(UI 控制) | 后端不校验时间窗 |
| 深度交流阈值 | 总数 ≥20、双方各 ≥5、单条 ≥5 字符 | `unlock-threshold-messages` |
| 连续发送上限 | 5 条(对方回复后重置) | 双端 4 提醒 / 5 拦截 |
| 声呐限流 | 生产 3 次/小时,dev 100 次 | `sonar.max-per-hour` |
| 普通 JWT 有效期 | 24h | `noisex.jwt.expiration=86400000` |
| 管理员 JWT | 2h | `noisex.admin.jwt-expiration=7200000` |
| 管理员登录限流 | 15 min / 5 次,按 IP+username 双维度 | Redis `noisex:rate:admin_login:<ip>:<userHash>` |
| 封禁(banned) | 关房清数据 + 双方 JWT 拉黑 + **7 天临时封禁标记**(到期自动解封) + 踢 WS;补偿单可重试补齐 | `AdminService.banRoom` / `noisex:user:banned:{uid}` |
| 弹窗动画 | 250ms + 标准缓动 | 双端视觉一致 |
| Geohash 精度 | 6 | `defaultGeohashPrecision` |
| 匹配范围 | 同格 ~1km 优先 → ~5km → 同城 ~20km 封顶 | `noisex.match.max-expand-level=2` |
| 首启协议门 | 首启弹《用户协议》《隐私政策》,同意才可用;同意前零采集 | 双端启动链路(privacy_agreed_v1) |
| Signal Code | `RX-XXXX`(1000–9999) | `ChatService.java` |

---

## 6. 数据存储

| 类型 | 存储 | 生命周期 | 表/Key |
|------|------|---------|--------|
| 永久 | MySQL | 主动删除 | `user_profile`, `saved_connection`, `report`, `user_block`, `saved_moment`, `admin_account`, `pending_compensation` |
| 临时 | Redis(TTL) | 72h 自动过期 | 房间、消息、声呐、匹配队列(具体 key 见 `RedisKeys.java`) |
| 加密 | AES-256-GCM | — | `report.phone_number`、E2EE 共享密钥 |

Flyway 迁移已交付 V1–V8,任何 schema 变更**只增加新版本文件**,不改历史脚本。

---

## 7. 编码标准

- 函数 ≤ 50 行,文件 ≤ 800 行,嵌套 ≤ 4 层
- 测试覆盖率 ≥ 80%
- 错误显式处理:不吞异常、不藏默认值
- 注释用中文(开源场景例外)
- 提交格式:`<类型>: <描述>` (feat/fix/refactor/docs/test/chore/perf/ci)
- 不主动 `git push --force` 到 main/master

---

## 8. 何时读哪份文档

| 你要做的事 | 先读 |
|-----------|------|
| 了解产品全貌 | [`noisex/01-项目概述.md`](noisex/01-项目概述.md) |
| 看系统拓扑/技术架构 | [`noisex/02-技术架构.md`](noisex/02-技术架构.md) |
| 修客户端代码 | [`noisex/03-客户端开发文档.md`](noisex/03-客户端开发文档.md) + 子目录 CLAUDE.md |
| 修后端代码 | [`noisex/04-后端开发文档.md`](noisex/04-后端开发文档.md) + [`noisex/java_server/CLAUDE.md`](noisex/java_server/CLAUDE.md) |
| 调用/扩展 API | [`noisex/05-API接口文档.md`](noisex/05-API接口文档.md) |
| 改表/Redis key | [`noisex/06-数据模型设计.md`](noisex/06-数据模型设计.md) |
| 部署到服务器 | [`noisex/07-部署与运维.md`](noisex/07-部署与运维.md) + [`noisex/DEPLOYMENT.md`](noisex/DEPLOYMENT.md) |
| 本地搭环境 | [`noisex/08-本地开发环境搭建指南.md`](noisex/08-本地开发环境搭建指南.md) |
| 理解业务流程 | [`noisex/09-业务技术文档.md`](noisex/09-业务技术文档.md) + [`一、NOSIX当前聊天房间生命周期.md`](一、NOSIX当前聊天房间生命周期.md) |
| 管理后台/审核 | [`noisex/ADMIN_GUIDE.md`](noisex/ADMIN_GUIDE.md) + [`二、举报提交后在哪看、官方人员怎么查看.md`](二、举报提交后在哪看、官方人员怎么查看.md) |
| 新会话接手本项目 | [`三、新会话接续提示词.md`](三、新会话接续提示词.md) |
| 双端联调/发布核对 | [`docs/双端联调测试手册.md`](docs/双端联调测试手册.md) + [`docs/生产就绪清单.md`](docs/生产就绪清单.md) |
| 上架资料 | [`docs/AGC资料-*.md`](docs/) |
| 华为 AGC 上架全流程（安卓 APK/鸿蒙 HAP，跨项目通用操作手册） | [`docs/AGC上架全流程指南-安卓与鸿蒙.md`](docs/AGC上架全流程指南-安卓与鸿蒙.md) |
