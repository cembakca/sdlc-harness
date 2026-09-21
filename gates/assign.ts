#!/usr/bin/env node
/**
 * gates/assign.ts — her role AYRI sinyalle kademe atar.
 *
 *   node gates/assign.ts F4-1              # tam atama (JSON)
 *   node gates/assign.ts F4-1 uat model    # tek değer (bash için)
 *
 * NEDEN AYRI SİNYAL
 *
 * Eski rota tek şey ölçüyordu — işin zorluğu — ve onu bütün rollere
 * uyguluyordu. Ama bir rolün ne kadar dikkat istediği, başka bir rolün işinin
 * zorluğundan türetilemez:
 *
 *   • Denetçinin derinliğini ALGORİTMA değil SALDIRI YÜZEYİ belirler.
 *     Auth'a dokunan üç satırlık mekanik değişiklik, offline bir script'teki
 *     karmaşık algoritmadan daha dikkatli okunmalıdır.
 *   • UAT'ın derinliğini implementasyon değil KİMİN OKUDUĞU belirler.
 *     Müşteriye giden bir bildirim, arkasında dokuz açık bulguyla teslim
 *     ediliyorsa, o paketi yazmak kod yazmaktan zor olabilir.
 *   • Test yazmanın zorluğunu DOĞRULAMA YÜZEYİ belirler: saf fonksiyon mu,
 *     durum mu, yoksa zaman/eşzamanlılık mı?
 *
 * VE ÖNEMLİSİ: bu sinyallerin çoğu ZATEN ÖLÇÜLÜ. Belirsizlik spec kapısında,
 * yarıçap blast kapısında, bulgu ağırlığı review kapısında ölçülüyor. Burada
 * onları yeniden sormuyoruz — karar defterinden okuyoruz. Yalnızca hiçbir
 * kapının cevaplamadığı iki soru Jev'e gidiyor (audience, verification_surface).
 * Bir süreç, kendi ölçtüğünü hatırlamıyorsa aynı soruyu iki kez sorar.
 */

import { existsSync, readFileSync } from "node:fs";
import { ROUTE, ASSIGN_QUESTIONS, THRESHOLDS, type TierName } from "./questions.ts";
import { ask, isOffline } from "./jev.ts";
import { loadRoster } from "../sdlc/roster.ts";
import { read, record } from "./journal.ts";
import { projectRoot } from "./root.ts";

const root = projectRoot();
const [, , ticket, roleArg, fieldArg] = process.argv;

if (!ticket) {
  console.error("usage: node gates/assign.ts <TICKET> [role] [field]");
  process.exit(1);
}

const dir = `${root}/docs/sdlc/${ticket}`;
const planPath = `${dir}/plan.md`;
const specPath = `${dir}/spec.md`;
const statePath = existsSync(planPath) ? planPath : existsSync(specPath) ? specPath : `${dir}/intent.md`;

if (!existsSync(statePath)) {
  console.error(`assign: ${ticket} için okunacak artifact yok`);
  process.exit(20);
}

// --- defterden: zaten ölçülmüş olanlar ------------------------------------

const journalRowsAll = read(ticket);
const latest: Record<string, { decision: string; measures: Record<string, number | string> }> = {};
for (const row of journalRowsAll) {
  if (row.gate === "assign") continue;
  latest[row.gate] = { decision: row.decision, measures: row.measures ?? {} };
}

const num = (v: unknown, fallback: number) => (typeof v === "number" ? v : fallback);
const known = {
  ambiguity: num(latest.spec?.measures.ambiguity, NaN),
  testable: num(latest.spec?.measures.testable, NaN),
  radius: String(latest.blast?.measures.radius ?? ""),
  reversible: num(latest.blast?.measures.reversible, NaN),
  severity: num(latest.review?.measures.severity, NaN),
  conformance: num(latest.review?.measures.spec_conformance, NaN),
  changedFiles: num(latest.postbuild?.measures.changedFiles, NaN),
};

// --- Jev'e yalnızca eksik olanı sor ---------------------------------------

let complexity: TierName = "deep";
let complexityReason = "offline — ölçüm yok, güvenli tarafta";
let audience = "customer";
let surface = "temporal";
let tokens = 0;
let fromCache = false;

if (!isOffline()) {
  const state = readFileSync(statePath, "utf8");
  const { answers, usage, cached } = await ask(
    `# ${ROUTE.stateHint}\n\n${state}`,
    [...ROUTE.questions(), ...ASSIGN_QUESTIONS]
  );
  tokens = usage?.input_tokens ?? 0;
  fromCache = cached === true;
  const routing = ROUTE.decide(answers);
  complexity = routing.tier;
  complexityReason = routing.reason;
  audience = String(answers.audience?.value ?? "customer");
  surface = String(answers.verification_surface?.value ?? "temporal");
}

// --- tekrar eden bloklar: ofis ısrarcı bir sorunu daha kıdemliye verir ----

/**
 * Aynı kapı bu ticket'ta iki kez üst üste durdurduysa, o kapının sorumlusu bir
 * kademe yukarı çıkar. Bir ofiste de böyle olur: aynı iş üçüncü kez geri
 * geliyorsa onu daha kıdemli birine verirsin, dördüncü kez aynı kişiye değil.
 * Veri zaten defterde; ölçmek için yeni bir soru gerekmiyor.
 */
/**
 * Sayaç BELGE SÜRÜMÜNE bağlı. "Bu ticket'ta toplam kaç blok oldu" yanlış
 * sinyaldi: 21 Eyl 2026'da bir ayrıştırıcı hatam postbuild'i 4 kez bloke etti
 * ve hat, benim hatam yüzünden geliştiriciyi en pahalı modele terfi ettirdi.
 * Doğru soru: "bu BELGE kaç kez reddedildi?" — belge yeniden yazıldığında
 * sayaç sıfırlanır, çünkü artık başka bir belgedir.
 */
const journalRows = journalRowsAll;
const currentHash: Record<string, string> = {};
for (const row of journalRows) {
  const h = row.measures?.artifactHash;
  if (typeof h === "string") currentHash[row.gate] = h; // son ölçümün hash'i
}
const blocksPerGate: Record<string, number> = {};
for (const row of journalRows) {
  if (row.decision !== "block") continue;
  const h = row.measures?.artifactHash;
  // Hash'i olan kararlar yalnızca GÜNCEL sürüme aitse sayılır; hash'siz eski
  // kayıtlar (ölçüm bu alanı taşımadan önce) sayılmaz.
  if (typeof h === "string" && h === currentHash[row.gate]) {
    blocksPerGate[row.gate] = (blocksPerGate[row.gate] ?? 0) + 1;
  }
}
const OWNER: Record<string, string> = {
  spec: "analyst",
  scope: "architect",
  blast: "architect",
  postbuild: "implementer",
  review: "implementer",
  test: "tester",
};
const escalated: Record<string, number> = {};
for (const [gate, count] of Object.entries(blocksPerGate)) {
  const owner = OWNER[gate];
  if (owner && count >= 2) escalated[owner] = Math.max(escalated[owner] ?? 0, count);
}

// --- rol başına kural: her biri kendi sinyalinden ------------------------

const up = (t: TierName): TierName => (t === "mechanical" ? "standard" : "deep");
type Assigned = { tier: TierName; signal: string; why: string };
const rules: Record<string, Assigned> = {};

// Analist: belirsizlik ölçülmüşse ondan, yoksa işin zorluğundan.
rules.analyst = Number.isNaN(known.ambiguity)
  ? { tier: complexity, signal: "complexity", why: `spec henüz ölçülmedi — ${complexityReason}` }
  : known.ambiguity >= 2.5
    ? { tier: "deep", signal: "spec.ambiguity", why: `belirsizlik ${known.ambiguity.toFixed(2)} ≥ 2.5` }
    : { tier: "standard", signal: "spec.ambiguity", why: `belirsizlik ${known.ambiguity.toFixed(2)} yönetilebilir` };

// Mimar: işin zorluğu + dokunulan yüzeyin genişliği.
rules.architect =
  complexity === "deep" || known.changedFiles >= 12
    ? { tier: "deep", signal: "complexity+breadth", why: complexityReason }
    : { tier: complexity, signal: "complexity", why: complexityReason };

// Geliştirici: bugünkü sinyal doğru — zorluk + emsal.
rules.implementer = { tier: complexity, signal: "complexity", why: complexityReason };

// Güvenlik denetçisi: ALGORİTMA DEĞİL, SALDIRI YÜZEYİ.
rules.reviewer_security = known.radius
  ? known.radius === "critical"
    ? { tier: "deep", signal: "blast.radius", why: "kritik yüzey — derin okuma" }
    : known.radius === "logic"
      ? { tier: "standard", signal: "blast.radius", why: "uygulama mantığı" }
      : { tier: "mechanical", signal: "blast.radius", why: `yüzey ${known.radius}` }
  : { tier: up(complexity), signal: "complexity(fallback)", why: "blast ölçülmedi — yukarı yuvarlandı" };

// Spec denetçisi: kriterlerin ölçülebilirliği düşükse yanlış anlama riski yüksek.
rules.reviewer_spec = Number.isNaN(known.testable)
  ? { tier: complexity, signal: "complexity", why: "spec ölçülmedi" }
  : known.testable < 0.85
    ? { tier: "standard", signal: "spec.testable", why: `kriterler sınırda (${known.testable.toFixed(2)})` }
    : { tier: "mechanical", signal: "spec.testable", why: `kriterler net (${known.testable.toFixed(2)})` };

// Test yazarı: doğrulama yüzeyi. Zaman/eşzamanlılık varsa ucuz model yetmez.
rules.tester =
  surface === "temporal"
    ? { tier: "deep", signal: "verification_surface", why: "zaman/eşzamanlılık — deterministik test zor" }
    : surface === "stateful"
      ? { tier: "standard", signal: "verification_surface", why: "durum kurulumu gerekiyor" }
      : { tier: "mechanical", signal: "verification_surface", why: "saf fonksiyon testi" };

// UAT: implementasyonun zorluğu DEĞİL — kimin okuduğu ve kaç açık bulgu var.
const openSeverity = Number.isNaN(known.severity) ? 0 : known.severity;
rules.uat =
  audience === "customer" || openSeverity >= 3
    ? {
        tier: "deep",
        signal: "audience+findings",
        why:
          audience === "customer"
            ? `müşteriye dokunuyor${openSeverity >= 3 ? `, üstelik ağır açık bulgu (${openSeverity.toFixed(2)})` : ""}`
            : `ağır açık bulgu (${openSeverity.toFixed(2)}) anlatılmalı`,
      }
    : audience === "operator"
      ? { tier: "standard", signal: "audience", why: "operatör okuyacak" }
      : { tier: "mechanical", signal: "audience", why: "yalnızca ekip içi" };

rules.reviewer_second_opinion = rules.reviewer_security;

// Eskalasyon en sonda uygulanır: sinyal ne derse desin, ısrarla durduran bir
// kapının sorumlusu yukarı çıkar.
for (const [role, count] of Object.entries(escalated)) {
  const r = rules[role];
  if (!r || r.tier === "deep") continue;
  rules[role] = {
    tier: up(r.tier),
    signal: "escalation",
    why: `bu ticket'ta ${count} kez bloke oldu (${r.signal}: ${r.why}) — bir kademe yukarı`,
  };
}

// --- kademeleri role/modele çevir ----------------------------------------

const roster = loadRoster();
const assignment: Record<string, unknown> = {};
for (const [role, r] of Object.entries(rules)) {
  const t = (roster.roles[role] as { tiers?: Record<string, { model: string; effort?: string }> })?.tiers?.[r.tier];
  if (!t) continue;
  assignment[role] = {
    vendor: roster.roles[role].vendor,
    model: t.model,
    ...(t.effort ? { effort: t.effort } : {}),
    tier: r.tier,
    signal: r.signal,
    why: r.why,
  };
}

record({
  gate: "assign",
  ticket,
  artifact: statePath.replace(`${root}/`, ""),
  decision: complexity,
  reason: `audience=${audience} surface=${surface} · ${complexityReason}`,
  tokens: tokens || undefined,
});

if (roleArg) {
  const a = assignment[roleArg] as Record<string, unknown> | undefined;
  if (!a) {
    console.error(`assign: "${roleArg}" için kural yok`);
    process.exit(1);
  }
  console.log(fieldArg ? String(a[fieldArg] ?? "") : JSON.stringify(a, null, 2));
} else {
  console.log(
    JSON.stringify(
      {
        ticket,
        state: statePath.replace(`${root}/`, ""),
        measured: { complexity, audience, verification_surface: surface },
        // "0 token" ile "olculmedi" ayni sey degil: hangisi oldugu yazili olmali.
        source: isOffline() ? "offline" : fromCache ? "önbellek" : "ölçüm",
        reused: known,
        ...(tokens ? { usage: { input_tokens: tokens } } : {}),
        assignment,
      },
      null,
      2
    )
  );
}
