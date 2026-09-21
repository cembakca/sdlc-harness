/**
 * gates/journal.ts — kapı kararlarının defteri.
 *
 * Her ölçüm bir satır olarak `docs/sdlc/<ticket>/decisions.jsonl` dosyasına
 * düşer: hangi kapı, ne karar verdi, hangi sayıyla, ne zaman.
 *
 * Neden: 21 Eylül 2026'ya kadar kapılar karar veriyor ama hiçbir yerde iz
 * bırakmıyordu. Hangi kapının kaç kez neyi durdurduğunu, bir spec'in kaç turda
 * geçtiğini, eşiğin gerçekten ayırt edip etmediğini ölçemiyorduk — yani süreci
 * yönetirken kendi geçmişimize bakamıyorduk.
 *
 * Deftere model dokunmaz; yazan da okuyan da koddur.
 */

import { appendFileSync, mkdirSync, existsSync, readFileSync } from "node:fs";
import { dirname } from "node:path";
import { createHash } from "node:crypto";
import { projectRoot } from "./root.ts";

export type JournalEntry = {
  at: string;
  gate: string;
  ticket: string;
  artifact: string;
  decision: string;
  reason: string;
  measures?: Record<string, number | string>;
  model?: string;
  tokens?: number;
  /** Onceki satirin muhru. Zincirin halkasi. */
  prev?: string;
  /** Bu satirin muhru: hash(prev + satirin geri kalani). */
  seal?: string;
};

/**
 * ZINCIRLEME MUHUR — neden var.
 *
 * Butun kanit sistemi bu deftere dayaniyor: teslim kapisi "insan onayladi mi"
 * sorusunu buradan okuyor. Onaylar BELGENIN hash'ine bagliydi ama defteri
 * kendine baglayan hicbir sey yoktu (denetlendi 21 Eyl 2026: journal.ts'te
 * hash/imza/checksum sayisi SIFIR). Kabuk erisimi olan bir ajan dosyaya
 *     {"gate":"approve:blast","decision":"approved",...}
 * satiri ekleyebilir ve kapi bunu gercek insan onayi sayardi.
 *
 * Her satir bir oncekinin muhrunu tasir; bir satir degistirilir, silinir ya da
 * araya eklenirse zincir o noktadan sonra kopar ve dogrulama nerede koptugunu
 * soyler. Bu KRIPTOGRAFIK IMZA DEGILDIR — deftere yazabilen zinciri yeniden
 * hesaplayabilir. Amaci imza degil, SESSIZ DEGISIKLIGI IMKANSIZ KILMAK:
 * elle duzenleme, kismi geri alma, iki ayri kosunun satirlarinin karismasi.
 */
const GENESIS = "sdlc-journal-v1";

function sealOf(prev: string, entry: Record<string, unknown>): string {
  // Muhur alanlarinin kendisi hesaba girmez; girerse zincir kendini isirir.
  const { seal: _s, prev: _p, ...rest } = entry as Record<string, unknown>;
  return createHash("sha256")
    .update(prev + "\n" + JSON.stringify(rest))
    .digest("hex")
    .slice(0, 16);
}

/** Defterin son muhru — yoksa GENESIS. */
function lastSeal(path: string): string {
  if (!existsSync(path)) return GENESIS;
  const lines = readFileSync(path, "utf8").split("\n").filter(Boolean);
  for (let i = lines.length - 1; i >= 0; i--) {
    try {
      const r = JSON.parse(lines[i]) as JournalEntry;
      if (r.seal) return r.seal;
    } catch {
      /* bozuk satir: bir onceye bak */
    }
  }
  return GENESIS;
}

export type Verdict = {
  ok: boolean;
  lines: number;
  /** Zincirin koptugu ilk satir (1'den baslar), yoksa 0. */
  brokenAt: number;
  reason: string;
};

/**
 * Defteri bastan sona yurur ve muhurlerin tuttugunu dogrular.
 *
 * Miras satirlarin ayri bir ozeti repoya kaydedilir. Ozet, gecmisin gercek insan
 * karari oldugunu kanitlamaz; mevcut Git gecmisine bagli icerigin sessizce
 * degismedigini denetler.
 */
export function verify(ticket: string): Verdict {
  const path = journalPath(ticket);
  if (!existsSync(path)) return { ok: true, lines: 0, brokenAt: 0, reason: "defter yok" };

  const lines = readFileSync(path, "utf8").split("\n").filter(Boolean);
  let prev = GENESIS;
  let sealed = 0;
  let unsealed = 0;
  const legacy: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    let r: JournalEntry;
    try {
      r = JSON.parse(lines[i]) as JournalEntry;
    } catch {
      return { ok: false, lines: lines.length, brokenAt: i + 1, reason: `satir ${i + 1} okunamadi (bozuk JSON)` };
    }
    if (!r.seal) {
      // MIRAS SATIR YALNIZCA ZINCIRIN ONUNDE OLABILIR.
      //
      // Ilk surumde her muhursuz satir "eski kayit" sayilip atlaniyordu ve bu,
      // korumayi tumuyle ise yaramaz kiliyordu: saldirgan seal alanini hic
      // yazmadan sahte bir onay ekler, defter "temiz" derdi (olculdu
      // 21 Eyl 2026 — sahte approve:blast satiri fark edilmedi).
      // Muhur bir kez basladiktan sonra muhursuz satir KURCALAMADIR.
      if (sealed > 0) {
        return {
          ok: false,
          lines: lines.length,
          brokenAt: i + 1,
          reason: `satir ${i + 1}: muhursuz satir zincirin ORTASINDA — sonradan eklenmis`,
        };
      }
      unsealed++;
      legacy.push(lines[i]);
      continue; // muhurden onceki miras satir (yalnizca basta olabilir)
    }
    if (r.prev !== prev) {
      return {
        ok: false,
        lines: lines.length,
        brokenAt: i + 1,
        reason: `satir ${i + 1}: zincir kopuk — onceki muhur ${r.prev ?? "(yok)"}, beklenen ${prev}`,
      };
    }
    if (sealOf(prev, r as unknown as Record<string, unknown>) !== r.seal) {
      return {
        ok: false,
        lines: lines.length,
        brokenAt: i + 1,
        reason: `satir ${i + 1}: icerik muhurle uyusmuyor — sonradan degistirilmis`,
      };
    }
    prev = r.seal;
    sealed++;
  }
  if (unsealed) {
    const anchorPath = `${dirname(path)}/.legacy-sha256`;
    const actual = createHash("sha256").update(legacy.join("\n") + "\n").digest("hex");
    const expected = existsSync(anchorPath) ? readFileSync(anchorPath, "utf8").trim() : "";
    if (expected !== actual) {
      return {
        ok: false,
        lines: lines.length,
        brokenAt: 1,
        reason: expected ? "miras satırlar kayıtlı özetle uyuşmuyor" : "miras satırlar için kayıtlı özet yok",
      };
    }
  }
  return {
    ok: true,
    lines: lines.length,
    brokenAt: 0,
    reason: unsealed ? `${sealed} mühürlü · ${unsealed} özetle bağlı miras satır` : `${sealed} mühürlü satır`,
  };
}

/** docs/sdlc/<TICKET>/... yolundan ticket adını çıkarır. */
export function ticketOf(artifactPath: string): string | null {
  const m = artifactPath.replace(/\\/g, "/").match(/docs\/sdlc\/([^/]+)\//);
  return m ? m[1] : null;
}

export function journalPath(ticket: string): string {
  const root = projectRoot();
  return `${root}/docs/sdlc/${ticket}/decisions.jsonl`;
}

/** Bir kararı deftere yazar. Kanıt kaydı tutulamıyorsa akış durur. */
export function record(entry: Omit<JournalEntry, "at">): void {
  if (!entry.ticket) return;
  const path = journalPath(entry.ticket);
  mkdirSync(dirname(path), { recursive: true });
  const verdict = verify(entry.ticket);
  if (!verdict.ok) throw new Error(`karar defteri bozuk: ${verdict.reason}`);
  const prev = lastSeal(path);
  const row: Record<string, unknown> = { at: new Date().toISOString(), ...entry };
  const seal = sealOf(prev, row);
  appendFileSync(path, JSON.stringify({ ...row, prev, seal }) + "\n", "utf8");
}

export function read(ticket: string): JournalEntry[] {
  const path = journalPath(ticket);
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line) as JournalEntry;
      } catch {
        return null;
      }
    })
    .filter((x): x is JournalEntry => x !== null);
}

/** Defteri insan ve hafıza için okunur markdown'a çevirir. */
export function toMarkdown(ticket: string): string {
  const rows = read(ticket);
  if (!rows.length) return `# Decisions — ${ticket}\n\nNo gate decisions recorded yet.\n`;

  const counts = new Map<string, number>();
  for (const r of rows) counts.set(r.decision, (counts.get(r.decision) ?? 0) + 1);

  const lines = [
    `# Decisions — ${ticket}`,
    "",
    "Every gate measurement on this ticket, written by code at the moment of the decision.",
    "",
    `Total ${rows.length} decisions: ` +
      [...counts.entries()].map(([d, n]) => `${n}× ${d}`).join(", "),
    "",
    "| When | Gate | Decision | Reason | Measures |",
    "|---|---|---|---|---|",
  ];
  for (const r of rows) {
    const measures = r.measures
      ? Object.entries(r.measures)
          .map(([k, v]) => `${k}=${typeof v === "number" ? v.toFixed(2) : v}`)
          .join(" ")
      : "";
    lines.push(
      `| ${r.at.slice(0, 16).replace("T", " ")} | ${r.gate} | **${r.decision}** | ${r.reason.replace(/\|/g, "/")} | ${measures} |`
    );
  }
  lines.push("");
  return lines.join("\n");
}
