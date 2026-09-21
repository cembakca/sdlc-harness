#!/usr/bin/env node
/**
 * gates/cache.ts — aynı girdiye iki kez para ödememek.
 *
 * Ölçüm saf bir fonksiyondur: aynı belge + aynı sorular + aynı model → aynı
 * cevap. Buna rağmen F4-1'de `assign` kapısı aynı `plan.md`'yi **58 kez**
 * ölçtü; 55'i birebir tekrardı ve tek başına 381 bin input token yedi —
 * biletin toplam 587 bin token'ının üçte ikisi (ölçüldü karar defterinden,
 * 22 Eyl 2026).
 *
 * Önbellek yalnızca ucuzluk değil, KARARLILIK da getirir: `jev-latest` bir
 * takma addır ve arkasındaki model kayabilir, dolayısıyla aynı belgeyi iki kez
 * ölçmek iki farklı karar döndürebilir. Aynı girdi aynı kararı okuyorsa kapı
 * çalışma-arası salınamaz.
 *
 * NEREDE SUSMASI GEREKİR: kalibrasyon. Kalibrasyonun işi tam da "aynı girdide
 * aynı cevabı veriyor mu" diye SORMAK; önbellekten okursa `flapping: 0` her
 * zaman doğru çıkar ve kontrol boş bir güvenceye dönüşür. `repeats: 1`
 * hatasının aynısı, başka kılıkta.
 *
 * Kayıt yeri `<proje>/.sdlc-cache/` — git'e girmez. CI zaten modelsiz koşar,
 * o yüzden paylaşılmasının bir faydası yok; paylaşılan bir önbellek ise
 * "kim neyi ölçtü" sorusunu bulanıklaştırır.
 */

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { fromRoot } from "./root.ts";

export type CacheEntry = {
  at: string;
  model: string;
  key: string;
  answers: unknown;
  usage?: { input_tokens: number; output_tokens: number };
};

function dir(): string {
  return fromRoot(".sdlc-cache/gates");
}

/** Girdiyi tek bir kimliğe indirger: model + belge + sorular. */
export function keyOf(model: string, state: string, questions: unknown): string {
  return createHash("sha256")
    .update(model)
    .update("\u0000")
    .update(state)
    .update("\u0000")
    .update(JSON.stringify(questions))
    .digest("hex")
    .slice(0, 32);
}

/**
 * Yaş sınırı. İçerik anahtarı model ADINI tutar ama `jev-latest` takma addır:
 * arkasındaki model isim değişmeden yenilenebilir. Süresiz bir önbellek o
 * durumda eski bir modelin kararını süresiz servis eder.
 */
function ttlDays(): number {
  const raw = Number(process.env.SDLC_GATE_CACHE_TTL_DAYS ?? 14);
  return Number.isFinite(raw) && raw > 0 ? raw : 14;
}

export function disabled(): boolean {
  return process.env.SDLC_GATE_NO_CACHE === "1";
}

export function get(key: string): CacheEntry | null {
  if (disabled()) return null;
  const file = resolve(dir(), `${key}.json`);
  if (!existsSync(file)) return null;
  try {
    const entry = JSON.parse(readFileSync(file, "utf8")) as CacheEntry;
    const ageDays = (Date.now() - new Date(entry.at).getTime()) / 86_400_000;
    if (!Number.isFinite(ageDays) || ageDays > ttlDays()) return null;
    return entry;
  } catch {
    // Bozuk kayit onbellegin isi degil: yok say, yeniden olc.
    return null;
  }
}

export function put(entry: CacheEntry): void {
  if (disabled()) return;
  try {
    mkdirSync(dir(), { recursive: true });
    writeFileSync(resolve(dir(), `${entry.key}.json`), JSON.stringify(entry), "utf8");
  } catch {
    // Onbellege yazamamak olcumu gecersiz kilmaz: sessizce gec.
  }
}

export function stats(): { entries: number; bytes: number; oldestDays: number | null; savedTokens: number } {
  const d = dir();
  if (!existsSync(d)) return { entries: 0, bytes: 0, oldestDays: null, savedTokens: 0 };
  let bytes = 0;
  let oldest: number | null = null;
  let savedTokens = 0;
  const files = readdirSync(d).filter((f) => f.endsWith(".json"));
  for (const f of files) {
    const p = resolve(d, f);
    bytes += statSync(p).size;
    try {
      const e = JSON.parse(readFileSync(p, "utf8")) as CacheEntry & { hits?: number };
      const age = (Date.now() - new Date(e.at).getTime()) / 86_400_000;
      if (oldest === null || age > oldest) oldest = age;
      savedTokens += (e.usage?.input_tokens ?? 0) * (e.hits ?? 0);
    } catch { /* bozuk kayit sayilmaz */ }
  }
  return { entries: files.length, bytes, oldestDays: oldest === null ? null : Math.floor(oldest), savedTokens };
}

/** Bir isabette sayacı artırır — kazancın ölçülebilmesi için. */
export function noteHit(entry: CacheEntry): void {
  try {
    const file = resolve(dir(), `${entry.key}.json`);
    const cur = JSON.parse(readFileSync(file, "utf8")) as CacheEntry & { hits?: number };
    cur.hits = (cur.hits ?? 0) + 1;
    writeFileSync(file, JSON.stringify(cur), "utf8");
  } catch { /* sayac tutulamadi: olcum yine de gecerli */ }
}

export function clear(): number {
  const d = dir();
  if (!existsSync(d)) return 0;
  const n = readdirSync(d).filter((f) => f.endsWith(".json")).length;
  rmSync(d, { recursive: true, force: true });
  return n;
}

const invokedDirectly =
  process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;

if (invokedDirectly) {
  if (process.argv.includes("--clear")) {
    console.log(`${clear()} kayıt silindi · ${dir()}`);
  } else {
    const s = stats();
    console.log(`kapı ölçüm önbelleği · ${dir()}`);
    console.log(`  ${s.entries} kayıt · ${(s.bytes / 1024).toFixed(1)} KB · en eskisi ${s.oldestDays ?? "-"} gün`);
    console.log(`  isabetlerle kazanılan: ${s.savedTokens} input token`);
    if (disabled()) console.log("  SDLC_GATE_NO_CACHE=1 — önbellek KAPALI");
  }
}
