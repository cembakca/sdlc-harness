#!/usr/bin/env node
/**
 * gates/diagnose.ts — "kapı hayır dedi" cümlesini "şu madde sorunlu"ya çevirir.
 *
 *   node gates/diagnose.ts docs/sdlc/F4-1/spec.md
 *
 * Spec kapısı tüm belgeye tek bir ölçülebilirlik puanı veriyor. Puan düşükse
 * hangi kriterin çektiğini bilmeden yazarı "daha iyi yaz" diye geri göndermek,
 * ölçüm değil temenni olur. Bu araç her kabul kriterini AYRI sorar ve zayıf
 * olanları sıralar — tek Jev çağrısı, çünkü sorular tek istekte izole gider.
 */

import { readFileSync } from "node:fs";
import { ask, isOffline } from "./jev.ts";
import { extractCriteria } from "./criteria.ts";

const path = process.argv[2];
if (!path) {
  console.error("usage: node gates/diagnose.ts <spec.md>");
  process.exit(1);
}
if (isOffline()) {
  console.error("JEV_API_KEY yok — teşhis ölçüm gerektirir");
  process.exit(1);
}

const text = readFileSync(path, "utf8");

// "## Acceptance criteria" başlığı altındaki numaralı maddeleri topla.
// Cikarim TEK KAYNAKTAN: kapinin durdurdugu madde ile burada gosterilen madde
// ayni olmali (bkz. gates/criteria.ts).
const criteria = extractCriteria(text);

if (!criteria.length) {
  console.error("kabul kriteri bulunamadı (## Acceptance criteria başlığı ve numaralı maddeler bekleniyor)");
  process.exit(1);
}

const questions = criteria.map((c) => ({
  id: c.id.replace(/-/g, "_"),
  kind: "noul" as const,
  prompt:
    `This acceptance criterion is objectively verifiable: a tester could decide ` +
    `pass/fail from it alone, without asking the author what was meant.\n\n${c.id}: ${c.body}`,
  criteria: {
    true: "It names an observable trigger and an observable outcome, or an exact value, field, call or number.",
    false: "It leaves a judgement call open: an undefined term, an unstated source of truth, or a quality word with no number behind it.",
  },
}));

const { answers, usage } = await ask(
  `# The spec under review (for context only; judge each criterion on its own)\n\n${text}`,
  questions
);

const rows = criteria.map((c) => ({
  id: c.id,
  score: Number(answers[c.id.replace(/-/g, "_")]?.value ?? 0),
  body: c.body.slice(0, 96),
}));
rows.sort((a, b) => a.score - b.score);

console.log(`${path} — ${criteria.length} kriter, ölçüm ${usage?.input_tokens ?? "?"} token\n`);
console.log("puan  kriter   ilk satır");
console.log("─".repeat(78));
for (const r of rows) {
  const flag = r.score < 0.6 ? "✗" : r.score < 0.8 ? "~" : "✓";
  console.log(`${r.score.toFixed(2)}  ${flag} ${r.id.padEnd(6)} ${r.body}`);
}
const weak = rows.filter((r) => r.score < 0.8);
console.log("─".repeat(78));
console.log(
  weak.length
    ? `${weak.length} kriter eşiğin altında: ${weak.map((r) => r.id).join(", ")} — puanı bunlar çekiyor.`
    : "Her kriter tek başına ölçülebilir; düşük toplam puan başka bir şeyden geliyor."
);
