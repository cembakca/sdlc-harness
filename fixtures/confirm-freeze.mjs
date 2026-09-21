#!/usr/bin/env node
/**
 * fixtures/confirm-freeze.mjs — "ölç, doğrula, dondur" gerçekten öyle mi.
 *
 *   node fixtures/confirm-freeze.mjs <harness-koku>
 *
 * Gerçek bir Jev çağrısı YAPMAZ: yerinde küçük bir HTTP sunucusu açar ve
 * ölçümleri istediği gibi salındırır. Böylece kararsızlık senaryosu bedava ve
 * yeniden üretilebilir şekilde sınanır — gerçek modelde bunu tetiklemek için
 * sınırda duran bir belge bulmak ve şansa güvenmek gerekirdi.
 *
 * Sınanan dört davranış:
 *   1. iki ölçüm ayrışırsa kararsızlık BİLDİRİLİR ve İHTİYATLI olan seçilir
 *   2. kararsız ölçüm ÖNBELLEĞE GİRMEZ (yazı-tura dondurulmaz)
 *   3. ölçümler uyuşursa önbelleğe girer ve ikinci koşu 0 token harcar
 *   4. SDLC_GATE_CONFIRM=0 doğrulamayı kapatır (tek ölçüm)
 */
import { createServer } from "node:http";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";

const HARNESS = process.argv[2];
if (!HARNESS) {
  console.error("kullanim: node fixtures/confirm-freeze.mjs <harness-koku>");
  process.exit(2);
}

const fails = [];
const ok = (cond, what) => { if (!cond) fails.push(what); };

let calls = 0;
let nextValue = () => 0.9;
const srv = createServer((req, res) => {
  res.setHeader("content-type", "application/json");
  if (req.url.endsWith("/models")) {
    res.end(JSON.stringify({ models: [{ name: "jev-latest", release_date: "2026-01-01" }] }));
    return;
  }
  let body = "";
  req.on("data", (d) => { body += d; }).on("end", () => {
    calls++;
    res.end(JSON.stringify({
      model: "stub-1",
      usage: { input_tokens: 100, output_tokens: 5 },
      answers: { q: { type: "noul", noul: nextValue() } },
    }));
  });
});
await new Promise((r) => srv.listen(0, "127.0.0.1", r));

const P = mkdtempSync(resolve(tmpdir(), "confirm-freeze-"));
mkdirSync(resolve(P, "sdlc"), { recursive: true });
writeFileSync(resolve(P, "sdlc/project.json"), '{"schemaVersion":1,"name":"s","stacks":[]}');
process.env.SDLC_PROJECT_ROOT = P;
process.env.JEV_API_KEY = "stub";
process.env.JEV_API_URL = `http://127.0.0.1:${srv.address().port}/v1/systemone`;
delete process.env.SDLC_GATE_CONFIRM;

const { ask } = await import(`${HARNESS}/gates/jev.ts`);
const cache = await import(`${HARNESS}/gates/cache.ts`);

const qs = [{ id: "q", kind: "noul", prompt: "x" }];
// Cagiranin KENDI saf karar fonksiyonu — karsilastirma nokta tahmini uzerinden
// degil KARAR uzerinden yapilir.
const confirm = { label: (a) => (a.q.value >= 0.5 ? "pass" : "block"), rank: (d) => (d === "pass" ? 0 : 2) };

// 1-2: olcumler ayrissin (0.90 sonra 0.10) -> pass/block
let seq = 0;
nextValue = () => (++seq === 1 ? 0.9 : 0.1);
const before = calls;
const r1 = await ask("kararsiz belge", qs, { confirm });
ok(calls - before === 2, `ayrisma senaryosunda ${calls - before} olcum alindi, 2 olmaliydi`);
ok(!!r1.unstable, "kararsizlik bildirilmedi");
ok(r1.answers.q.value === 0.1, `ihtiyatli olan secilmedi (deger ${r1.answers.q.value})`);
ok(cache.stats().entries === 0, "KARARSIZ OLCUM ONBELLEGE DONDU — yazi-tura donduruldu");

// 3: olcumler uyussun -> onbellege girsin, ikinci kosu bedava olsun
nextValue = () => 0.9;
const r2 = await ask("kararli belge", qs, { confirm });
ok(!r2.unstable, "uyusan olcumler kararsiz sayildi");
ok(cache.stats().entries === 1, `uyusan olcum onbellege girmedi (${cache.stats().entries} kayit)`);
const c3 = calls;
const r3 = await ask("kararli belge", qs, { confirm });
ok(calls === c3, "onbellek isabetinde yine de cagri yapildi");
ok(r3.cached === true, "onbellek isabeti bildirilmedi");
ok((r3.usage?.input_tokens ?? -1) === 0, "onbellek isabeti 0 token yazmadi");

// 4: dogrulama kapatilabilmeli
process.env.SDLC_GATE_CONFIRM = "0";
const c4 = calls;
await ask("ucuncu belge", qs, { confirm });
ok(calls - c4 === 1, `CONFIRM=0 iken ${calls - c4} olcum alindi, 1 olmaliydi`);

srv.close();
if (fails.length) {
  for (const f of fails) console.error(`  - ${f}`);
  process.exit(1);
}
console.log("olc-dogrula-dondur: 4 davranis da dogrulandi");
