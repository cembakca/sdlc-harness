#!/usr/bin/env node
/**
 * gates/calibrate.ts — kapılar gerçekten ayırt ediyor mu, ve kararlı mı?
 *
 *   node gates/calibrate.ts          # her vaka 2 kez (salınım ölçülebilsin)
 *   node gates/calibrate.ts 5        # her vaka 5 kez — SALINIM ölçümü
 *   node gates/calibrate.ts --plan   # MODELSİZ: hangi vaka hangi fixture'dan,
 *                                    #   eksik var mı (bedava, CI'da koşar)
 *
 * İki ayrı soru ölçülüyor:
 *   1. Doğruluk  — kapı bilinen-iyiyi geçiriyor, bilinen-kötüyü durduruyor mu?
 *   2. Kararlılık — aynı girdide aynı kararı veriyor mu? Eşiğin dibinde salınan
 *      bir vaka, bugün PASS yarın BLOCK okur; bu bir kapı değil, kura çekmedir.
 *
 * Bozuk bir kapı, kapı olmamasından tehlikelidir: olmadığını bilirsin, bozuk
 * olduğunu bilmezsin.
 *
 * Exit 0 hepsi tuttu ve salınım yok, 1 sapma veya salınım var.
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { GATES, ROUTE, type GateName, type TierName } from "./questions.ts";
import { fromRoot, harnessRoot } from "./root.ts";
import { loadProject } from "../sdlc/project.ts";
import { ask, isOffline } from "./jev.ts";

type GateCase = { kind: "gate"; gate: GateName; fixture: string; expect: string; because: string };
type RouteCase = { kind: "route"; fixture: string; expect: TierName; because: string };

const GENERIC_CASES: (GateCase | RouteCase)[] = [
  // --- spec kapısı: ölçülebilirlik ve belirsizlik
  { kind: "gate", gate: "spec", fixture: "spec-tight.md", expect: "pass",
    because: "ölçülebilir EARS kriterleri, açık kapsam dışı, açık soru yok" },
  { kind: "gate", gate: "spec", fixture: "spec-minimal-good.md", expect: "pass",
    because: "küçük ama kesin: üç kriter de tek başına test edilebilir" },
  { kind: "gate", gate: "spec", fixture: "spec-vague.md", expect: "block",
    because: '"daha alakalı olmalı", "temiz görünmeli" — test edilemez' },
  { kind: "gate", gate: "spec", fixture: "spec-open-questions.md", expect: "block",
    because: "dört açık soru tasarımı değiştirir; kapsam dışı 'henüz belli değil'" },

  // --- bölünme kapısı: bir iş mi, paket mi
  { kind: "gate", gate: "scope", fixture: "spec-single-outcome.md", expect: "pass",
    because: "dört kriter de aynı tek çıktıya hizmet ediyor; yarısını yayınlamak kimseye yaramaz" },
  { kind: "gate", gate: "scope", fixture: "spec-should-split.md", expect: "block",
    because: "klasör ağacı, bildirim, fatura PDF'i, Slack, ZIP export — haftalarca ayrı yayınlanabilir işler" },

  // --- blast kapısı: risk ve geri alınabilirlik
  { kind: "gate", gate: "blast", fixture: "plan-docs.md", expect: "pass",
    because: "yalnızca markdown; çalışma zamanına dokunmuyor" },
  { kind: "gate", gate: "blast", fixture: "plan-config.md", expect: "pass",
    because: "tek sabit değişiyor, geri alması bir satır" },
  { kind: "gate", gate: "blast", fixture: "plan-critical.md", expect: "human",
    because: "migration + auth + faturalama; geri alınca veri kaybı var" },
  { kind: "gate", gate: "blast", fixture: "plan-payments.md", expect: "human",
    because: "ödeme yüzeyi — Stripe'a gönderilen fatura geri alınamıyor" },
  { kind: "gate", gate: "blast", fixture: "plan-irreversible.md", expect: "human",
    because: "kritik yüzey yok ama eski değerler siliniyor: geri alınamaz" },

  // --- review kapısı: bulgu ağırlığı ve spec uyumu
  { kind: "gate", gate: "review", fixture: "review-clean.md", expect: "pass",
    because: "tek low bulgu, spec uyumu tam" },
  { kind: "gate", gate: "review", fixture: "review-medium.md", expect: "pass",
    because: "en ağır bulgu medium ve görünür şekilde hatalı — eşiğin altında" },
  { kind: "gate", gate: "review", fixture: "review-scope-creep.md", expect: "human",
    because: "bulgular hafif ama kimsenin istemediği silme ucu eklenmiş" },
  { kind: "gate", gate: "review", fixture: "review-critical.md", expect: "block",
    because: "critical enumeration açığı + istenmeyen public endpoint" },

  // --- GERCEK IS: teslim edilmis bir ticket'in kendi artifact'leri ------------
  //
  // Kalibrasyon 21 Eyl 2026'ya kadar yalnizca EL YAPIMI fixture'larla kosuyordu
  // ve "wrong: 0" diyordu. Ama gercek bir plan.md kapiya girdiginde radius
  // sinyali 0.40-0.53 guvenle cokuyor ve karar insana dusuyordu — yani kapi,
  // kendi sectigi sinavda basariliydi. Asil girdi burada.
  //
  // Beklenen degerler UYDURULMADI: F4-1 gercekten teslim edildi (shipped-clean,
  // olay yok) ve kararlari defterde duruyor. Yani bu vakalar "dogru cevabi"
  // gecmisten aliyor, bizim tahminimizden degil.
  // GERCEK VAKALAR ARTIK PROJEDE TANIMLANIR. Burada uc tane Crawlens vakasi
  // gomuluydu; harness ayri repoya cikinca bunlar BASKA HER PROJEDE eksik
  // fixture olarak dusuyordu (olculdu 22 Eyl 2026: 22 vakanin 3'u).
  // Projenin kendi vakalari: sdlc/project.json -> calibration.cases,
  // dosyalari sdlc/fixtures/ altinda.

  // --- yönlendirme: hangi iş hangi modelde koşmalı
  { kind: "route", fixture: "plan-mechanical-precedent.md", expect: "mechanical",
    because: "birebir emsali olan yeniden adlandırma; karar verilecek şey yok" },
  { kind: "route", fixture: "plan-docs.md", expect: "standard",
    because: "mekanik iş ama emsal yok → bir kademe yukarı. BİLİNEN SAPMA: saf " +
      "doküman işi için fazla temkinli; emsal sorusu kod işine göre yazıldı." },
  { kind: "route", fixture: "plan-algorithmic.md", expect: "deep",
    because: "kümeleme algoritması + eşzamanlılık, emsalsiz" },
  { kind: "route", fixture: "plan-critical.md", expect: "deep",
    because: "migration + auth + ödeme; emsali yok" },
];

/**
 * Projenin KENDI vakaları — `sdlc/project.json` → `calibration.cases`.
 *
 * El yapımı fixture'lar kapıyı kendi seçtiği sınavda başarılı gösterir: gerçek
 * bir `plan.md` girdiğinde sinyal 0.40'a çöküyordu, fixture'larda öyle bir
 * girdi yoktu (ölçüldü 21 Eyl 2026). O yüzden "gerçek girdiyle kalibre et"
 * vazgeçilmez — ama gerçek girdi PROJEYE aittir, harness'a değil.
 *
 * Beklenen değer uydurulmaz: teslim edilmiş bir işin defterdeki kararı yazılır.
 */
function projectCases(): (GateCase | RouteCase)[] {
  const raw = (loadProject() as any).calibration?.cases;
  if (!Array.isArray(raw)) return [];
  return raw.map((c: any) =>
    c.kind === "route"
      ? { kind: "route", fixture: c.fixture, expect: c.expect, because: c.because ?? "" }
      : { kind: "gate", gate: c.gate, fixture: c.fixture, expect: c.expect, because: c.because ?? "" },
  );
}

const CASES: (GateCase | RouteCase)[] = [...GENERIC_CASES, ...projectCases()];

// IKI KOK. Harness ayri repoya cikinca bunlar ayni dizin degil:
//   genel vakalar → harness'in kendi gates/fixtures/  (projeden bagimsiz)
//   proje vakalari → PROJENIN sdlc/fixtures/          (gercek artifact'ler)
// Ikisini karistirmak, "gercek girdiyle kalibre et" ozelligini sessizce
// kapatirdi: harness'in icinde proje fixture'i aranir, bulunmaz, vaka duser.
const GENERIC_DIR = resolve(harnessRoot(), "gates/fixtures");
const PROJECT_DIR = fromRoot("sdlc/fixtures");

/** Vakanin fixture'i nerede — ve var mi. */
function fixtureOf(c: GateCase | RouteCase): { path: string; source: "genel" | "proje" } | null {
  const generic = resolve(GENERIC_DIR, c.fixture);
  if (existsSync(generic)) return { path: generic, source: "genel" };
  const own = resolve(PROJECT_DIR, c.fixture);
  if (existsSync(own)) return { path: own, source: "proje" };
  return null;
}
// VARSAYILAN 2, 1 DEGIL. Salinim tek kosuyla OLCULEMEZ: repeats=1 iken
// "flapping: 0" her zaman dogru cikar ve CI'daki salinim kontrolu bos bir
// guvenceye donusur (olculdu 21 Eyl 2026 — kayitta repeats:1 vardi).
// Bir kontrolun her zaman yesil vermesi, kontrol olmadigi anlamina gelir.
const repeats = Math.max(2, Number(process.argv[2] ?? 2));

// --plan: MODEL CAGIRMADAN dongunun saglam olup olmadigini gosterir.
// Eksik bir fixture eskiden yalnizca UCRETLI bir kosuda ortaya cikiyordu;
// artik selftest ve CI bunu bedava yakalar.
if (process.argv.includes("--plan")) {
  let missing = 0;
  const bySource: Record<string, number> = { genel: 0, proje: 0 };
  console.log(`kalibrasyon planı · ${CASES.length} vaka`);
  console.log(`  genel vakalar : ${GENERIC_DIR}`);
  console.log(`  proje vakaları: ${PROJECT_DIR}${existsSync(PROJECT_DIR) ? "" : "  (yok — yalnızca genel vakalar)"}`);
  for (const c of CASES) {
    const found = fixtureOf(c);
    const label = c.kind === "route" ? "route" : c.gate;
    if (!found) {
      missing++;
      console.log(`  ✗ ${label.padEnd(9)} ${c.fixture} — FIXTURE YOK`);
    } else {
      bySource[found.source]++;
    }
  }
  console.log(`  ${bySource.genel} genel · ${bySource.proje} proje · ${missing} eksik`);
  if (missing) console.log("\neksik fixture = ölçülmeyen vaka: kapı o durumda hiç sınanmıyor.");
  process.exit(missing ? 1 : 0);
}

if (isOffline()) {
  console.error("JEV_API_KEY yok — kalibrasyon offline modda anlamsız.");
  console.error("  modelsiz denetim için: node gates/calibrate.ts --plan");
  process.exit(1);
}

let lastModel = "";

async function runOnce(c: GateCase | RouteCase): Promise<{ verdict: string; detail: string }> {
  // FIXTURE IKI YERDEN GELIR:
  //   gates/fixtures/  → harness'in kendi vakalari (genel, projeden bagimsiz)
  //   sdlc/fixtures/   → BU PROJENIN gercek artifact'leri
  //
  // Ayrim, harness ayri bir repoya cikarken sart oldu: genel kapiya Turkce
  // Crawlens belgeleri tasimak tuhaf olurdu, ama "gercek girdiyle kalibre et"
  // ozelligi de kaybedilemezdi — el yapimi fixture'lar kapiyi kendi sectigi
  // sinavda basarili gosteriyordu (olculdu 21 Eyl 2026: radius guveni gercek
  // bir planda 0.40'a dusuyordu, fixture'larda oyle bir girdi yoktu).
  // Her proje kendi kalibrasyonunu kendi isiyle besler.
  const found = fixtureOf(c);
  if (!found) throw new Error(`fixture bulunamadi: ${c.fixture}`);
  const state = readFileSync(found.path, "utf8");
  if (c.kind === "route") {
    // ONBELLEK KAPALI: kalibrasyonun isi "ayni girdide ayni cevap mi" diye
    // sormak. Onbellekten okursa flapping her zaman 0 cikar — bos guvence.
    const { answers, usage, model } = await ask(`# ${ROUTE.stateHint}\n\n${state}`, ROUTE.questions(), { cache: false });
    tokens += usage?.input_tokens ?? 0;
    if (model) lastModel = model;
    const r = ROUTE.decide(answers);
    return { verdict: r.tier, detail: r.reason };
  }
  const gate = GATES[c.gate];
  // prepare() URETIMDE uygulaniyordu, kalibrasyonda UYGULANMIYORDU: yani
  // kalibre edilen kapi ile kosan kapi ayni sey degildi (olculdu 21 Eyl 2026).
  // Kalibrasyonun tek isi gercegi taklit etmek; farkli girdiyle olcerse
  // "wrong: 0" hicbir sey soylemez.
  const prepared = gate.prepare ? gate.prepare(state) : state;
  // ONBELLEK KAPALI — yukaridaki gerekce.
  const { answers, usage, model } = await ask(`# ${gate.stateHint}\n\n${prepared}`, gate.questions, { cache: false });
  if (model) lastModel = model;
  tokens += usage?.input_tokens ?? 0;
  const r = gate.decide(answers, prepared);
  return {
    verdict: r.decision,
    detail:
      r.reason +
      " · " +
      Object.values(answers)
        .map((a) => `${a.id}=${typeof a.value === "number" ? a.value.toFixed(2) : a.value}@${a.confidence.toFixed(2)}`)
        .join(" "),
  };
}

let tokens = 0;
let wrong = 0;
let flapping = 0;

console.log(`her vaka ${repeats}x koşuyor\n`);
console.log("vaka                              beklenen   sonuç" + (repeats > 1 ? "      kararlılık" : ""));
console.log("─".repeat(84));

for (const c of CASES) {
  const label = `${c.kind === "route" ? "route" : c.gate} · ${c.fixture}`;
  const seen = new Map<string, number>();
  let lastDetail = "";
  for (let i = 0; i < repeats; i++) {
    const { verdict, detail } = await runOnce(c);
    seen.set(verdict, (seen.get(verdict) ?? 0) + 1);
    lastDetail = detail;
  }
  const hits = seen.get(c.expect) ?? 0;
  const stable = seen.size === 1;
  const ok = hits === repeats;
  if (!ok) wrong++;
  if (!stable) flapping++;

  const mark = ok ? "✓" : hits > 0 ? "~" : "✗";
  const stability = repeats > 1 ? `  ${hits}/${repeats} ${stable ? "" : "SALINIM: " + [...seen.keys()].join("/")}` : "";
  const shown = [...seen.entries()].sort((a, b) => b[1] - a[1])[0][0];
  console.log(`${label.padEnd(33)} ${c.expect.padEnd(10)} ${shown.padEnd(9)} ${mark}${stability}`);
  console.log(`${" ".repeat(4)}beklenti: ${c.because}`);
  console.log(`${" ".repeat(4)}kapı    : ${lastDetail}`);
}

console.log("─".repeat(84));
console.log(
  `${CASES.length - wrong}/${CASES.length} vaka tam tuttu · ${flapping} vaka salınıyor · ` +
    `${tokens} input token (≈ $${((tokens / 1_000_000) * 0.042).toFixed(5)})`
);
// Sonucu diske yaz: SessionStart hook'u kalibrasyonun bayatladigini buradan anlar.
try {
  writeFileSync(
    // Kayit PROJEYE ait: olculen sey bu projenin kapilaridir (genel vakalar +
    // projenin kendi artifact'leri). Harness'in icine yazmak, tuketen repoda
    // submodule'u kirletirdi ve olcumu yanlis repoya baglardi.
    fromRoot("sdlc/.last-calibration.json"),
    JSON.stringify(
      {
        at: new Date().toISOString(),
        cases: CASES.length,
        wrong,
        flapping,
        repeats,
        // MODEL KAYDA GECER. "Kapilar ayirt ediyor" cumlesi BIR MODEL
        // hakkindadir; jev-latest takma adi arkasindaki model isim degismeden
        // kayar (olculdu 22 Eyl 2026: istenen jev-latest, donen jev-1.13.0).
        // Model yazilmazsa kayit taze gorunur ama neyi olctugu bilinmez.
        model: lastModel,
        inputTokens: tokens,
      },
      null,
      2
    ) + "\n",
    "utf8"
  );
} catch {
  /* kayit tutulamadi — olcum yine de gecerli */
}

if (flapping) {
  console.log(
    "\nSalınan vaka eşiğin dibinde demektir. Yapılacak şey eşiği kaydırmak DEĞİL:\n" +
      "ya soru daha keskin yazılır, ya o vaka kararsız kabul edilip insana düşürülür."
  );
}
process.exit(wrong || flapping ? 1 : 0);
