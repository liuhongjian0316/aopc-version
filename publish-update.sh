#!/usr/bin/env bash
# 一键发布更新到 GitHub Releases（liuhongjian0316/aopc-version）。
#
# 用法:
#   ./publish-update.sh                  # dist 取默认路径，版本号从 latest-*.yml 自动读取
#   ./publish-update.sh 0.16.9           # 指定版本号（仅作为 Release tag；与 manifest 版本不一致时会告警）
#   ./publish-update.sh 0.16.9 "备注"    # 指定版本与发布说明
#   NOTES="..." ./publish-update.sh      # 用环境变量传发布说明（等效第二个参数）
#   ./publish-update.sh --dry-run        # 只做校验（manifest 完整性/强更门槛/产物清单），不上传
#
# 前置:
#   1. gh auth login 已完成
#   2. 桌面构建产物在 ../AOPC/packages/desktop/dist（含 latest-*.yml 与安装包），
#      建议用 npm run build（build.mjs）产出：正式身份 + 更新源已烘焙
set -euo pipefail

REPO="liuhongjian0316/aopc-version"
DIST_DIR="${AOPC_DESKTOP_DIST:-../AOPC/packages/desktop/dist}"
CONFIG_JSON="${AOPC_CLIENT_CONFIGS:-../AOPC/config/client-configs.json}"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

case "${1:-}" in
  -h|--help) usage ;;
esac

DRY_RUN=0
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

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
MANIFEST_VERSION=$(grep -E '^version:' "$DIST_DIR/$MANIFEST" | head -1 | sed 's/version:[[:space:]]*//; s/["'\'']//g')
VERSION="${POSITIONAL[0]:-$MANIFEST_VERSION}"
if [ -z "$VERSION" ]; then
  echo "错误: 无法确定版本号" >&2
  exit 1
fi
TAG="v${VERSION#v}"
if [ -n "$MANIFEST_VERSION" ] && [ "$VERSION" != "$MANIFEST_VERSION" ]; then
  echo "警告: 指定版本 $VERSION 与 manifest 版本 $MANIFEST_VERSION 不一致；" >&2
  echo "      客户端按 manifest 版本判断更新，tag 仅是发布名" >&2
fi

# 3. 发布说明：第二个参数 > NOTES 环境变量
NOTES="${POSITIONAL[1]:-${NOTES:-}}"

# 4. 发布前校验：manifest 引用的文件齐全 + 强更门槛（semver 比较） + 测试产物提醒
node - "$DIST_DIR" "$MANIFEST" "$VERSION" "$CONFIG_JSON" <<'NODE_EOF'
const [distDir, manifestName, version, configJson] = process.argv.slice(2);
const { readFileSync, existsSync } = require("node:fs");
const { join } = require("node:path");

// 与 AOPC shared/forceUpdate.ts 同规则的 semver 解析与比较
function parseSemver(input) {
  const normalized = input.trim().replace(/^v/i, "");
  const strict = normalized.match(/^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$/);
  if (strict) {
    return { nums: [Number(strict[1]), Number(strict[2]), Number(strict[3])], pre: strict[4]?.split(".") ?? [] };
  }
  const majorOnly = normalized.match(/^(\d+)$/);
  if (majorOnly) return { nums: [Number(majorOnly[1]), 0, 0], pre: [] };
  const majorMinor = normalized.match(/^(\d+)\.(\d+)$/);
  if (majorMinor) return { nums: [Number(majorMinor[1]), Number(majorMinor[2]), 0], pre: [] };
  return null;
}
function compareSemver(a, b) {
  const left = parseSemver(a);
  const right = parseSemver(b);
  if (!left || !right) return null;
  for (let i = 0; i < 3; i += 1) {
    if (left.nums[i] !== right.nums[i]) return left.nums[i] > right.nums[i] ? 1 : -1;
  }
  if (left.pre.length === 0 && right.pre.length === 0) return 0;
  if (left.pre.length === 0) return 1;
  if (right.pre.length === 0) return -1;
  const len = Math.max(left.pre.length, right.pre.length);
  for (let i = 0; i < len; i += 1) {
    const l = left.pre[i];
    const r = right.pre[i];
    if (l === undefined) return -1;
    if (r === undefined) return 1;
    const lNum = /^\d+$/.test(l);
    const rNum = /^\d+$/.test(r);
    if (lNum && rNum) {
      if (Number(l) !== Number(r)) return Number(l) > Number(r) ? 1 : -1;
      continue;
    }
    if (lNum !== rNum) return lNum ? -1 : 1;
    if (l !== r) return l > r ? 1 : -1;
  }
  return 0;
}

const yaml = readFileSync(join(distDir, manifestName), "utf-8");
const manifestVersion = yaml.match(/^version:\s*(.+)$/m)?.[1]?.trim().replace(/^["']|["']$/g, "");
if (manifestVersion && manifestVersion !== version) {
  console.log(`提示: manifest 版本 ${manifestVersion}，发布版本 ${version}`);
}

// manifest 引用的每个文件都必须在 dist 里（files[].url 与顶层 path）
const referenced = new Set();
for (const m of yaml.matchAll(/^\s*(?:-\s+)?url:\s*(.+)$/gm)) referenced.add(m[1].trim().replace(/^["']|["']$/g, ""));
for (const m of yaml.matchAll(/^path:\s*(.+)$/gm)) referenced.add(m[1].trim().replace(/^["']|["']$/g, ""));
let missing = 0;
for (const name of referenced) {
  if (name.startsWith("http://") || name.startsWith("https://")) continue;
  if (!existsSync(join(distDir, name))) {
    console.error(`错误: manifest 引用的文件不在 dist 里: ${name}`);
    missing += 1;
  }
}
if (missing > 0) process.exit(1);

// mac 自动更新只认 .zip（Squirrel.Mac），manifest 引用里必须有 zip
if (manifestName === "latest-mac.yml") {
  const hasZip = [...referenced].some((name) => name.toLowerCase().endsWith(".zip"));
  if (!hasZip) {
    console.error("错误: latest-mac.yml 未引用 .zip（mac 自动更新必须上传 zip，dmg 仅供手动安装）");
    process.exit(1);
  }
}

const testArtifacts = [...referenced].filter((name) => name.includes("_TEST"));
if (testArtifacts.length > 0) {
  console.warn(`警告: 产物带 _TEST 后缀（测试后端构建）: ${testArtifacts.join(", ")}`);
  console.warn("      正式发布请用 npm run build（AOPC_ENV=production）重新构建");
}

if (existsSync(configJson)) {
  try {
    const minimal = JSON.parse(readFileSync(configJson, "utf-8"))?.data?.configs?.forceUpdate?.minimalVersion;
    if (minimal) {
      const cmp = compareSemver(version, minimal);
      if (cmp === null) {
        console.error(`错误: 无法比较版本 ${version} 与强更门槛 ${minimal}`);
        process.exit(1);
      }
      if (cmp < 0) {
        console.error(`错误: 发布版本 ${version} 低于强制升级门槛 ${minimal}，先调整 config/client-configs.json`);
        process.exit(1);
      }
      console.log(`强更门槛校验 OK: ${version} >= ${minimal}`);
    } else {
      console.log("强更门槛: 未设置（forceUpdate.minimalVersion 为空）");
    }
  } catch (error) {
    console.warn(`警告: 读取强更门槛失败（忽略）: ${error.message}`);
  }
} else {
  console.log(`强更门槛: 配置文件不存在，跳过（${configJson}）`);
}
console.log(`manifest 完整性 OK: ${referenced.size} 个引用文件全部存在`);
NODE_EOF

# 5. 收集发布产物：安装包 + blockmap + manifest（过滤 builder-debug.yml、解包目录等构建中间物）
shopt -s nullglob
ARTIFACTS=()
for pattern in \
  "$DIST_DIR"/*.dmg "$DIST_DIR"/*.zip \
  "$DIST_DIR"/*.exe "$DIST_DIR"/*.AppImage "$DIST_DIR"/*.appimage \
  "$DIST_DIR"/*.deb "$DIST_DIR"/*.rpm "$DIST_DIR"/*.pacman "$DIST_DIR"/*.pkg.tar.zst \
  "$DIST_DIR"/*.blockmap \
  "$DIST_DIR"/latest*.yml; do
  ARTIFACTS+=("$pattern")
done
shopt -u nullglob
if [ ${#ARTIFACTS[@]} -eq 0 ]; then
  echo "错误: dist 里没有可发布的安装产物" >&2
  exit 1
fi
echo "==> 待发布产物（${#ARTIFACTS[@]} 个）:"
for f in "${ARTIFACTS[@]}"; do
  echo "    $(basename "$f")"
done

if [ "$DRY_RUN" = "1" ]; then
  echo "==> [dry-run] 校验通过，未创建/上传 Release"
  exit 0
fi

# 6. 创建 Release 并上传（同名资产覆盖）
echo "==> 创建 Release $TAG（$REPO）"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "==> Release 已存在，追加/覆盖上传"
  if [ -n "$NOTES" ]; then
    gh release edit "$TAG" --repo "$REPO" --notes "$NOTES" >/dev/null
  fi
else
  if [ -n "$NOTES" ]; then
    gh release create "$TAG" --repo "$REPO" --title "AOPC $TAG" --latest --notes "$NOTES"
  else
    gh release create "$TAG" --repo "$REPO" --title "AOPC $TAG" --latest --generate-notes
  fi
fi
gh release upload "$TAG" "${ARTIFACTS[@]}" --repo "$REPO" --clobber

# 7. 上传后核对资产数量
UPLOADED_COUNT=$(gh release view "$TAG" --repo "$REPO" --json assets --jq '.assets | length')
if [ "$UPLOADED_COUNT" -lt ${#ARTIFACTS[@]} ]; then
  echo "错误: Release 资产数量（$UPLOADED_COUNT）少于本地产物（${#ARTIFACTS[@]}），请检查上传日志" >&2
  exit 1
fi

echo "==> 发布完成（$UPLOADED_COUNT 个资产）。客户端 feed 地址："
echo "    https://github.com/$REPO/releases/latest/download/latest-mac.yml"
echo "    https://github.com/$REPO/releases/latest/download/latest.yml"
echo "    https://github.com/$REPO/releases/latest/download/latest-linux.yml"
