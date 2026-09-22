/**
 * gates/criteria.ts — spec.md'deki kabul kriterlerini KOD ile çıkarır.
 *
 * Tek kaynak: hem `gates/diagnose.ts` (insana rapor) hem spec kapısı (karar)
 * aynı listeyi görür. Ayrı ayrı ayrıştırsalardı kapının durdurduğu madde ile
 * insana gösterilen madde farklı olabilirdi.
 *
 * Kodun sayabildiğini kod sayar: "kaç kriter var" sorusunu modele sormak,
 * cetveli tahmine sormaktır.
 */

export type Criterion = { id: string; body: string };

export function extractCriteria(text: string): Criterion[] {
  const section = text.split(/^##\s+/m).find((s) => /^acceptance criteria/i.test(s)) ?? "";
  const out: Criterion[] = [];
  for (const raw of section.split(/\n(?=\s*\d+b?\.\s)/)) {
    const m = raw.match(/^\s*(\d+b?)\.\s([\s\S]+?)(?=\n\s*\n|$)/);
    if (m) out.push({ id: `AC-${m[1]}`, body: m[2].replace(/\s+/g, " ").trim() });
  }
  return out;
}

/** Kriter kimliğinden soru kimliği: `AC-12` → `ac_12`. */
export const questionIdOf = (id: string) => id.toLowerCase().replace(/[^a-z0-9]+/g, "_");
