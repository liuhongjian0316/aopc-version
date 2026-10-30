# aopc-version 更新发布仓库

本仓库只承载 AOPC 桌面客户端的**更新发布**：安装包与 electron-updater manifest 通过 GitHub Releases 分发（`releases/latest/download/...` 恒指向最新版）。git 里只保存发布脚本与说明。

## 打包指令

前置：`gh auth login`（一次即可），AOPC 项目可构建。

**一键发版（构建 + 发布，推荐）：**

```bash
AOPC_APP_VERSION=0.0.3 npm run release          # 构建版本号 0.0.3 的包并发布到 GitHub Releases
AOPC_APP_VERSION=0.0.3 npm run release NOTES="更新说明"  # 带发布说明
```

**只构建不发布：**

```bash
AOPC_APP_VERSION=0.0.3 npm run build   # 产物在 ../AOPC/packages/desktop/dist
./publish-update.sh --dry-run          # 发布前校验，不上传
npm run publish                        # 校验并发布到 GitHub Releases
```

**在 AOPC 仓库直接打包（与本仓库 build 等效，feed 已默认烘焙）：**

```bash
cd ../AOPC/packages/desktop
AOPC_ENV=production AOPC_APP_VERSION=0.0.3 pnpm bundle
```

不带 `AOPC_ENV=production` 会产出 `AOPC Preview-…-TEST` 测试包，不能用于发布。

## 环境变量

| 变量 | 作用 | 默认 |
| --- | --- | --- |
| `AOPC_APP_VERSION` | 抬安装包版本号（客户端按它判更新） | AOPC 根 package.json 的 version |
| `AOPC_UPDATE_FEED_URL` | 更新源，支持完整 URL 或 `owner/repo` 简写 | `liuhongjian0316/aopc-version`（已默认烘焙） |
| `AOPC_AUTO_UPDATE` | 是否启用自动更新能力（`1`/`true`/`yes`） | 本仓库构建默认 `1` |
| `AOPC_TARGET_OS` / `AOPC_TARGET_ARCH` | 目标平台/架构（`node build.mjs` 自动按当前机器设置） | darwin / 当前 arch |
| `AOPC_ENV` | 后端环境，发布必须 `production` | build 脚本强制 production |

**版本号必须用 `AOPC_APP_VERSION` 抬**：electron-updater 客户端只认 manifest 里的
`version` 字段（= 构建时的 appVersion），Release tag 叫 v0.0.x 不影响更新判定。
每发一版都要抬，否则已安装客户端永远判“已是最新”。

## 更新闭环是怎么工作的

1. `npm run build` 用 `AOPC_ENV=production` 构建 AOPC 桌面正式包，并把 feed 地址
   `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest-{mac.yml,yml,linux.yml}`
   **烘焙进安装包**（`resources/update-feed.json`，由 AOPC 侧 `packages/desktop/scripts/update-feed-resource.mjs` 完成；
   未设置 `AOPC_UPDATE_FEED_URL` 时也默认烘焙本渠道，显式设空字符串才不烘焙）；
2. `publish-update.sh` 校验产物完整性后，把安装包 + `latest-*.yml` + blockmap 上传到 GitHub Release；
3. 已安装的客户端定期检查 `releases/latest/download/latest-*.yml`，发现更高版本就下载安装包并自动更新。

客户端运行时更新源优先级：CLI 启动参数 > 环境变量 > 包内烘焙的 `update-feed.json`（正式包的默认源）。
更新器/更新源是构建期能力（`AOPC_AUTO_UPDATE`），关闭时安装包检查更新会提示“未启用自动更新”。

## 客户端 feed 地址

- mac: `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest-mac.yml`
- win: `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest.yml`
- linux: `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest-linux.yml`

- **开发态**：写在 AOPC 项目 `.env.local` 的 `AOPC_UPDATE_FEED_URL`（支持完整 URL 或 `owner/repo` 简写）；
- **正式包**：构建期烘焙进 `resources/update-feed.json`（`npm run build` 已自动注入）。

## 注意

- **mac 自动更新必须上传 `.zip`**（Squirrel.Mac 只认 zip），`.dmg` 仅供手动安装；`publish-update.sh` 会校验 manifest 引用了 zip；
- 上传清单以 `latest-*.yml` 引用为准（安装包 + blockmap + manifest）；dist 里未被 manifest 引用的安装产物（旧版本/测试构建残留）会直接拒绝发布——bundle 不会清理 dist，重新构建前先清掉旧产物；
- 安装包超过 100MB 不能进 git，必须走 Releases 资产（上限 2GB）；
- `npm run build` 已强制 `AOPC_ENV=production`，脚本发现 `_TEST` 产物会告警；
- `publish-update.sh` 传自定义版本只改 Release tag，客户端按 manifest 版本判断更新——所以抬版本靠 `AOPC_APP_VERSION`，不靠 tag；
- 旧构建（2026-10-30 前）没有烘焙 feed / 未启用更新器，会回退 z.ai 服务端 manifest 并下载上游 ZCode 包（v3.16.x），请全部升级到本流程构建的版本。
