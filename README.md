# aopc-version 更新发布仓库

本仓库只承载 AOPC 桌面客户端的**更新发布**：安装包与 electron-updater manifest 通过 GitHub Releases 分发（`releases/latest/download/...` 恒指向最新版）。git 里只保存发布脚本与说明。

## 一键发版

前置：`gh auth login`（一次即可），AOPC 项目可构建。

```bash
npm run release
```

等价于：构建桌面应用（`../AOPC/packages/desktop`）→ `publish-update.sh` 自动读版本 → 创建 Release 并上传全部产物。

分步执行：

```bash
npm run build     # 构建 AOPC 桌面应用（含 electron-builder 打包）
npm run publish   # 发布 dist 产物到 GitHub Releases
npm run check     # 校验 dist 版本与 forceUpdate 门槛的一致性
```

## 客户端 feed 地址（写入 AOPC 项目 .env.local 的 AOPC_UPDATE_FEED_URL）

- mac: `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest-mac.yml`
- win: `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest.yml`
- linux: `https://github.com/liuhongjian0316/aopc-version/releases/latest/download/latest-linux.yml`

`releases/latest/download/<文件名>` 恒指向最新 Release，发新版不用改客户端配置。

## 注意

- **mac 自动更新必须上传 `.zip`**（Squirrel.Mac 只认 zip），`.dmg` 仅供手动安装；
- 安装包超过 100MB 不能进 git，必须走 Releases 资产（上限 2GB）；
- 强制升级门槛由 AOPC 项目 `config/client-configs.json` 的 `forceUpdate.minimalVersion` 控制（本地文件，手动编辑），`npm run check` 会校验 dist 版本不低于门槛。
