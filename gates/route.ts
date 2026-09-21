#!/usr/bin/env node
/**
 * gates/route.ts — işin sınıfını ölçer, her role model ve efor atar.
 *
 *   node gates/route.ts docs/sdlc/F4-1/plan.md              # tam rota (JSON)
 *   node gates/route.ts docs/sdlc/F4-1/plan.md implementer  # tek rol
 *   node gates/route.ts docs/sdlc/F4-1/plan.md implementer model
 *
 * Neden ölçüyoruz: her işi en güçlü modelde yüksek eforla koşturmak da, her işi
 * en ucuzda koşturmak da aynı hatanın iki yüzü — işin zorluğunu ölçmemek.
 * Rota başına ≈$0.0001; yanlış kademede tek bir Codex koşusu bunun binlerce katı.
 *
 * Offline (JEV_API_KEY yok) → kademe "deep". Ölçemiyorsak ucuza kaçmayız.
 */

import { readFileSync } from "node:fs";
import { ROUTE, type TierName } from "./questions.ts";
import { ask, isOffline } from "./jev.ts";
import { loadRoster } from "../sdlc/roster.ts";
import { record, ticketOf } from "./journal.ts";

const [, , artifactPath, roleArg, fieldArg] = process.argv;

if (!artifactPath) {
  console.error("usage: node gates/route.ts <artifact> [role] [field]");
  process.exit(1);
}

let state: string;
try {
  state = readFileSync(artifactPath, "utf8");
} catch {
  console.error(`route: artifact bulunamadı: ${artifactPath}`);
  process.exit(20);
}

const roster = loadRoster();
let tier: TierName = "deep";
let reason = "offline — ölçüm yok, güvenli tarafta kalındı";
let confidence = 0;
let inputTokens = 0;

if (!isOffline()) {
  const questions = ROUTE.questions();
  const { answers, usage } = await ask(`# ${ROUTE.stateHint}\n\n${state}`, questions);
  const routing = ROUTE.decide(answers);
  tier = routing.tier;
  reason = routing.reason;
  confidence = routing.confidence;
  inputTokens = usage?.input_tokens ?? 0;
}

record({
  gate: "route",
  ticket: ticketOf(artifactPath) ?? "",
  artifact: artifactPath,
  decision: tier,
  reason,
  tokens: inputTokens || undefined,
  measures: { confidence },
});

// Kademeyi rollere çevir — model adları yalnızca roster.json'dan gelir.
const assignment: Record<string, { vendor: string; model: string; effort?: string }> = {};
for (const [name, r] of Object.entries(roster.roles)) {
  const t = (r as { tiers?: Record<string, { model: string; effort?: string }> }).tiers?.[tier];
  if (!t) continue;
  assignment[name] = { vendor: r.vendor, model: t.model, ...(t.effort ? { effort: t.effort } : {}) };
}

if (roleArg) {
  const a = assignment[roleArg];
  if (!a) {
    console.error(`route: "${roleArg}" rolünün kademe matrisi yok`);
    process.exit(1);
  }
  if (fieldArg) {
    console.log(String((a as unknown as Record<string, unknown>)[fieldArg] ?? ""));
  } else {
    console.log(JSON.stringify(a, null, 2));
  }
} else {
  console.log(
    JSON.stringify(
      {
        artifact: artifactPath,
        tier,
        reason,
        confidence,
        mode: isOffline() ? "offline" : "jev",
        ...(inputTokens ? { usage: { input_tokens: inputTokens } } : {}),
        assignment,
      },
      null,
      2
    )
  );
}
