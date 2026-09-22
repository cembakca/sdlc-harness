/**
 * Orkestrasyonu MODEL CAGIRMADAN kosturur.
 *
 *   node scripts/sdlc/workflow-dryrun.mjs
 *
 * 21 Eylul 2026'da olculdu: workflow'un 17 ajanindan yalnizca 5'i gercekten
 * kosmustu. Arka %70 (plan, build, review, merge, test, uat, teslim) hic
 * calistirilmamisti — ve bu oturumun tekrar eden dersi suydu: KOSMAYAN KOD
 * SESSIZCE YANLIS OLUR. Gercek bir tur ~1 saat surer ve token yakar; bu
 * kosum saniyeler surer ve sifir maliyetlidir.
 *
 * NE OLCER: kontrol akisini. Her senaryoda script bastan sona yurur, her
 * agent() cagrisi sahte bir yanit alir, ve sonunda hattin DOGRU YERDE durup
 * durmadigi kontrol edilir. Tanimsiz degisken, eksik await, yanlis dallanma,
 * bozuk donus nesnesi — hepsi burada patlar.
 *
 * NE OLCMEZ: modelin cikti kalitesini. O ayri bir soru ve ayri bir maliyet.
 *
 * Script bir CommonJS govdesi gibi yazilmis (ust seviye `return` var), cunku
 * Workflow araci onu bir fonksiyona sariyor. Burada da ayni sekilde sariyoruz.
 */
import { TRANSITIONS, unreachable } from "../../gates/chain.ts";
import { orchestrate } from "../../sdlc/orchestrator.mjs";

/** Senaryoya gore kapi karari ureten sahte ajan. */
function makeAgent(scenario, seen) {
  return async (prompt, opts = {}) => {
    const label = opts.label ?? "?";
    seen.push(label);
    if (scenario.modelClaimsPass) return '{"decision":"pass"}';
    const p = String(prompt);

    // Kapi cagrilari: JSON dondur. Hangi kapi oldugunu komuttan anla.
    const gate = /evaluate\.ts\s+(\w+)/.exec(p)?.[1];
    if (gate) {
      const decision = scenario.freshGates?.[gate] ?? scenario.gates?.[gate] ?? "pass";
      return JSON.stringify({
        gate,
        decision,
        reason: `dry-run: ${decision}`,
        measures: { artifactHash: "dryrun", radius: scenario.radius ?? "logic" },
      });
    }

    // Toplu olcum fazi: butun kapilari birden dondurur.
    if (/measure\.sh/.test(p)) {
      if (/build-stage/.test(p)) {
        return JSON.stringify({
          postbuild: { decision: scenario.gates?.postbuild ?? "pass", reason: "dry-run" },
          assignment: { measured: { complexity: "standard" } },
        });
      }
      if (/review-stage/.test(p)) {
        return JSON.stringify({ reviewScope: "FULL", severityLadder: "dry-run", assignment: {} });
      }
      const g = (n) => {
        // scenario.newPlan: toplu olcumde blast kararı YOK demek — hat plani
        // yeniden uretir ve blast kapisini GERCEKTEN olcer. Bu yol tabloda
        // "plan → gate:blast" olarak duruyor ve senaryosuz kalirsa test
        // tuketici olmaz.
        if (n === "blast" && scenario.newPlan) return { gate: n, decision: "unknown", reason: "artifact not found", measures: {} };
        if ((n === "spec" || n === "scope") && scenario.newSpec) return { gate: n, decision: "block", reason: "artifact not found", measures: {} };
        return { gate: n, decision: scenario.gates?.[n] ?? "pass", reason: "dry-run", measures: {} };
      };
      return JSON.stringify({
        gates: { spec: g("spec"), scope: g("scope"), blast: g("blast") },
        assignment: { measured: { complexity: "standard" }, implementer: { tier: "standard", model: "x" } },
        approvals: scenario.approvals ?? {},
        rounds: scenario.rounds ?? 0,
      });
    }

    if (/readiness\.ts/.test(p)) {
      return scenario.ready === false ? "HAZIR DEĞİL — 1 engel" : "HAZIR — bütün kayıtlar yeşil.";
    }
    if (/journal\.ts/.test(p) && /rounds/.test(p)) {
      return JSON.stringify({ rounds: scenario.rounds ?? 0 });
    }
    if (/test\.sh/.test(p)) {
      return scenario.testFail ? "sonuc: fail — gercek hata: tests/x.py" : "sonuc: pass — yesil";
    }
    if (/memory\.sh recall/.test(p)) {
      return scenario.memory === false ? "HAFIZA-YOK: dry-run" : "emsal: benzer is yok";
    }
    if (/approve\.sh --check/.test(p)) {
      return scenario.approved ? "2026-09-21 12:00 · dry-run onayi" : "onay yok";
    }
    // review, spec, plan, build, uat, kayit: serbest metin bekleniyor.
    if (label.startsWith("review")) {
      return scenario.reviewFindings ?? "NO FINDINGS";
    }
    return `dry-run çıktısı (${label})`;
  };
}

function makeCommand(scenario, seen) {
  const fake = makeAgent({ ...scenario, modelClaimsPass: false }, []);
  return async (file, args = []) => {
    const name = (file === "node" && typeof args[0] === "string" && args[0].includes("/"))
      ? args[0].split("/").at(-1) : file.split("/").at(-1);
    const stage = name === "measure.sh" ? args[1] : "";
    const gate = name === "evaluate.ts" ? args[1] : "";
    const label = gate ? `gate:${gate}` : stage ? `ölçüm:${stage}` :
      name === "codex-build.sh" ? "build" : name === "merge-check.sh" ? "merge" :
      name === "test.sh" ? "test" : name === "readiness.ts" ? "gate:teslim" :
      name === "memory.sh" && args[0]?.startsWith("remember") ? "hafıza:remember" : name;
    seen.push(label);
    if (name === "measure.sh") return { stdout: await fake(`measure.sh ${stage}`, { label }), code: 0 };
    if (gate) {
      const stdout = await fake(`evaluate.ts ${gate}`, { label });
      const decision = JSON.parse(stdout).decision;
      return { stdout, code: decision === "pass" ? 0 : decision === "human" ? 10 : 20 };
    }
    if (name === "approve.sh") return { stdout: scenario.approved ? "2026-09-21 12:00 · dry-run onayi" : "", code: scenario.approved ? 0 : 1 };
    // Gomulu node script'leri ICERIGINE gore ayrilir: hepsini tek bir cevaba
    // baglamak, yeni bir sorguyu sessizce eski cevapla besler ve durdurucu
    // hic kosmadan "gecti" gorunur (22 Eyl 2026'da spec devre kesicisi
    // yazilirken tam bu oldu).
    if (name === "node" && args[0] === "-e") {
      const src = String(args[1] ?? "");
      if (/existsSync/.test(src)) {
        return { stdout: JSON.stringify({ exists: scenario.specOnDisk === true }), code: 0 };
      }
      return { stdout: "dry-run intent", code: 0 };
    }
    if (name === "node" && args[0] === "--input-type=module") {
      // ["--input-type=module", "-e", <script>, ...] — script args[2]'de.
      const src = String(args[2] ?? args[1] ?? "");
      if (/gate==='spec'/.test(src)) {
        return { stdout: JSON.stringify({ n: scenario.specBlocks ?? 0 }), code: 0 };
      }
      return { stdout: JSON.stringify({ rounds: scenario.rounds ?? 0 }), code: 0 };
    }
    if (name === "memory.sh") return { stdout: scenario.memory === false ? "HAFIZA-YOK: dry-run" : "emsal: benzer is yok", code: 0 };
    if (name === "review-scope.sh" && args[1] === "--patch") return { stdout: "diff --git a/x b/x\n+ok\n", code: 0 };
    if (name === "readiness.ts") return { stdout: scenario.ready === false ? "HAZIR DEĞİL" : "HAZIR", code: scenario.ready === false ? 20 : 0 };
    if (name === "test.sh") return { stdout: scenario.testFail ? "sonuc: fail" : "sonuc: pass", code: scenario.testFail ? 20 : 0 };
    if (name === "merge-check.sh") return { stdout: scenario.mergeFail ? "ÇAKIŞMA" : "birleşme temiz", code: scenario.mergeFail ? 20 : 0 };
    return { stdout: `dry-run çıktısı (${label})`, code: 0 };
  };
}

async function run(name, scenario) {
  const seen = [];
  const logs = [];
  const phases = [];
  const result = await orchestrate({
    agent: makeAgent(scenario, seen),
    command: makeCommand(scenario, seen),
    writeArtifact: (path, content) => { seen.push(`write:${path.split("/").at(-1)}`); },
    args: scenario.args ?? { ticket: "DRYRUN-1" },
    budget: scenario.budget
      ? { total: scenario.budget.total, spent: () => 0, remaining: () => scenario.budget.left }
      : { total: null, spent: () => 0, remaining: () => Infinity },
    log: (m) => logs.push(String(m)),
    onPhase: (t) => phases.push(t),
  });
  return { name, result, seen, logs, phases };
}

const SCENARIOS = [
  {
    // Spec turu devre kesici: kapi ayni bilette ucuncu kez blokladiysa hat
    // durur. Yakinsamayan bir spec daha fazla turla degil INSANLA duzelir;
    // her tur yeni bir Opus belgesi + ~10k token kapi olcumu demek.
    name: "spec üçüncü kez bloklandı → hat spec fazına girmeden durur",
    scenario: { specBlocks: 3, gates: { spec: "block" } },
    expect: (r) =>
      r.result?.stoppedAt === "spec-devre-kesici" &&
      !r.seen.includes("spec") &&
      typeof r.result?.next === "string",
  },
  {
    name: "spec kapısı bloke → plan fazına geçmemeli",
    scenario: { gates: { spec: "block" } },
    expect: (r) => r.result?.stoppedAt === "gate:spec" && !r.seen.includes("plan"),
  },
  {
    name: "model pass iddia etse de gerçek spec kapısı block → build başlamaz",
    scenario: { newSpec: true, gates: { spec: "block" }, modelClaimsPass: true },
    expect: (r) => r.result?.stoppedAt === "gate:spec" && !r.seen.includes("build"),
  },
  {
    name: "scope kapısı bloke → durmalı",
    scenario: { gates: { scope: "block" } },
    expect: (r) => String(r.result?.stoppedAt ?? "").includes("scope"),
  },
  {
    name: "blast insana düştü, onay yok → build başlamamalı",
    scenario: { gates: { blast: "human" }, approved: false },
    expect: (r) => !r.seen.includes("build"),
  },
  {
    name: "review bloke → merge/test/uat'a geçmemeli",
    scenario: { gates: { review: "block" }, approved: true },
    expect: (r) => !r.seen.includes("merge") && !r.seen.includes("uat"),
  },
  {
    name: "specOnly → plan üretir, build yapmaz",
    scenario: { args: { ticket: "DRYRUN-1", specOnly: true } },
    expect: (r) => !r.seen.includes("build") && typeof r.result?.next === "string",
  },
  {
    name: "hafıza kapalı → hat durmaz ama bunu söyler",
    scenario: { memory: false, approved: true },
    expect: (r) =>
      r.result?.memory?.consulted === false ||
      r.logs.some((l) => /hafıza sorulamadı/i.test(l)),
  },
  {
    name: "yeni plan → blast kapısı gerçekten ölçülür",
    scenario: { newPlan: true, approved: true },
    expect: (r) => r.phases.includes("gate:blast") && r.seen.includes("build"),
  },
  {
    name: "bütçe bitti → pahalı faza girmeden durur",
    scenario: { approved: true, budget: { total: 100_000, left: 5_000 } },
    expect: (r) => r.result?.reason === "budget" && !r.seen.includes("build"),
  },
  {
    name: "sıfır bütçe → build başlamaz",
    scenario: { approved: true, budget: { total: 0, left: 0 } },
    expect: (r) => r.result?.reason === "budget" && !r.seen.includes("build"),
  },
  {
    name: "yeni spec → scope taze belgeyle yeniden ölçülür",
    scenario: { newSpec: true, newPlan: true, approved: true },
    expect: (r) => r.seen.includes("gate:spec") && r.seen.includes("gate:scope") && r.seen.includes("build"),
  },
  {
    name: "postbuild insan onayı yok → review başlamaz",
    scenario: { gates: { postbuild: "human" } },
    expect: (r) => r.result?.stoppedAt === "gate:postbuild" && !r.seen.includes("review:sec"),
  },
  {
    name: "bilinmeyen scope kararı → plan başlamaz",
    scenario: { gates: { scope: "unknown" } },
    expect: (r) => r.result?.stoppedAt === "gate:scope" && !r.seen.includes("plan"),
  },
  {
    name: "tur sınırı → spec başlamaz",
    scenario: { rounds: 2 },
    expect: (r) => r.result?.stoppedAt === "devre-kesici" && !r.phases.includes("spec"),
  },
  {
    name: "her şey yeşil → zincir sonuna kadar yürür",
    scenario: { approved: true },
    expect: (r) => r.seen.includes("uat") && r.seen.includes("hafıza:remember"),
  },
];

// Tablo kendisi saglam mi: olu faz kalmasin.
const dead = unreachable();
if (dead.length) {
  console.log(`  ✗ erişilemeyen faz: ${dead.join(", ")}`);
  process.exit(1);
}

const entered = new Set();
let pass = 0;
let fail = 0;
for (const s of SCENARIOS) {
  let r;
  try {
    r = await run(s.name, s.scenario);
  } catch (e) {
    console.log(`  ✗ ${s.name}`);
    console.log(`      PATLADI: ${String(e && e.message).slice(0, 160)}`);
    fail++;
    continue;
  }
  for (const p of r.phases) entered.add(p);
  if (s.expect(r)) {
    console.log(`  ✓ ${s.name}`);
    pass++;
  } else {
    console.log(`  ✗ ${s.name}`);
    console.log(`      koşan ajanlar: ${r.seen.join(", ") || "(hiç)"}`);
    console.log(`      döndü: ${JSON.stringify(r.result).slice(0, 160)}`);
    fail++;
  }
}

// TUKETICILIK: tablodaki her faza en az bir senaryoda girilmis olmali.
// Elle secilmis senaryolar, tablo buyudukce sessizce eksik kalir.
const never = Object.keys(TRANSITIONS).filter((p) => p !== "BITTI" && !entered.has(p));
if (never.length) {
  console.log(`  ✗ hiçbir senaryoda girilmeyen faz: ${never.join(", ")}`);
  fail++;
} else {
  console.log(`  ✓ tablodaki ${Object.keys(TRANSITIONS).length - 1} fazın hepsine girildi`);
  pass++;
}

console.log(`\n  ${pass} geçti · ${fail} kaldı`);
process.exit(fail ? 1 : 0);
