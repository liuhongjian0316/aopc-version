# aopc-version 更新发布仓库

本仓库只承载 AOPC 桌面客户端的**更新发布**：安装包与 electron-updater manifest 通过 GitHub Releases 分发（`releases/latest/download/...` 恒指向最新版）。git 里只保存发布脚本与说明。

## 更新闭环是怎么工作的

1. `npm run release` 用 `AOPC_ENV=production` 构建 AOPC 桌面正式包，并把 feed 地址
   `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest-{mac.yml,yml,linux.yml}`
   **烘焙进安装包**（`resources/update-feed.json`，由 AOPC 侧 `packages/desktop/scripts/update-feed-resource.mjs` 完成）；
2. `publish-update.sh` 校验产物完整性后，把安装包 + `latest-*.yml` + blockmap 上传到 GitHub Release；
3. 已安装的客户端定期检查 `releases/latest/download/latest-*.yml`，发现更高版本就下载安装包并自动更新
   （正式包不读运行时环境变量，只认构建期烘焙的 feed，防止更新请求被改道）。

## 一键发版

前置：`gh auth login`（一次即可），AOPC 项目可构建。

```bash
npm run release          # 构建（含 feed 烘焙）+ 发布
npm run release NOTES=…  # 等价于 publish 时带说明，见下
```

分步执行：

```bash
npm run build     # 构建 AOPC 桌面正式包（AOPC_ENV=production，feed 已烘焙）
npm run publish   # 校验 dist 产物并发布到 GitHub Releases
npm run check     # 校验 dist 版本与 forceUpdate 门槛的一致性（semver 比较）
./publish-update.sh --dry-run   # 只做发布前校验，不上传
```

发布说明：`./publish-update.sh 0.16.9 "本次更新内容…"`（第二个参数），或 `NOTES="…" npm run publish`。
不给说明时用 `gh --generate-notes` 自动生成。

## 客户端 feed 地址

- mac: `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest-mac.yml`
- win: `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest.yml`
- linux: `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest-linux.yml`

- **开发态**：写在 AOPC 项目 `.env.local` 的 `AOPC_UPDATE_FEED_URL`（支持完整 URL 或 `owner/repo` 简写）；
- **正式包**：构建期由 `AOPC_UPDATE_FEED_URL` 烘焙进 `resources/update-feed.json`（`npm run build` 已自动注入），
  运行时环境变量/启动参数会被忽略。

## 注意

- **mac 自动更新必须上传 `.zip`**（Squirrel.Mac 只认 zip），`.dmg` 仅供手动安装；`publish-update.sh` 会校验 manifest 引用了 zip；
- 安装包超过 100MB 不能进 git，必须走 Releases 资产（上限 2GB）；上传内容已过滤，只含安装包 + blockmap + `latest-*.yml`；
- **默认（test）构建产出 `AOPC Preview-…-TEST` 包，不能用于发布**；`npm run build` 已强制 `AOPC_ENV=production`，脚本发现 `_TEST` 产物会告警；
- 强制升级门槛由 AOPC 项目 `config/client-configs.json` 的 `forceUpdate.minimalVersion` 控制（本地文件，手动编辑），`npm run check` 与 `publish-update.sh` 都会按 semver 校验 dist 版本不低于门槛；
- 版本号以 `latest-*.yml` 里的 `version`（即 AOPC 根 package.json 的 version）为准；给 `publish-update.sh` 传自定义版本只改 Release tag，客户端仍按 manifest 版本判断更新。
