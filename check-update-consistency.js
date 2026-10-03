#!/usr/bin/env node
/**
 * 校验 config/client-configs.json 快照与 dist 产物 latest-*.yml 的版本一致性。
 * 用法: npm run check （或 node check-update-consistency.js ../AOPC/config/client-configs.json ../AOPC/packages/desktop/dist）
 * 退出码 0 = 一致；1 = dist 版本低于 forceUpdate.minimalVersion 门槛（semver 比较，非字符串比较）。
 */
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const [configPath, distDir] = process.argv.slice(2);
if (!configPath || !distDir || !existsSync(configPath) || !existsSync(distDir)) {
  console.error("用法: node check-update-consistency.js <client-configs.json> <dist目录>");
  process.exit(1);
}

// 与 AOPC shared/forceUpdate.ts 同规则的 semver 解析与比较。
// 字符串比较会把 0.9.10 排在 0.10.0 之后（"0.9.10" > "0.10.0"），必须按数值逐段比较。
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

const snapshot = JSON.parse(readFileSync(configPath, "utf-8"));
const minimal = snapshot?.data?.configs?.forceUpdate?.minimalVersion ?? "";

const manifests = readdirSync(distDir).filter((f) => /^latest-.*\.yml$/.test(f));
if (manifests.length === 0) {
  console.error("dist 里没有 latest-*.yml（请先完成桌面打包）");
  process.exit(1);
}
let inconsistent = false;
for (const m of manifests) {
  const yml = readFileSync(join(distDir, m), "utf-8");
  const version = yml.match(/^version:\s*(.+)$/m)?.[1]?.trim().replace(/^["']|["']$/g, "");
  if (!version) continue;
  if (!minimal) {
    console.log(`${m}: dist=${version} minimalVersion=(未设置) OK`);
    continue;
  }
  const cmp = compareSemver(version, minimal);
  const ok = cmp !== null && cmp >= 0;
  console.log(`${m}: dist=${version} minimalVersion=${minimal} ${ok ? "OK" : "低于门槛"}`);
  if (!ok) inconsistent = true;
}
process.exit(inconsistent ? 1 : 0);
