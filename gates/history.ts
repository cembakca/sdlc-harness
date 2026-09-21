#!/usr/bin/env node
/**
 * gates/history.ts — hattın kendi geçmişine bakması.
 *
 *   node gates/history.ts            # tüm ticket'lar
 *   node gates/history.ts F4-1       # tek ticket, tüm kararlar
 *
 * Modelsiz: yalnızca decisions.jsonl okunur. "Hangi kapı en çok neyi durduruyor,
 * bir spec kaç turda geçiyor, bir ticket kaç ölçüm yedi" sorularının cevabı.
 */

import { readdirSync, existsSync } from "node:fs";
import { read, toMarkdown } from "./journal.ts";
import { projectRoot } from "./root.ts";

const root = projectRoot();
const one = process.argv[2];

if (one) {
  process.stdout.write(toMarkdown(one));
  process.exit(0);
}

const dir = `${root}/docs/sdlc`;
if (!existsSync(dir)) {
  console.log("henüz ticket yok");
  process.exit(0);
}

const tickets = readdirSync(dir, { withFileTypes: true })
  .filter((d) => d.isDirectory() && d.name !== "templates")
  .map((d) => d.name);

const byGate = new Map<string, Map<string, number>>();
let total = 0;
let tokens = 0;

console.log("ticket        ölçüm   pass  human  block   son karar");
console.log("─".repeat(72));

for (const t of tickets) {
  const rows = read(t);
  if (!rows.length) continue;
  total += rows.length;
  const c = { pass: 0, human: 0, block: 0 } as Record<string, number>;
  for (const r of rows) {
    c[r.decision] = (c[r.decision] ?? 0) + 1;
    tokens += r.tokens ?? 0;
    const g = byGate.get(r.gate) ?? new Map<string, number>();
    g.set(r.decision, (g.get(r.decision) ?? 0) + 1);
    byGate.set(r.gate, g);
  }
  const last = rows[rows.length - 1];
  console.log(
    `${t.padEnd(13)} ${String(rows.length).padStart(5)} ${String(c.pass ?? 0).padStart(6)} ` +
      `${String(c.human ?? 0).padStart(6)} ${String(c.block ?? 0).padStart(6)}   ${last.gate}: ${last.decision}`
  );
}

if (!total) {
  console.log("(henüz kapı kararı kaydedilmemiş)");
  process.exit(0);
}

console.log("─".repeat(72));
console.log("kapı başına:");
for (const [gate, counts] of byGate) {
  const parts = [...counts.entries()].map(([d, n]) => `${n}× ${d}`).join(", ");
  console.log(`  ${gate.padEnd(12)} ${parts}`);
}
console.log(
  `\ntoplam ${total} ölçüm · ${tokens} input token ` +
    `(≈ $${((tokens / 1_000_000) * 0.042).toFixed(5)})`
);
