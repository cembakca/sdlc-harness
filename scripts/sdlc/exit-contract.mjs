#!/usr/bin/env node
/**
 * scripts/sdlc/exit-contract.mjs — çıkış kodu sözleşmesi tutuyor mu.
 *
 * İki yönlü denetler:
 *
 *   1. AKIŞ → SÖZLEŞME. `.claude/workflows/sdlc.js` içindeki her `command()`
 *      çağrısının izin listesi, `gates/exits.ts`'teki sözleşmeyle aynı olmalı.
 *      Elle yazılan bir liste bir kodu atlarsa koşu çöker.
 *
 *   2. KAYNAK → SÖZLEŞME. Her script'in kendi `exit N` satırları sözleşmenin
 *      içinde olmalı. Bir script yeni bir kod döndürmeye başladığında tablo
 *      güncellenmeden yeşile dönmez — asıl koruma budur; insan listesi
 *      eskiyebilir, kaynak eskimez.
 *
 * `1` her iki yönde de yok sayılır: gerçek çökmedir, fırlaması doğrudur.
 */
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HARNESS = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const { CONTRACT } = await import(`${HARNESS}/gates/exits.ts`);
const problems = [];

// --- 1. akistaki cagrilar ------------------------------------------------
const flow = readFileSync(`${HARNESS}/.claude/workflows/sdlc.js`, "utf8");
const callRe = /command\(\s*"([^"]+)"\s*,\s*\[([^\]]*)\]\s*(?:,\s*\[([0-9,\s]*)\])?\s*\)/g;
for (const m of flow.matchAll(callRe)) {
  const [, file, args, allowedRaw] = m;
  // node ile cagrilan gate'lerde gercek komut args[0]'da.
  const target = file === "node"
    ? (args.match(/"([^"]*\.(?:ts|mjs))"/) ?? [])[1] ?? file
    : file;
  const declared = CONTRACT[target];
  if (declared === undefined) {
    // Sozlesmesi olmayan komut: izin listesi de yoksa yalnizca 0 kabul edilir,
    // bu da bilincli olabilir. Ama LISTE yazilmissa sozlesme de yazilmalidir.
    if (allowedRaw !== undefined) problems.push(`sözleşmesiz komut izin listesi taşıyor: ${target}`);
    continue;
  }
  if (declared === "any") continue;
  const allowed = (allowedRaw ?? "0").split(",").map((x) => Number(x.trim())).filter((x) => !Number.isNaN(x));
  const missing = declared.filter((c) => !allowed.includes(c));
  if (missing.length) {
    problems.push(`${target}: izin listesi ${missing.join(",")} kodunu atlıyor (sözleşme: ${declared.join(",")})`);
  }
}

// --- 2. script kaynaklari ------------------------------------------------
for (const [target, declared] of Object.entries(CONTRACT)) {
  if (declared === "any") continue;
  let src = "";
  try { src = readFileSync(`${HARNESS}/${target}`, "utf8"); } catch { continue; }
  const found = new Set();
  for (const m of src.matchAll(/^\s*exit\s+(\d+)/gm)) found.add(Number(m[1]));
  for (const m of src.matchAll(/process\.exit\((\d+)\)/g)) found.add(Number(m[1]));
  for (const m of src.matchAll(/process\.exit\([^)]*\?\s*(\d+)\s*:\s*(\d+)/g)) { found.add(Number(m[1])); found.add(Number(m[2])); }
  found.delete(1); // gercek cokme
  const undeclared = [...found].filter((c) => !declared.includes(c));
  if (undeclared.length) {
    problems.push(`${target}: kaynakta ${undeclared.join(",")} var, sözleşmede yok`);
  }
}

if (problems.length) {
  for (const p of problems) console.error(`  ✗ ${p}`);
  process.exit(20);
}
console.log(`çıkış sözleşmesi tutuyor (${Object.keys(CONTRACT).length} komut)`);
