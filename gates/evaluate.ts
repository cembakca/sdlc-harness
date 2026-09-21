#!/usr/bin/env node
/**
 * gates/evaluate.ts — bir kapıyı çalıştırır, JSON karar basar.
 *
 *   node gates/evaluate.ts spec   docs/sdlc/HKA-123/spec.md
 *   node gates/evaluate.ts blast  docs/sdlc/HKA-123/plan.md
 *   node gates/evaluate.ts review docs/sdlc/HKA-123/REVIEW.md
 *
 * Çıktı: {"gate":"spec","decision":"pass|human|block","reason":"...","answers":{...}}
 * Exit kodu: 0 pass, 10 human, 20 block, 1 hata.  Kararı model değil kod verir.
 */

import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { GATES, type GateName } from "./questions.ts";
import { ask, isOffline } from "./jev.ts";
import { record, ticketOf } from "./journal.ts";
import { fromRoot, harnessRoot } from "./root.ts";
import { resolve } from "node:path";

/** Harness'a ait dosya: proje kokunde DEGIL harness kokunde aranir. */
const harnessPath = (p: string) => resolve(harnessRoot(), p);

const [, , gateName, artifactPath] = process.argv;

const gate = GATES[gateName as GateName];
if (!gate || !artifactPath) {
  console.error(`usage: node gates/evaluate.ts <${Object.keys(GATES).join("|")}> <artifact>`);
  process.exit(1);
}

let state = "";
try {
  state = readFileSync(artifactPath, "utf8");
} catch {
  console.log(
    JSON.stringify({
      gate: gate.name,
      decision: "block",
      reason: `artifact not found: ${artifactPath} — the previous phase did not produce it`,
    })
  );
  process.exit(20);
}

// Kodun sayabildiğini kod sayar.
if (gate.prepare) state = gate.prepare(state);

// Ürün hafızası: "bu iş daha önce yapılmış bir şeye benziyor mu" sorusu projeyi
// bilmeyi gerektirir. Hafıza kapalıysa kapı çalışmaya devam eder, yalnızca
// precedent sorusu boş bağlamla cevaplanır (ve "emsal yok" tarafına düşer).
if (gate.wantsProjectContext) {
  try {
    const summary = state.split("\n").slice(0, 40).join(" ").slice(0, 600);
    const recalled = execFileSync(
      harnessPath("scripts/sdlc/memory.sh"),
      ["recall-project", summary],
      { encoding: "utf8", timeout: 120_000 }
    ).trim();
    if (recalled && !/kapali|kayit yok/i.test(recalled)) {
      state = `PROJECT CONTEXT (from the product knowledge graph):\n${recalled.slice(0, 2500)}\n\n---\n\n${state}`;
    }
  } catch {
    /* hafıza yok ya da yavaş — kapı yine de ölçer */
  }
}

// Dogrulama kapinin KENDI karar fonksiyonuyla yapilir: iki olcumun nokta
// tahminleri degil, KARARLARI karsilastirilir. Ihtiyat sirasi: pass < human < block.
const RANK: Record<string, number> = { pass: 0, human: 1, block: 2 };
const { answers, usage, model, cached, unstable } = await ask(
  `# ${gate.stateHint}\n\n${state}`,
  gate.questions,
  { confirm: { label: (a) => gate.decide(a, state).decision, rank: (d) => RANK[d] ?? 1 } }
);
const measured = gate.decide(answers, state);

// AYNI GIRDIDE IKI FARKLI OLCUM = BELIRSIZLIK. Kapinin zaten dusuk confidence
// icin yaptigi sey: insana dusur. Ihtiyatlisi secilmis olsa bile "pass" kalmasi
// yanlis olurdu — kapi o girdide kendi kararini tekrar edemiyor.
const result = unstable && measured.decision === "pass"
  ? {
      ...measured,
      decision: "human" as const,
      reason: `ölçüm kararsız: aynı girdi iki ölçümde "${unstable.first}" ve "${unstable.second}" okudu`,
    }
  : measured;

// Karar deftere düşer: hangi kapı neyi durdurdu, hangi sayıyla.
// Belgenin surumu karara yazilir: eskalasyon "bu TICKET'ta kac blok" degil
// "bu BELGE kac kez reddedildi" diye sayabilsin. Plan yeniden yazildiginda
// sayac sifirlanmali — artik baska bir plandir.
let artifactHash = "";
try {
  artifactHash = createHash("sha256").update(readFileSync(artifactPath)).digest("hex").slice(0, 16);
} catch {
  /* hash yok — eskalasyon eski davranisa duser */
}

let headSha = "";
if (gate.name === "review") {
  try {
    const ticketName = ticketOf(artifactPath);
    headSha = execFileSync(
      "git",
      ["-C", fromRoot(".sdlc-worktrees", ticketName), "rev-parse", "HEAD"],
      { encoding: "utf8" }
    ).trim().slice(0, 12);
  } catch {
    /* worktree yok */
  }
}

record({
  gate: gate.name,
  ticket: ticketOf(artifactPath) ?? "",
  artifact: artifactPath,
  decision: result.decision,
  reason: result.reason,
  model,
  tokens: usage?.input_tokens,
  measures: {
    ...Object.fromEntries(
      Object.values(answers).map((a) => [a.id, typeof a.value === "number" ? a.value : String(a.value)])
    ),
    ...(result.derived ?? {}),
    ...(artifactHash ? { artifactHash } : {}),
    ...(unstable ? { unstable: `${unstable.first}/${unstable.second}` } : {}),
    ...(headSha ? { headSha } : {}),
  },
});

console.log(
  JSON.stringify(
    {
      gate: gate.name,
      artifact: artifactPath,
      mode: isOffline()
        ? "offline (no JEV_API_KEY — every gate falls to a human)"
        // Onbellekten okundugunu SOYLEMEK zorundayiz: "0 token" ile "olculmedi"
        // ayni sey degil, ve hangisi oldugunu okuyan bilmeli.
        : `jev (${model ?? "?"})${cached ? " · önbellekten" : ""}${unstable ? " · KARARSIZ (dondurulmadı)" : ""}`,
      ...(usage ? { usage } : {}),
      ...result,
      answers,
    },
    null,
    2
  )
);

process.exit(result.decision === "pass" ? 0 : result.decision === "human" ? 10 : 20);
