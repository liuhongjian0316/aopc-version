#!/usr/bin/env bash
# 一键发布更新到 GitHub Releases（liuhongjian0316/aopc-version）。
#
# 用法:
#   ./publish-update.sh                  # dist 取默认路径，版本号从 latest-*.yml 自动读取
#   ./publish-update.sh 0.16.9           # 指定版本号（仅作为 Release tag；与 manifest 版本不一致时会告警）
#   ./publish-update.sh 0.16.9 "备注"    # 指定版本与发布说明
#   NOTES="..." ./publish-update.sh      # 用环境变量传发布说明（等效第二个参数）
#   ./publish-update.sh --dry-run        # 只做校验（manifest 完整性/产物清单），不上传
#
# 前置:
#   1. gh auth login 已完成
#   2. 桌面构建产物在 ../AOPC/packages/desktop/dist（含 latest-*.yml 与安装包），
#      建议用 npm run build（build.mjs）产出：正式身份 + 更新源已烘焙
#
# 注意: 本脚本运行在 macOS 自带 bash 3.2 上，echo 里变量展开后不能紧跟中文/全角字符
# （bash 3.2 会把多字节字符首字节并进变量名，触发 set -u 的 unbound variable）。
set -euo pipefail

REPO="liuhongjian0316/aopc-version"
DIST_DIR="${AOPC_DESKTOP_DIST:-../AOPC/packages/desktop/dist}"

usage() {
  sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
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

# 1. 定位主 manifest（mac 优先，其次 win/linux），版本号以它为准
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

# 4. 发布前校验 + 收集产物清单（node 输出清单到 stdout 临时文件，日志走 stderr）
# 校验内容：所有 latest*.yml 引用的文件都在 dist、mac manifest 必须引用 zip、_TEST 测试产物告警。
# 产物清单 = manifest 文件 + 引用文件 + 对应 blockmap（存在时）。
# 注意：清单用临时文件中转，不用 $(node <<EOF)——macOS 自带 bash 3.2 解析不了命令替换里嵌 heredoc。
REFERENCED_LIST_FILE=$(mktemp /tmp/aopc-publish-list.XXXXXX)
trap 'rm -f "$REFERENCED_LIST_FILE"' EXIT
node - "$DIST_DIR" "$VERSION" > "$REFERENCED_LIST_FILE" <<'NODE_EOF'
const [distDir, version] = process.argv.slice(2);
const { readFileSync, existsSync, readdirSync } = require("node:fs");
const { join } = require("node:path");

const manifests = readdirSync(distDir).filter((f) => /^latest-.*\.yml$/.test(f)).sort();
if (manifests.length === 0) {
  console.error("错误: dist 里没有 latest-*.yml（请先完成桌面打包）");
  process.exit(1);
}

// 从 machine 生成的 electron-updater YAML 里提取引用文件（files[].url 与顶层 path）
function referencedFiles(yaml) {
  const names = new Set();
  for (const m of yaml.matchAll(/^\s*(?:-\s+)?url:\s*(.+)$/gm)) {
    names.add(m[1].trim().replace(/^["']|["']$/g, ""));
  }
  for (const m of yaml.matchAll(/^path:\s*(.+)$/gm)) {
    names.add(m[1].trim().replace(/^["']|["']$/g, ""));
  }
  return [...names].filter((name) => !/^https?:\/\//i.test(name));
}

const upload = new Set();
for (const manifestName of manifests) {
  const yaml = readFileSync(join(distDir, manifestName), "utf-8");
  upload.add(manifestName);

  const names = referencedFiles(yaml);
  if (names.length === 0) {
    console.error(`错误: ${manifestName} 没有引用任何文件`);
    process.exit(1);
  }
  let missing = 0;
  for (const name of names) {
    if (!existsSync(join(distDir, name))) {
      console.error(`错误: ${manifestName} 引用的文件不在 dist 里: ${name}`);
      missing += 1;
      continue;
    }
    upload.add(name);
    const blockmap = `${name}.blockmap`;
    if (existsSync(join(distDir, blockmap))) {
      upload.add(blockmap);
    }
  }
  if (missing > 0) process.exit(1);

  // mac 自动更新只认 .zip（Squirrel.Mac），manifest 引用里必须有 zip
  if (manifestName === "latest-mac.yml") {
    const hasZip = names.some((name) => name.toLowerCase().endsWith(".zip"));
    if (!hasZip) {
      console.error("错误: latest-mac.yml 未引用 .zip（mac 自动更新必须上传 zip，dmg 仅供手动安装）");
      process.exit(1);
    }
  }

  const testArtifacts = names.filter((name) => name.includes("_TEST"));
  if (testArtifacts.length > 0) {
    console.warn(`警告: ${manifestName} 引用的产物带 _TEST 后缀（测试后端构建）: ${testArtifacts.join(", ")}`);
    console.warn("      正式发布请用 npm run build（AOPC_ENV=production）重新构建");
  }

  const manifestVersion = yaml.match(/^version:\s*(.+)$/m)?.[1]?.trim().replace(/^["']|["']$/g, "");
  if (manifestVersion && manifestVersion !== version) {
    console.warn(`警告: ${manifestName} 版本 ${manifestVersion} 与发布版本 ${version} 不一致`);
  }
}

console.error(`manifest 完整性 OK: ${manifests.length} 个 manifest，${upload.size} 个待上传文件`);
for (const name of upload) {
  console.log(name);
}
NODE_EOF

# 5. 组装产物路径；dist 里未被任何 manifest 引用的安装产物视为残留，直接拒绝发布
ARTIFACTS=()
while IFS= read -r name; do
  [ -n "$name" ] || continue
  ARTIFACTS+=("$DIST_DIR/$name")
done < "$REFERENCED_LIST_FILE"
if [ ${#ARTIFACTS[@]} -eq 0 ]; then
  echo "错误: 没有可发布的产物" >&2
  exit 1
fi

STALE=()
shopt -s nullglob
for f in "$DIST_DIR"/*.dmg "$DIST_DIR"/*.zip \
         "$DIST_DIR"/*.exe "$DIST_DIR"/*.AppImage "$DIST_DIR"/*.appimage \
         "$DIST_DIR"/*.deb "$DIST_DIR"/*.rpm "$DIST_DIR"/*.pacman "$DIST_DIR"/*.pkg.tar.zst \
         "$DIST_DIR"/*.blockmap; do
  IN_LIST=0
  for a in "${ARTIFACTS[@]}"; do
    if [ "$a" = "$f" ]; then IN_LIST=1; break; fi
  done
  if [ "$IN_LIST" -eq 0 ]; then
    STALE+=("$f")
  fi
done
shopt -u nullglob
if [ ${#STALE[@]} -gt 0 ]; then
  echo "错误: dist 里有未被 manifest 引用的安装产物（旧版本/测试构建残留），拒绝发布:" >&2
  for f in "${STALE[@]}"; do
    echo "    $(basename "$f")" >&2
  done
  echo "    请删除这些残留文件，或清空 dist 后用 npm run build 重新构建（bundle 不会清理 dist）" >&2
  exit 1
fi

echo "==> 待发布产物: ${#ARTIFACTS[@]} 个"
for f in "${ARTIFACTS[@]}"; do
  echo "    $(basename "$f")"
done

if [ "$DRY_RUN" = "1" ]; then
  echo "==> [dry-run] 校验通过，未创建/上传 Release"
  exit 0
fi

# 6. 创建 Release 并上传（同名资产覆盖）
echo "==> 创建 Release $TAG ($REPO)"
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
  echo "错误: Release 资产数量 $UPLOADED_COUNT 少于本地产物 ${#ARTIFACTS[@]} 个，请检查上传日志" >&2
  exit 1
fi

echo "==> 发布完成，资产 $UPLOADED_COUNT 个。客户端 feed 地址："
echo "    https://github.com/$REPO/releases/latest/download/latest-mac.yml"
echo "    https://github.com/$REPO/releases/latest/download/latest.yml"
echo "    https://github.com/$REPO/releases/latest/download/latest-linux.yml"
