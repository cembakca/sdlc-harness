#!/usr/bin/env node
/**
 * gates/flow.ts — bu bilet zincirin neresinde, sırada ne var.
 *
 *   node gates/flow.ts <TICKET>          # nerede, sırada ne, sıra bozuldu mu
 *   node gates/flow.ts <TICKET> --next   # yalnızca bir sonraki komut
 *
 * NEDEN VAR. Zincir (`gates/chain.ts`) yazılıydı ama gerçek hiçbir komut ona
 * bakmıyordu: yalnızca kuru koşum, hiç koşmamış orkestratör ve selftest
 * okuyordu. Sonuç, F4-1'in kendi defterinde görülebiliyor — kapıların ilk
 * koşma sırası şuydu (ölçüldü 22 Eyl 2026):
 *
 *     spec → postbuild → test → route → blast → review → assign → scope
 *
 * Zincir "spec → scope → plan → blast → build → review → test" diyor. `scope`
 * kapısı spec'ten 45 dakika sonra ve REVIEW'DAN SONRA koştu. Yani hat bir sıra
 * izlemedi; komutlar elle, rastgele açıldı ve defter bunu sadakatle kaydetti.
 *
 * `gates/status.ts` bunu göremezdi çünkü o bir KONTROL LİSTESİ: hangi kapının
 * satırı var diye bakar, satırların SIRASINA bakmaz. Bir işaretlenmiş liste,
 * yanlış sırada işaretlendiğinde de dolu görünür.
 *
 * Buradaki fark: defter, geçiş tablosuna karşı YENİDEN OYNATILIR.
 */

import { existsSync } from "node:fs";
import { TRANSITIONS, REQUIRES, START, type Phase } from "./chain.ts";
import { read, record } from "./journal.ts";
import { fromRoot } from "./root.ts";

/** Defterdeki kapı adı → zincirdeki faz. Eşlenmeyenler faz değildir. */
const GATE_PHASE: Record<string, Phase> = {
  spec: "gate:spec",
  scope: "gate:scope",
  blast: "gate:blast",
  postbuild: "gate:postbuild",
  review: "gate:review",
  merge: "merge",
  test: "test",
  readiness: "gate:teslim",
};

/**
 * Ölçüm yardımcıları faz DEĞİLDİR: `route` ve `assign` hangi modelin koşacağını
 * söyler, işin nerede olduğunu değil. `approve:*` bir kapının kararını taşır,
 * yeni bir faz açmaz. Bunları faz saymak, sırayı olduğundan düzgün gösterirdi.
 */
const NOT_A_PHASE = new Set(["route", "assign", "defer", "outcome", "land", "flow:override"]);

/** Belge üreten fazlar: kapı değil, çıktı bırakırlar. */
const ARTIFACT_PHASE: [Phase, string][] = [
  ["spec", "spec.md"],
  ["plan", "plan.md"],
  ["review", "REVIEW.md"],
  ["uat", "UAT.md"],
];

export type FlowState = {
  ticket: string;
  phase: Phase;
  entered: Phase[];
  next: Phase[];
  /** `from` burada "eksik olan dayanak"tir, onceki faz degil. */
  violations: { at: string; from: string; to: Phase }[];
};

export function flowOf(ticket: string): FlowState {
  const dir = fromRoot("docs/sdlc", ticket);
  const rows = read(ticket);

  // Zincir defterden YENIDEN OYNATILIR: satirlar zaman sirasindadir, faza
  // cevrilir ve her gecis tabloya sorulur.
  let phase: Phase = START;
  const entered: Phase[] = [];
  const violations: FlowState["violations"] = [];

  // URETIM FAZLARI ZAMANIYLA KANITLANIR, varlikla degil.
  //
  // "plan.md su an duruyor" demek, "blast kapisi olcerken duruyordu" demek
  // degildir. Belgenin bugun var olmasina bakmak, gecmisi olceni her zaman
  // masum gosterir. Defter ise her satirda HANGI BELGEYI olctugunu yaziyor:
  // bir belgeye deginen ILK satir, o belgenin o an var oldugunun kanitidir.
  const evidence = new Map<Phase, string>();
  for (const r of rows) {
    for (const [ph, file] of ARTIFACT_PHASE) {
      if (r.artifact?.endsWith(`/${file}`) && !evidence.has(ph)) evidence.set(ph, r.at);
    }
    // build'in ciktisi bir belge degil: postbuild olctuyse build kosmustur.
    if (r.gate === "postbuild" && !evidence.has("build")) evidence.set("build", r.at);
  }

  const enter = (to: Phase, at: string) => {
    // ONKOSUL: sira degil, DAYANAK denetlenir. Kapinin okumasi gereken karar
    // ortada yoksa, olctugu sey eksik bir durumdur.
    const missing = (REQUIRES[to] ?? []).filter((r) => !entered.includes(r));
    if (missing.length) violations.push({ at, from: missing.join(", ") as Phase, to });
    phase = to;
    if (!entered.includes(to)) entered.push(to);
  };

  // Kapi satirlari ve belge kanitlari ZAMAN SIRASINDA birlikte oynatilir.
  const timeline: { at: string; phase: Phase }[] = [];
  for (const [ph, at] of evidence) timeline.push({ at, phase: ph });
  for (const r of rows) {
    if (NOT_A_PHASE.has(r.gate) || r.gate.startsWith("approve:")) continue;
    const to = GATE_PHASE[r.gate];
    if (to) timeline.push({ at: r.at, phase: to });
  }
  timeline.sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : 0));
  for (const t of timeline) enter(t.phase, t.at);

  // Belgesi olan ama defterde hic degilmemis uretim fazlari: gerceklesmis
  // sayilir, ama kanit olmadigi icin onkosul denetimine girmezler.
  for (const [ph, file] of ARTIFACT_PHASE) {
    if (existsSync(`${dir}/${file}`) && !entered.includes(ph)) entered.push(ph);
  }

  return { ticket, phase, entered, next: TRANSITIONS[phase] ?? [], violations };
}

/**
 * Bu faza ŞİMDİ girilebilir mi — dayanakları yerinde mi.
 *
 * Kapılar bunu ölçmeden ÖNCE sorar. Sormadıkları sürece zincir kâğıtta kalır:
 * `chain.ts` yazılıydı ama gerçek hiçbir komut ona bakmıyordu (ölçüldü
 * 22 Eyl 2026 — yalnızca kuru koşum, hiç koşmamış orkestratör ve selftest).
 */
export function canEnter(ticket: string, phase: Phase): { ok: true } | { ok: false; missing: Phase[] } {
  const grounded = groundedPhases(ticket);
  const missing = (REQUIRES[phase] ?? []).filter((r) => !grounded.has(r));
  return missing.length ? { ok: false, missing } : { ok: true };
}

/**
 * TEMELLENMİŞ fazlar: gerçekleşmiş VE kendi dayanakları da yerinde olanlar.
 *
 * "plan.md diskte duruyor" tek başına yetmez. Plan, spec ve scope kapılarından
 * geçmemişse ortada plan sayılmaz — yalnızca bir dosya vardır. Dayanağı
 * geçişli okumazsak kontrol boşa düşer: biri boş bir dizine `plan.md` bırakıp
 * doğrudan blast kapısına girebilir (ölçüldü 22 Eyl 2026, bu kontrol yazılırken).
 */
export function groundedPhases(ticket: string): Set<Phase> {
  const f = flowOf(ticket);
  const happened = new Set(f.entered);
  const grounded = new Set<Phase>();
  // Sabit noktaya kadar yinele: bir faz, dayanaklari temellendikce temellenir.
  for (let pass = 0; pass < happened.size + 1; pass++) {
    let added = false;
    for (const p of happened) {
      if (grounded.has(p)) continue;
      const need = REQUIRES[p] ?? [];
      if (need.every((r) => grounded.has(r))) { grounded.add(p); added = true; }
    }
    if (!added) break;
  }
  return grounded;
}

/**
 * Kapıdan önce çağrılır. Dayanak yoksa DURDURUR.
 *
 * Geçmenin tek yolu gerekçeyi deftere yazmaktır — kuralın kendisiyle aynı
 * mantık: "onay kayıttır, bayrak değil". `SDLC_FLOW_OVERRIDE` bir bypass
 * değil, imzalı bir istisnadır: `flow:override` satırı defterin mühür
 * zincirine girer ve `sdlc-history` onu gösterir.
 */
export function requireEntry(ticket: string, phase: Phase): void {
  const v = canEnter(ticket, phase);
  if (v.ok) return;

  const why = (process.env.SDLC_FLOW_OVERRIDE ?? "").trim();
  if (why) {
    record({
      gate: "flow:override",
      ticket,
      artifact: phase,
      decision: "human",
      reason: why,
      measures: { phase, missing: v.missing.join(", ") },
    });
    console.error(`akış istisnası deftere yazıldı: ${phase} — eksik: ${v.missing.join(", ")}`);
    return;
  }

  console.error(`DAYANAK YOK: "${phase}" fazı için önce şunlar gerekiyor — ${v.missing.join(", ")}`);
  console.error("");
  // EN DERINDEKI eksigi goster. "plan eksik" demek, plan.md diskte dururken
  // kafa karistirir; asil eksik plan'in KENDI dayanagidir (spec/scope kapilari).
  const grounded = groundedPhases(ticket);
  const seen = new Set<Phase>();
  const deepest: Phase[] = [];
  const walk = (p: Phase) => {
    if (seen.has(p)) return;
    seen.add(p);
    const need = (REQUIRES[p] ?? []).filter((r) => !grounded.has(r));
    if (need.length) { need.forEach(walk); return; }
    deepest.push(p);
  };
  v.missing.forEach(walk);
  for (const m of deepest) console.error(`  ${commandFor(m, ticket)}`);
  console.error("");
  console.error(`  nerede olduğunu görmek için: node gates/flow.ts ${ticket}`);
  console.error(`  bilerek atlıyorsan (deftere yazılır):`);
  console.error(`    SDLC_FLOW_OVERRIDE="<neden>" <komut>`);
  process.exit(21);
}

/** Her faz için insanın çalıştıracağı komut. Tek yerde. */
export function commandFor(phase: Phase, ticket: string): string {
  const d = `docs/sdlc/${ticket}`;
  const map: Partial<Record<Phase, string>> = {
    "hafıza": `scripts/sdlc/memory.sh recall "<intent>"`,
    "ölçüm": `scripts/sdlc/measure.sh ${ticket} plan-stage`,
    spec: `skill brd-analyst → ${d}/spec.md`,
    "gate:spec": `node gates/evaluate.ts spec ${d}/spec.md`,
    "gate:scope": `node gates/evaluate.ts scope ${d}/spec.md`,
    plan: `skill architect → ${d}/plan.md`,
    "gate:blast": `node gates/evaluate.ts blast ${d}/plan.md`,
    build: `scripts/sdlc/codex-build.sh ${ticket}`,
    "gate:postbuild": `node gates/postbuild.ts ${ticket}`,
    review: `scripts/sdlc/codex-review.sh ${ticket} security`,
    "gate:review": `node gates/evaluate.ts review ${d}/REVIEW.md`,
    merge: `scripts/sdlc/merge-check.sh ${ticket}`,
    test: `scripts/sdlc/test.sh ${ticket}`,
    uat: `skill uat-packager → ${d}/UAT.md`,
    "gate:teslim": `node gates/readiness.ts ${ticket}`,
    "hafıza:remember": `scripts/sdlc/memory.sh remember-decisions ${ticket}`,
    BITTI: `scripts/sdlc/land.sh ${ticket}`,
  };
  return map[phase] ?? "—";
}

const invokedDirectly =
  process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;

if (invokedDirectly) {
  const ticket = process.argv[2];
  if (!ticket) {
    console.error("usage: node gates/flow.ts <TICKET> [--next]");
    process.exit(2);
  }
  const f = flowOf(ticket);

  if (process.argv.includes("--next")) {
    for (const n of f.next) console.log(commandFor(n, ticket));
    process.exit(0);
  }

  console.log(`akış · ${ticket}`);
  console.log(`  şu an: ${f.phase}`);
  console.log("");
  const ORDER: Phase[] = ["hafıza", "ölçüm", "spec", "gate:spec", "gate:scope", "plan",
    "gate:blast", "build", "gate:postbuild", "review", "gate:review", "merge", "test",
    "uat", "gate:teslim", "hafıza:remember"];
  for (const p of ORDER) {
    const mark = f.entered.includes(p) ? "✓" : f.next.includes(p) ? "→" : "·";
    const cmd = f.next.includes(p) ? `   ${commandFor(p, ticket)}` : "";
    console.log(`  ${mark} ${p.padEnd(18)}${cmd}`);
  }

  if (f.violations.length) {
    console.log("");
    console.log(`  DAYANAKSIZ ÖLÇÜM — ${f.violations.length} kapı, önkoşulu yokken ölçtü:`);
    for (const v of f.violations) {
      console.log(`    ${v.at.slice(0, 19).replace("T", " ")}  ${v.to.padEnd(16)} eksik: ${v.from}`);
    }
    console.log("");
    console.log("  Bu, kapıların YANLIŞ karar verdiği anlamına gelmez; okuması gereken");
    console.log("  kararı okuyamadan ölçtüğü anlamına gelir. Ölçülen şey eksik bir durumdur.");
  }
  process.exit(f.violations.length ? 1 : 0);
}
