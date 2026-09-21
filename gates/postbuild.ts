#!/usr/bin/env node
/**
 * gates/postbuild.ts — build fazının çıktısını PLANA karşı denetler.
 *
 *   node gates/postbuild.ts F4-1
 *
 * Neden var: 21 Eylül 2026'daki ilk uçtan uca koşuda Codex planın 1. görevinin
 * "Done when: test X geçiyor" şartını atladı ve bunu review fazına kadar kimse
 * fark etmedi. Modelin "5 görev de tamam" raporu tek doğrulama kaynağıydı.
 *
 * Bu kontrolde model yok: plan.md'den dosya listeleri ve done-when şartları
 * ayrıştırılır, worktree'deki gerçek diff ile karşılaştırılır.
 *
 * Exit 0 temiz, 10 uyarı (insan baksın), 20 plan ihlali (build eksik).
 */

import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { record } from "./journal.ts";
import { loadProject } from "../sdlc/project.ts";
import { projectRoot } from "./root.ts";

const ticket = process.argv[2];
if (!ticket) {
  console.error("usage: node gates/postbuild.ts <TICKET>");
  process.exit(1);
}

const root = projectRoot();
const planPath = `${root}/docs/sdlc/${ticket}/plan.md`;
const worktree = process.env.SDLC_WORKTREE || `${root}/.sdlc-worktrees/${ticket}`;

if (!existsSync(planPath)) {
  console.error(`postbuild: plan yok: ${planPath}`);
  process.exit(20);
}
if (!existsSync(worktree)) {
  console.error(`postbuild: worktree yok: ${worktree}`);
  process.exit(20);
}

const plan = readFileSync(planPath, "utf8");

// --- plan.md'den ayrıştır -------------------------------------------------

/** "- Files: `a/b.py`, `c/d.tsx`" satırlarındaki backtick'li yollar. */
const plannedFiles = new Set<string>();
{
  // "- Files:" satiri bir sonraki madde isaretine kadar SARABILIR; satir bazli
  // okumak listenin yarisini kaciriyordu (21 Eyl 2026'da olculdu: 4/8 dosya).
  const lines = plan.split("\n");
  let collecting = false;
  let buffer = "";
  const flush = () => {
    if (!buffer) return;
    for (const f of buffer.matchAll(/`([^`]+)`/g)) {
      const raw = f[1].trim();
      // Backtick icinde fonksiyon adi da olabiliyor: dosya saymak icin dizin
      // ayraci ya da bilinen uzanti sart.
      // Gercek yol olmayanlari ele: fonksiyon adlari, joker kaliplar, prose.
      if (!raw.includes("/")) continue;
      if (raw.includes("*")) continue; // joker kalip bir dosya degil
      if (/\s/.test(raw)) continue;
      const brace = raw.match(/^(.*)\{([^}]+)\}(.*)$/);
      if (brace) {
        for (const part of brace[2].split(","))
          plannedFiles.add(`${brace[1]}${part.trim()}${brace[3]}`);
      } else {
        plannedFiles.add(raw);
      }
    }
    buffer = "";
  };
  for (const line of lines) {
    // Markdown kalinlastirmayi da kabul et: "- **Files:**" formati plan
    // yeniden yazildiginda geldi ve ayristirici sessizce 0 dosya okudu
    // (olculdu 21 Eyl 2026: 18 degisen dosyanin tamami "planda yok" uyarisi).
    const start = line.match(/^\s*[-*]\s*\*{0,2}Files?\*{0,2}\s*:\*{0,2}\s*(.*)$/i);
    if (start) {
      flush();
      collecting = true;
      buffer = start[1];
      continue;
    }
    if (collecting) {
      // Yeni madde, yeni baslik, bos satir ya da BACKTICK ICERMEYEN devam
      // satiri listeyi bitirir — aksi halde gorev aciklamasindaki dosya adlari
      // "planlanmis" sayiliyordu (olculdu 21 Eyl 2026).
      if (/^\s*[-*]\s/.test(line) || /^#/.test(line) || !line.trim() || !line.includes("`")) {
        flush();
        collecting = false;
      } else {
        buffer += " " + line.trim();
      }
    }
  }
  flush();
}

/** "Done when: ..." şartları, göreviyle birlikte. */
const doneWhen: { task: string; text: string }[] = [];
let currentTask = "?";
for (const line of plan.split("\n")) {
  const heading = line.match(/^###\s+(.+)$/);
  if (heading) currentTask = heading[1].trim();
  const dw = line.match(/^\s*[-*]\s*\*{0,2}Done when\*{0,2}\s*:\*{0,2}\s*(.+)$/i);
  if (dw) doneWhen.push({ task: currentTask, text: dw[1].trim() });
}

// --- worktree'deki gerçek diff -------------------------------------------

const git = (...args: string[]) =>
  execFileSync("git", ["-C", worktree, ...args], { encoding: "utf8" }).trim();

git("add", "-A");

// DEGISIKLIK KUMESI = taban dala gore fark + commit edilmemis is.
// Yalnizca staged diff'e bakmak, merge-check bir WIP commit attiktan sonra
// onceki turlarda degisen dosyalari GORUNMEZ yapiyordu ve postbuild "planda
// listelenip dokunulmamis" diye bloke ediyordu (olculdu 21 Eyl 2026:
// models/url.py ilk turda degismisti, ikinci turda kaybolmus gorundu).
const baseBranch = (() => {
  try {
    return readFileSync(`${root}/docs/sdlc/${ticket}/.base-branch`, "utf8").trim();
  } catch {
    return "main";
  }
})();
let mergeBase = "";
try {
  mergeBase = git("merge-base", baseBranch, "HEAD");
} catch {
  /* taban dal bulunamadi — yalnizca staged diff ile devam */
}
const changed = [
  ...new Set([
    ...git("diff", "--cached", "--name-only").split("\n"),
    ...(mergeBase ? git("diff", "--name-only", `${mergeBase}..HEAD`).split("\n") : []),
  ]),
]
  .map((s) => s.trim())
  .filter((s) => s && !s.startsWith("docs/sdlc/"));

// --- kontroller -----------------------------------------------------------

const problems: string[] = [];
const warnings: string[] = [];

if (changed.length === 0) problems.push("build hiçbir dosya değiştirmemiş");

// 1. Planda olup dokunulmayan dosyalar
const matches = (changedPath: string, planned: string) =>
  changedPath === planned ||
  changedPath.startsWith(planned.endsWith("/") ? planned : `${planned}/`);

const untouched = [...plannedFiles].filter((p) => !changed.some((c) => matches(c, p)));
if (untouched.length) {
  problems.push(`planda listelenip dokunulmayan dosya(lar): ${untouched.join(", ")}`);
}

// 2. Planda olmayan dosyalara dokunulmuş (kapsam sızıntısı)
const unplanned = changed.filter((c) => ![...plannedFiles].some((p) => matches(c, p)));
if (unplanned.length) {
  warnings.push(`planda olmayan dosya(lar) değişmiş: ${unplanned.join(", ")}`);
}

// 3. Test şartı: done-when bir test dosyasından bahsediyorsa o dosya diff'te olmalı
const testPathsInPlan = new Set<string>();
for (const { text } of doneWhen) {
  for (const m of text.matchAll(/`?([\w./-]*tests?\/[\w./-]+\.(py|ts|tsx|js))`?/g)) {
    testPathsInPlan.add(m[1]);
  }
}
// NOT: eksik test burada BLOKE ETMEZ, uyarir. Sebebi olculdu (21 Eyl 2026):
// plan test yazmayi build gorevlerine bagliyor, kadro ise test yazmayi tester
// rolune veriyordu — tasarim kendi kendisiyle celisiyordu ve zincir test
// fazina hic ulasamiyordu. Testin sahibi test fazi; orada scripts/sdlc/test.sh
// eslesen test bulamazsa zincir GERCEKTEN durur.
for (const t of testPathsInPlan) {
  if (!changed.some((c) => c.endsWith(t) || t.endsWith(c))) {
    warnings.push(`plan test dosyası istiyor, diff'te yok (test fazının işi): ${t}`);
  }
}

// 4. Plan test istiyor ama hiç test dosyasına dokunulmamışsa
// Plan test stratejisi tanimliyor mu: yigin komutlarindan turetilir, sabit
// arac isimlerinden degil. Baska bir repo baska kosucular kullanir.
const runners = loadProject()
  .stacks.flatMap((s) => [s.testCommand, s.typecheckCommand])
  .filter((c): c is string => Boolean(c))
  .flatMap((c) => c.split(/[\s/]+/))
  .filter((w) => /^[a-z][a-z0-9.-]{2,}$/i.test(w));
const testWords = ["test", ...new Set(runners)];
const mentionsTests = new RegExp(testWords.join("|"), "i").test(plan);
const touchedTests = changed.filter((c) => /(^|\/)tests?\//.test(c) || /\.(test|spec)\./.test(c));
if (mentionsTests && touchedTests.length === 0) {
  warnings.push("plan test stratejisi tanımlıyor, diff'te test yok — test fazı yazacak");
}

// --- rapor ----------------------------------------------------------------

const report = {
  ticket,
  worktree,
  changedFiles: changed.length,
  plannedFiles: plannedFiles.size,
  doneWhenConditions: doneWhen.length,
  testFilesTouched: touchedTests.length,
  decision: problems.length ? "block" : warnings.length ? "human" : "pass",
  problems,
  warnings,
};

record({
  gate: "postbuild",
  ticket,
  artifact: `${worktree} (diff)`,
  decision: report.decision,
  reason: problems[0] ?? warnings[0] ?? "plan ile diff örtüşüyor",
  measures: { changedFiles: changed.length, testFilesTouched: touchedTests.length },
});

console.log(JSON.stringify(report, null, 2));
process.exit(problems.length ? 20 : warnings.length ? 10 : 0);
