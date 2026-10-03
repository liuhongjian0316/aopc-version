#!/usr/bin/env node
/**
 * 校验 config/client-configs.json 快照与 dist 产物 latest-*.yml 的版本一致性。
 * 用法: npm run check （或 node check-update-consistency.js ../AOPC/config/client-configs.json ../AOPC/packages/desktop/dist）
 * 退出码 0 = 一致；1 = dist 版本低于 forceUpdate.minimalVersion 门槛。
 */
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { join } from "node:path";

const [configPath, distDir] = process.argv.slice(2);
if (!configPath || !distDir || !existsSync(configPath) || !existsSync(distDir)) {
  console.error("用法: node check-update-consistency.js <client-configs.json> <dist目录>");
  process.exit(1);
}

const snapshot = JSON.parse(readFileSync(configPath, "utf-8"));
const minimal = snapshot?.data?.configs?.forceUpdate?.minimalVersion ?? "";

const manifests = readdirSync(distDir).filter((f) => /^latest-.*\.yml$/.test(f));
let inconsistent = false;
for (const m of manifests) {
  const yml = readFileSync(join(distDir, m), "utf-8");
  const version = yml.match(/^version:\s*(.+)$/m)?.[1]?.trim().replace(/^["']|["']$/g, "");
  if (!version) continue;
  const ok = !minimal || version >= minimal;
  console.log(`${m}: dist=${version} minimalVersion=${minimal || "(未设置)"} ${ok ? "OK" : "低于门槛"}`);
  if (!ok) inconsistent = true;
}
process.exit(inconsistent ? 1 : 0);
