#!/usr/bin/env node
/**
 * gates/hindsight.ts — kapılar ne dedi, gerçekte ne oldu?
 *
 *   node gates/hindsight.ts
 *
 * Eşikler bugün yalnızca fixture'lara karşı kalibre. Gerçek kalibrasyon, teslim
 * edilmiş işlerin sonucuna karşı yapılır: blast "logic" dediği işlerin kaçı
 * olay çıkardı, review "temiz" dediklerinin kaçı geri alındı?
 *
 * Model yok. Yalnızca karar defteri okunur — tahmin ve sonuç yan yana konur.
 * Sonuç kaydı yoksa bunu açıkça söyler; boş bir tabloyu "her şey yolunda" diye
 * sunmak, ölçmemenin en kötü halidir.
 */

import { readdirSync, existsSync } from "node:fs";
import { read } from "./journal.ts";
import { projectRoot } from "./root.ts";

const root = projectRoot();
const dir = `${root}/docs/sdlc`;
if (!existsSync(dir)) {
  console.log("henüz ticket yok");
  process.exit(0);
}

type Row = {
  ticket: string;
  outcome: string;
  what: string;
  radius: string;
  reversible: number | null;
  severity: number | null;
  tier: string;
  blocks: number;
};

const rows: Row[] = [];
for (const d of readdirSync(dir, { withFileTypes: true })) {
  if (!d.isDirectory() || d.name === "templates") continue;
  const entries = read(d.name);
  const outcome = [...entries].reverse().find((r) => r.gate === "outcome");
  if (!outcome) continue;
  const at = (gate: string) => [...entries].reverse().find((r) => r.gate === gate);
  const blast = at("blast");
  const review = at("review");
  const assign = at("assign");
  rows.push({
    ticket: d.name,
    outcome: outcome.decision,
    what: outcome.reason,
    radius: String(blast?.measures?.radius ?? "—"),
    reversible: typeof blast?.measures?.reversible === "number" ? blast.measures.reversible : null,
    severity: typeof review?.measures?.severity === "number" ? review.measures.severity : null,
    tier: assign?.decision ?? "—",
    blocks: entries.filter((r) => r.decision === "block").length,
  });
}

if (!rows.length) {
  console.log(
    "Henüz hiçbir ticket'ın sonucu kaydedilmedi.\n\n" +
      "Eşikler şu an yalnızca fixture'lara karşı kalibre — üretim gerçeğine karşı değil.\n" +
      "İlk teslimden sonra:\n" +
      "  scripts/sdlc/outcome.sh <TICKET> shipped-clean \"iki hafta sorunsuz çalıştı\"\n" +
      "  scripts/sdlc/outcome.sh <TICKET> incident \"bildirim seli, 3 saat sonra kapatıldı\""
  );
  process.exit(0);
}

console.log("ticket        sonuç          blast      geri-al  review  kademe     blok");
console.log("─".repeat(80));
for (const r of rows) {
  console.log(
    `${r.ticket.padEnd(13)} ${r.outcome.padEnd(14)} ${r.radius.padEnd(10)} ` +
      `${(r.reversible?.toFixed(2) ?? "—").padStart(7)} ${(r.severity?.toFixed(2) ?? "—").padStart(7)} ` +
      `${r.tier.padEnd(10)} ${String(r.blocks).padStart(4)}`
  );
}
console.log("─".repeat(80));

const bad = rows.filter((r) => r.outcome === "incident" || r.outcome === "rollback");
const missed = bad.filter((r) => r.radius !== "critical" && (r.severity ?? 0) < 3);
console.log(`${rows.length} sonuçlanmış ticket · ${bad.length} olay/geri alma`);
if (missed.length) {
  console.log(
    `\nKAPILAR KAÇIRDI: ${missed.map((r) => r.ticket).join(", ")} — kapılar "riskli değil" ` +
      `dedi ama üretimde sorun çıktı. Bu vakaları kalibrasyon korpusuna fixture olarak ekle;\n` +
      `eşiği elle indirmek değil, kaçırılan örneği ölçüme sokmak doğru düzeltmedir.`
  );
} else if (bad.length) {
  console.log("\nOlaylar kapıların zaten işaret ettiği işlerde çıktı — ölçüm tuttu.");
} else {
  console.log("\nSonuçlanan işlerin hiçbirinde olay yok.");
}
