#!/usr/bin/env node
/**
 * sdlc/roster.ts — kadro dosyasının tipli okuyucusu ve denetleyicisi.
 *
 *   node sdlc/roster.ts                 # kadroyu tablo olarak bas
 *   node sdlc/roster.ts implementer     # tek rolün JSON'u
 *   node sdlc/roster.ts implementer model   # tek alan (bash için)
 *   node sdlc/roster.ts --check         # kuralları ve sapmaları denetle
 *
 * --check üç şeye bakar:
 *   1. no_self_review: kodu yazan sağlayıcı kendi kodunu denetlemiyor.
 *   2. Harness'taki model adları kadroyla aynı mı (tek kaynak kuralı).
 *   3. Bilinmeyen sağlayıcı / eksik alan var mı.
 * Exit 0 temiz, 1 ihlal.
 */

import { readFileSync } from "node:fs";

export type Role = {
  title: string;
  vendor: string;
  model: string | null;
  effort?: string;
  where: string;
  why: string;
};

export type Roster = {
  vendors: Record<string, { label: string; surface: string }>;
  roles: Record<string, Role>;
  rules: Record<string, { statement: string; why: string }>;
};

const here = new URL(".", import.meta.url).pathname;

export function loadRoster(): Roster {
  return JSON.parse(readFileSync(`${here}roster.json`, "utf8")) as Roster;
}

export function role(name: string): Role {
  const r = loadRoster().roles[name];
  if (!r) throw new Error(`roster: bilinmeyen rol "${name}"`);
  return r;
}

// ---------------------------------------------------------------- denetim

function check(): number {
  const roster = loadRoster();
  const problems: string[] = [];

  for (const [name, r] of Object.entries(roster.roles)) {
    if (!roster.vendors[r.vendor]) problems.push(`${name}: bilinmeyen sağlayıcı "${r.vendor}"`);
    if (r.vendor !== "none" && !r.model) problems.push(`${name}: sağlayıcı var ama model yok`);
    if (!r.why?.trim()) problems.push(`${name}: gerekçe yazılmamış`);
  }

  // 1. Kodu yazan kendi kodunu denetleyemez.
  const impl = roster.roles.implementer?.vendor;
  for (const reviewer of ["reviewer_security", "reviewer_spec"]) {
    const rv = roster.roles[reviewer]?.vendor;
    if (rv && impl && rv === impl) {
      problems.push(
        `no_self_review ihlali: ${reviewer} (${rv}) ile implementer (${impl}) aynı sağlayıcı`
      );
    }
  }

  // 2. Harness'ta elle yazılmış model adı kadrodan sapmasın.
  const workflow = readFileSync(`${here}../.claude/workflows/sdlc.js`, "utf8");

  // 1b. ZINCIR UYELIGI: inChain=false olan rol otomatik hatta gecmemeli.
  //
  // Kadro tablosuna bakan biri, orada duran her rolun hatta kostugunu sanar —
  // reviewer_second_opinion tam da boyle yanlis okunuyordu (21 Eyl 2026).
  // Uyelik artik yapisal bir alan ve burada dogrulaniyor: kadroda "zincirde
  // degil" yazip workflow'a koymak, ya da tersi, sessiz bir yalan olurdu.
  for (const [name, r] of Object.entries(roster.roles) as [string, Role & { inChain?: boolean }][]) {
    if (r.inChain === false && new RegExp(`"${name}"`).test(workflow)) {
      problems.push(`${name}: kadroda inChain=false ama .claude/workflows/sdlc.js icinde cagriliyor`);
    }
    // NOT: tersi DOGRULANAMAZ. inChain=true olan bir rol workflow'da adiyla
    // gecmeyebilir — implementer codex-build.sh uzerinden, gatekeeper ve router
    // gates/ uzerinden kosuyor. "Zincirde degil" iddiasi yanlislanabilir bir
    // iddiadir, "zincirde" degildir; yalnizca yanlislanabilir olani denetleriz.
  }

  const declared = new Set(
    Object.values(roster.roles)
      .map((r) => r.model)
      .filter((m): m is string => Boolean(m))
  );
  for (const m of workflow.matchAll(/model:\s*"([^"]+)"/g)) {
    if (!declared.has(m[1])) {
      problems.push(`sdlc.js içinde kadroda olmayan model: "${m[1]}" (tek kaynak kuralı)`);
    }
  }

  if (problems.length) {
    console.error("roster --check: " + problems.length + " sorun");
    for (const p of problems) console.error("  ✗ " + p);
    return 1;
  }
  console.log("roster --check: temiz — no_self_review ve tek kaynak kuralları sağlanıyor");
  return 0;
}

// ---------------------------------------------------------------- CLI
// Yalnizca dogrudan calistirildiginda; import edildiginde sessiz kalir.

const invokedDirectly =
  process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;

const [, , arg, field] = invokedDirectly ? process.argv : [];

if (!invokedDirectly) {
  // modul olarak import edildi — CLI calistirma
} else if (arg === "--check") {
  process.exit(check());
} else if (arg) {
  const r = role(arg);
  if (field) {
    const v = (r as unknown as Record<string, unknown>)[field];
    console.log(v == null ? "" : String(v));
  } else {
    console.log(JSON.stringify(r, null, 2));
  }
} else {
  const roster = loadRoster();
  const w = Math.max(...Object.keys(roster.roles).map((k) => k.length));
  for (const [name, r] of Object.entries(roster.roles)) {
    const v = roster.vendors[r.vendor];
    console.log(
      `${name.padEnd(w)}  ${(v?.label ?? r.vendor).padEnd(7)} ${(r.model ?? "—").padEnd(14)} ${r.title}` +
        ((r as Role & { inChain?: boolean }).inChain === false ? "  [ZINCIRDE DEGIL — elle]" : "")
    );
  }
}
