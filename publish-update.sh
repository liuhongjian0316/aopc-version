#!/usr/bin/env bash
# 一键发布更新到 GitHub Releases（liuhongjian0316/aopc-version）。
#
# 用法:
#   ./publish-update.sh                  # dist 取默认路径，版本号从 latest-mac.yml 自动读取
#   ./publish-update.sh 0.16.9           # 指定版本号（覆盖自动读取）
#   ./publish-update.sh 0.16.9 "备注"    # 指定版本与发布说明
#
# 前置:
#   1. gh auth login 已完成
#   2. 桌面构建产物在 ../AOPC/packages/desktop/dist（含 latest-*.yml 与安装包）
set -euo pipefail

REPO="liuhongjian0316/aopc-version"
DIST_DIR="${AOPC_DESKTOP_DIST:-../AOPC/packages/desktop/dist}"

if ! command -v gh >/dev/null 2>&1; then
  echo "错误: 未安装 gh CLI（brew install gh）" >&2
  exit 1
fi
if [ ! -d "$DIST_DIR" ]; then
  echo "错误: dist 目录不存在: $DIST_DIR" >&2
  exit 1
fi

# 1. 定位 manifest（mac 优先，其次 win/linux）
MANIFEST=""
for f in latest-mac.yml latest.yml latest-linux.yml; do
  if [ -f "$DIST_DIR/$f" ]; then MANIFEST="$f"; break; fi
done
if [ -z "${MANIFEST:-}" ]; then
  echo "错误: dist 缺少 latest-*.yml（请先完成桌面打包）" >&2
  exit 1
fi

# 2. 版本号：参数 > manifest 里的 version
if [ $# -ge 1 ] && [ -n "${1:-}" ]; then
  VERSION="$1"
else
  VERSION=$(grep -E '^version:' "$DIST_DIR/$MANIFEST" | head -1 | sed 's/version:[[:space:]]*//; s/["'\'']//g')
fi
if [ -z "$VERSION" ]; then
  echo "错误: 无法确定版本号" >&2
  exit 1
fi
TAG="v${VERSION#v}"

# 3. 校验强制升级门槛（config/client-configs.json 的 minimalVersion 不能高于本次发布）
CONFIG_JSON="../AOPC/config/client-configs.json"
if [ -f "$CONFIG_JSON" ] && command -v node >/dev/null 2>&1; then
  node -e "
    const fs = require('fs');
    const snap = JSON.parse(fs.readFileSync('$CONFIG_JSON', 'utf-8'));
    const minimal = snap?.data?.configs?.forceUpdate?.minimalVersion;
    if (minimal && '$VERSION' < minimal) {
      console.error(\`错误: 发布版本 $VERSION 低于强制升级门槛 \${minimal}，先调整 config/client-configs.json\`);
      process.exit(1);
    }
  " || exit 1
fi

# 4. 创建 Release 并上传全部产物（安装包 + latest-*.yml + blockmap）
echo "==> 创建 Release $TAG（$REPO）"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "==> Release 已存在，追加/覆盖上传"
else
  gh release create "$TAG" --repo "$REPO" --title "AOPC $TAG" --latest ${NOTES:+--notes "$NOTES"}
fi
gh release upload "$TAG" "$DIST_DIR"/* --repo "$REPO" --clobber

echo "==> 发布完成。客户端 feed 地址："
echo "    https://github.com/$REPO/releases/latest/download/latest-mac.yml"
echo "    https://github.com/$REPO/releases/latest/download/latest.yml"
echo "    https://github.com/$REPO/releases/latest/download/latest-linux.yml"
