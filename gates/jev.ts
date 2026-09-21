/**
 * gates/jev.ts — karar kapılarının TypeSafe (Jev) adaptörü.
 *
 * Sözleşme `https://api.typesafe.ai/openapi.json` (TypeSafe 0.2.0) üzerinden
 * doğrulandı: tek uç `POST /v1/systemone`, tüm sorular tek istekte, her soru
 * kendi adıyla yanıtlanıyor.
 *
 *   JEV_API_KEY var  → gerçek çağrı.
 *   yok              → "offline": hiçbir şey uydurulmaz, her soru confidence 0
 *                      döner ve kapı insana düşer (fail-to-human).
 *
 * Anahtar PROJE kökündeki .env'den okunur (harness'ınkinden değil); gerçek
 * ortam değişkeni onu ezer.
 */

import type { Answer, Answers, Question } from "./questions.ts";
import * as cache from "./cache.ts";
import { projectRoot } from "./root.ts";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const DEFAULT_URL = "https://api.typesafe.ai/v1/systemone";
const DEFAULT_MODEL = "jev-latest";

/**
 * `jev-latest` bir TAKMA ADDIR ve arkasındaki model isim değişmeden kayar.
 * Ölçüldü 22 Eyl 2026: `jev-latest` istendi, yanıt `jev-1.13.0` döndü.
 *
 * Bu iki yeri birden ilgilendirir:
 *   ÖNBELLEK — anahtar yalnızca "jev-latest" olsaydı, model kaydığında eski
 *              kararlar servis edilmeye devam ederdi.
 *   KALİBRASYON — kayıt "kapılar ayırt ediyor" der; ama BAŞKA bir modelle
 *              ölçüldüyse o cümle bu model hakkında hiçbir şey söylemez.
 *
 * Parmak izi `GET /v1/models` ile alınır — TOKEN HARCAMAZ. Alınamazsa istenen
 * ad kullanılır: bir kapı, sürüm bilgisi yok diye durmamalı.
 */
const MODELS_TTL_MS = 6 * 60 * 60 * 1000;
let fingerprintMemo: { at: number; value: string } | null = null;

export async function modelFingerprint(): Promise<string> {
  const wanted = conf("JEV_MODEL", DEFAULT_MODEL);
  if (isOffline()) return wanted;
  if (fingerprintMemo && Date.now() - fingerprintMemo.at < MODELS_TTL_MS) return fingerprintMemo.value;
  try {
    const base = conf("JEV_API_URL", DEFAULT_URL).replace(/\/systemone$/, "/models");
    const res = await fetch(base, {
      headers: { authorization: `Bearer ${process.env.JEV_API_KEY}` },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(String(res.status));
    const json = (await res.json()) as { models?: { name: string; release_date?: string }[] };
    const hit = json.models?.find((m) => m.name === wanted);
    const value = hit?.release_date ? `${wanted}@${hit.release_date}` : wanted;
    fingerprintMemo = { at: Date.now(), value };
    return value;
  } catch {
    return wanted;
  }
}

let envLoaded = false;
function loadEnv(): void {
  if (envLoaded) return;
  envLoaded = true;
  if (process.env.JEV_API_KEY) return;
  // ANAHTAR PROJEDE DURUR, harness'ta degil. Once "bu dosyanin bir ustu" diye
  // araniyordu; harness submodule'e cikinca orasi proje koku olmaktan cikti ve
  // her kapi SESSIZCE offline'a dustu — yani "olcemedim" degil, "hepsini
  // insana dusuruyorum" (olculdu 22 Eyl 2026, dc-archive'da isOffline() true).
  // Harness koku yine de denenir: eski duzen ve harness'in kendi testleri icin.
  const roots = [projectRoot(), resolve(dirname(fileURLToPath(import.meta.url)), "..")];
  for (const root of roots) {
    for (const file of [".env", ".env.development"]) {
      try {
        process.loadEnvFile(resolve(root, file));
        if (process.env.JEV_API_KEY) return;
      } catch {
        /* dosya yok — offline moda düşeriz */
      }
    }
  }
}

function conf(name: string, fallback: string): string {
  loadEnv();
  return process.env[name] || fallback;
}

export function isOffline(): boolean {
  loadEnv();
  return !process.env.JEV_API_KEY;
}

export type Usage = { input_tokens: number; output_tokens: number };

/**
 * `opts.cache: false` ÖLÇÜMÜ ZORLAR.
 *
 * Kalibrasyon bunu kullanmak ZORUNDA: işi "aynı girdide aynı cevabı veriyor mu"
 * diye sormak; önbellekten okursa `flapping: 0` her zaman doğru çıkar ve
 * kontrol boş bir güvenceye dönüşür.
 */
export async function ask(
  state: string,
  questions: Question[],
  opts: { cache?: boolean } = {}
): Promise<{ answers: Answers; usage?: Usage; model?: string; cached?: boolean }> {
  if (isOffline()) return { answers: offline(questions) };

  const model = conf("JEV_MODEL", DEFAULT_MODEL);
  const useCache = opts.cache !== false;
  // Anahtar TAKMA ADI degil, takma adin SU ANKI karsiligini tasir: model
  // kaydiginda onbellek kendiliginden gecersizlesir.
  const key = cache.keyOf(useCache ? await modelFingerprint() : model, state, questions);
  if (useCache) {
    const hit = cache.get(key);
    if (hit) {
      cache.noteHit(hit);
      return {
        answers: hit.answers as Answers,
        // Isabet BEDAVADIR; 0 yazmak durustur. Kazanc `gates/cache.ts` sayar.
        usage: { input_tokens: 0, output_tokens: 0 },
        model: hit.model,
        cached: true,
      };
    }
  }

  // Soru adları bizim id'lerimiz; yanıtlar aynı adlarla geri geliyor.
  const body = {
    state,
    model,
    questions: Object.fromEntries(questions.map((q) => [q.id, toApiQuestion(q)])),
  };

  // Gecici API hatalarinda tekrar dene. 21 Eyl 2026'da olculdu: ilk uc cagri
  // 503/503/529 dondu, dorduncusu calisti — ve o tekrari bir AJAN elle yapti.
  // Kapinin ayakta kalmasi bir modelin inisiyatifine birakilamaz.
  const RETRY_ON = new Set([429, 500, 502, 503, 504, 529]);
  let res!: Response;
  let lastError = "";
  for (let attempt = 0; attempt < 4; attempt++) {
    if (attempt > 0) {
      const waitMs = 800 * 2 ** (attempt - 1); // 0.8s · 1.6s · 3.2s
      await new Promise((r) => setTimeout(r, waitMs));
    }
    res = await fetch(conf("JEV_API_URL", DEFAULT_URL), {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${process.env.JEV_API_KEY}`,
      },
      body: JSON.stringify(body),
    });
    if (res.ok) break;
    lastError = `${res.status}`;
    if (!RETRY_ON.has(res.status)) break; // kalici hata: tekrar denemek anlamsiz
  }

  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`jev ${lastError}: ${text.slice(0, 500)} (4 denemede basarisiz)`);
  }

  const json = (await res.json()) as {
    model?: string;
    usage?: Usage;
    answers?: Record<string, Record<string, unknown>>;
  };

  const answers: Answers = {};
  for (const [id, raw] of Object.entries(json.answers ?? {})) {
    answers[id] = fromApiAnswer(id, raw);
  }
  if (useCache) {
    cache.put({ at: new Date().toISOString(), model: json.model ?? model, key, answers, usage: json.usage });
  }
  return { answers, usage: json.usage, model: json.model, cached: false };
}

function toApiQuestion(q: Question): Record<string, unknown> {
  switch (q.kind) {
    case "noul":
      return { type: "noul", instructions: q.prompt, ...(q.criteria ? { criteria: q.criteria } : {}) };
    case "choice":
      return { type: "choice", instructions: q.prompt, criteria: q.criteria };
    case "score":
      return { type: "score", instructions: q.prompt, criteria: q.criteria };
  }
}

/**
 * API yanıt şekli tipe göre değişiyor:
 *   noul   → { noul }                      (confidence YOK)
 *   choice → { choice, confidence, probabilities }
 *   score  → { score, confidence, probabilities, legend }
 *
 * noul'da belirsizliği olasılığın kendisi taşıdığı için confidence 1 yazılır;
 * eşik doğrudan olasılığa uygulanır (bkz. questions.ts → Answer).
 */
function fromApiAnswer(id: string, raw: Record<string, unknown>): Answer {
  const type = String(raw.type ?? "");
  if (type === "noul") {
    return { id, value: Number(raw.noul ?? 0), confidence: 1 };
  }
  if (type === "choice") {
    return {
      id,
      value: String(raw.choice ?? ""),
      probabilities: raw.probabilities as Record<string, number> | undefined,
      confidence: Number(raw.confidence ?? 0),
    };
  }
  return {
    id,
    value: Number(raw.score ?? 0),
    probabilities: raw.probabilities as Record<string, number> | undefined,
    confidence: Number(raw.confidence ?? 0),
  };
}

function offline(questions: Question[]): Answers {
  const out: Answers = {};
  for (const q of questions) {
    // En kötü durumu varsay: kapı insana düşsün, sessizce geçmesin.
    const value: string | number =
      q.kind === "choice"
        ? Object.keys(q.criteria).at(-1) ?? "critical"
        : q.kind === "score"
          ? q.criteria.length - 1
          : 0;
    out[q.id] = { id: q.id, value, confidence: 0 };
  }
  return out;
}
