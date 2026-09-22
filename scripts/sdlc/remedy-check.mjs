#!/usr/bin/env node
/**
 * scripts/sdlc/remedy-check.mjs — durdurucunun önerdiği çare uygulanabilir mi.
 *
 * Bir durdurucu durduruyorsa ve "şunu yap" diyorsa, o şey desteklenen
 * arayüzden gerçekten yapılabilmelidir. Yapılamıyorsa durdurucu değil tuzaktır.
 *
 * Bu kalıp 22 Eylül 2026'da hattın kendi sınavında dördüncü kez çıktı:
 *   - devre kesici TOPLAM tur sayıyordu → düzeltme sonrası da açılmıyordu
 *   - bilet kilidi PID bakmasa bir çökmede bileti kalıcı kilitlerdi
 *   - artifact koruması ham Error fırlatıp teşhis kanıtını siliyordu
 *   - devre kesici `{ force: true }` diyordu ama CLI `--force`'u reddediyordu
 *
 * Denetim: akışın ürettiği "next" metinlerinde geçen her `make sdlc-*` hedefi
 * ve her `--flag`, gerçekten var olmalı.
 */
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HARNESS = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const flow = readFileSync(`${HARNESS}/.claude/workflows/sdlc.js`, "utf8");
const cli = readFileSync(`${HARNESS}/scripts/sdlc/orchestrate.mjs`, "utf8");
const mk = readFileSync(`${HARNESS}/sdlc.mk`, "utf8");
const problems = [];

// 1. Onerilen make hedefleri var mi.
const targets = new Set([...mk.matchAll(/^([a-z][a-z0-9-]*):/gm)].map((m) => m[1]));
for (const m of flow.matchAll(/make (sdlc-[a-z-]+)/g)) {
  if (!targets.has(m[1])) problems.push(`akış "make ${m[1]}" öneriyor ama sdlc.mk'de böyle bir hedef yok`);
}

// 2. Onerilen bayraklar CLI tarafindan kabul ediliyor mu.
for (const m of flow.matchAll(/(--[a-z][a-z-]*)/g)) {
  const flag = m[1];
  if (flag === "--force" || flag.startsWith("--max-")) {
    if (!cli.includes(`"${flag}"`)) problems.push(`akış ${flag} öneriyor ama orchestrate.mjs onu tanımıyor`);
  }
}

// 3. Onerilen script'ler var mi.
for (const m of flow.matchAll(/scripts\/sdlc\/([a-z-]+\.(?:sh|mjs))/g)) {
  try { readFileSync(`${HARNESS}/scripts/sdlc/${m[1]}`); }
  catch { problems.push(`akış scripts/sdlc/${m[1]} öneriyor ama dosya yok`); }
}

// 4. "force: true" gibi UYGULANAMAZ receteler kalmasin.
if (/\{\s*"?ticket"?:[^}]*force[^}]*\}/.test(flow)) {
  problems.push('akış hâlâ JSON biçiminde `{ ticket, force: true }` öneriyor — CLI\'den uygulanamaz');
}

if (problems.length) {
  for (const p of problems) console.error(`  ✗ ${p}`);
  process.exit(20);
}
console.log("durdurucuların önerdiği her çare uygulanabilir");
