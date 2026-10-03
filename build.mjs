#!/usr/bin/env node
/**
 * 构建 AOPC 桌面正式包（供 publish-update.sh 发布到 GitHub Releases）。
 *
 * 相比直接跑 AOPC 的 build/bundle，这里额外保证两件事：
 * 1. AOPC_ENV=production：正式产品身份（productName=AOPC、无 _TEST 产物后缀）；
 *    默认（test）会产出 "AOPC Preview-...-TEST" 包，不能用于发布。
 * 2. AOPC_UPDATE_FEED_URL：构建期把 GitHub Releases feed 烘焙进安装包
 *    （resources/update-feed.json），正式包不读运行时环境变量，必须在这里注入。
 *
 * 用法:
 *   node build.mjs                       # 当前平台 + 当前架构
 *   node build.mjs --skip-prepare        # 透传额外参数给 AOPC bundle 脚本
 *   AOPC_TARGET_ARCH=x64 node build.mjs  # 覆盖目标架构
 */
import { spawnSync } from "node:child_process";
import process from "node:process";

const AOPC_DIR = process.env.AOPC_PROJECT_DIR ?? "../AOPC";
const DESKTOP_DIR = `${AOPC_DIR}/packages/desktop`;
const DEFAULT_REPO = "liuhongjian0316/aopc-version";

const PLATFORM_OS = { darwin: "mac", win32: "win", linux: "linux" };
const MANIFEST_NAMES = { mac: "latest-mac.yml", win: "latest.yml", linux: "latest-linux.yml" };

const targetOs = PLATFORM_OS[process.platform];
if (!targetOs) {
  console.error(`错误: 不支持的平台 ${process.platform}`);
  process.exit(1);
}
const manifestName = MANIFEST_NAMES[targetOs];
const repo = process.env.AOPC_VERSION_REPO?.trim() || DEFAULT_REPO;
const feedUrl =
  process.env.AOPC_UPDATE_FEED_URL?.trim() ||
  `https://github.com/${repo}/releases/latest/download/${manifestName}`;
const targetArch = process.env.AOPC_TARGET_ARCH?.trim() || process.arch;

console.log(`[build] 目标平台: ${targetOs}/${targetArch}`);
console.log(`[build] 更新源（烘焙进安装包）: ${feedUrl}`);
console.log(`[build] 产品环境: AOPC_ENV=production`);

function run(command, args) {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    shell: process.platform === "win32",
    env: {
      ...process.env,
      AOPC_ENV: "production",
      AOPC_UPDATE_FEED_URL: feedUrl,
      AOPC_TARGET_OS: targetOs,
      AOPC_TARGET_ARCH: targetArch,
    },
  });
  if (result.status !== 0) {
    console.error(`错误: ${command} ${args.join(" ")} 失败（exit ${result.status}）`);
    process.exit(result.status ?? 1);
  }
}

// bundle 脚本（packages/desktop/scripts/bundle.mjs）识别 AOPC_TARGET_OS/AOPC_TARGET_ARCH
// 与 --os/--arch 参数；这里用环境变量传递，避免参数拼接的引号问题。
run("pnpm", ["-C", DESKTOP_DIR, "run", "build"]);
run("pnpm", ["-C", DESKTOP_DIR, "run", "bundle", "--", ...process.argv.slice(2)]);

console.log(`[build] 构建完成，产物目录: ${AOPC_DIR}/packages/desktop/dist`);
console.log(`[build] 下一步: npm run publish 发布到 GitHub Releases`);
