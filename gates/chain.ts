/**
 * gates/chain.ts — hattın TEK durum makinesi.
 *
 * Neden var. Orkestratör 634 satırlık düz bir script'ti: açık geçiş tablosu
 * yoktu ve 13 ayrı erken `return` vardı (ölçüldü 21 Eylül 2026). On üç ayrı
 * çıkış demek, on üç ayrı yolu tek tek akılda tutmak demek — ve tam da bu
 * yüzden arka %70'te iki çökme yıllarca saklanabilirdi: `rBuild` geçici ölü
 * bölgede, `specGate` hiç tanımlı değil. İkisi de yalnızca o yollar hiç
 * koşmadığı için görünmemişti.
 *
 * Buradaki kazanç bir mimari desen değil. Kazanç şu: geçişler SAYILABİLİR
 * hale gelince, hepsi otomatik olarak sınanabilir. Elle seçilmiş senaryolar
 * yerine tüketici bir sınama.
 *
 * Kural: bir faza yalnızca tablodaki bir önceki fazdan girilebilir. Tabloda
 * olmayan bir geçiş denenirse hat DURUR (fail-closed) — sessizce devam etmez.
 */

export type Phase =
  | "hafıza"
  | "ölçüm"
  | "spec"
  | "gate:spec"
  | "gate:scope"
  | "plan"
  | "gate:blast"
  | "build"
  | "gate:postbuild"
  | "review"
  | "gate:review"
  | "merge"
  | "test"
  | "uat"
  | "gate:teslim"
  | "hafıza:remember"
  | "BITTI";

/**
 * Zincirin ÖBÜR YÜZÜ: bir faza girebilmek için hangi fazların gerçekleşmiş
 * olması gerekir.
 *
 * `TRANSITIONS` tek bir koşunun adım adım gidişini modeller ve orkestratör
 * için doğrudur. Ama defterden geçmişi okumak için yetmez: `measure.sh` birkaç
 * kapıyı TOPLU ölçer, kapılar yeniden koşturulur, iş yineler. Komşuluğa bakan
 * bir okuma bunların hepsini "atlama" sayar — F4-1'de 67 kez saydı, oysa
 * çoğu meşruydu (ölçüldü 22 Eyl 2026).
 *
 * Önkoşul ise sıralamadan bağımsızdır ve asıl güvenceyi söyler: "blast kapısı
 * ölçüldüyse ortada bir plan VARDI", "postbuild ölçüldüyse build KOŞTU".
 * İhlali gerçekten bir şey ifade eder — kapı, okuması gereken kararı
 * okuyamadan ölçmüştür.
 */
export const REQUIRES: Partial<Record<Phase, Phase[]>> = {
  "gate:spec": ["spec"],
  "gate:scope": ["spec"],
  plan: ["gate:spec", "gate:scope"],
  "gate:blast": ["plan"],
  build: ["plan", "gate:blast"],
  "gate:postbuild": ["build"],
  review: ["build"],
  "gate:review": ["review"],
  merge: ["gate:review"],
  test: ["build"],
  uat: ["test", "gate:review"],
  "gate:teslim": ["uat"],
  "hafıza:remember": ["gate:teslim"],
};

/** Bir fazdan geçilebilecek fazlar. "BITTI" = hattın meşru sonu. */
export const TRANSITIONS: Record<Phase, Phase[]> = {
  "hafıza": ["ölçüm"],
  "ölçüm": ["spec", "BITTI"],
  // spec.md zaten varsa ve TOPLU ÖLÇÜMDE kapısı geçmişse, kapı yeniden
  // koşturulmaz ve doğrudan scope'a geçilir. Bu bir atlama değil, idempotans:
  // karar zaten var ve belgenin hash'ine bağlı — yeniden ölçmek yalnızca para
  // ve zaman harcar. Tabloda yazılı olmasının sebebi, yazılı olmayan her
  // geçişin bir gün "acaba kasıtlı mıydı" sorusuna dönüşmesi.
  "spec": ["gate:spec", "gate:scope", "BITTI"],
  // ONARIM DÖNGÜLERİ. Tabloda yalnızca ileri geçişler vardı; gerçek iş ise
  // yineler — kapı reddeder, belge yeniden yazılır, yeniden ölçülür. Bu
  // kenarlar yazılı olmadığı için tablo GERÇEK AKIŞI MODELLEMİYORDU ve tam bu
  // yüzden hiçbir komut ona bakamıyordu: baksaydı normal işi durdururdu
  // (ölçüldü 22 Eyl 2026 — F4-1'in defterinde 67 "kaçak" geçişin çoğu aslında
  // meşru onarımdı).
  "gate:spec": ["gate:scope", "spec", "BITTI"],
  "gate:scope": ["plan", "spec", "BITTI"],
  // specOnly burada durur; plan üretildi, kod yazılmadı.
  //
  // "plan → build" de meşru: plan zaten varsa blast kapısı YENİDEN ÖLÇÜLMEZ,
  // kararı toplu ölçümden gelir. Atlanan şey ölçüm, KARAR DEĞİL — onay kontrolü
  // (kritik yüzey → insan) her durumda koşar. Faz işareti yalnızca kapı
  // gerçekten ölçüldüğünde basılır; tablo "girilen fazları" modeller.
  "plan": ["gate:blast", "build", "BITTI"],
  "gate:blast": ["build", "plan", "BITTI"],
  "build": ["gate:postbuild"],
  // Plana uymuyorsa yeniden build; plan yanlışsa plana dön.
  "gate:postbuild": ["review", "build", "plan", "BITTI"],
  "review": ["gate:review"],
  // Bulgu varsa düzeltme build'e döner — review'ın tek çıkışı merge değildir.
  "gate:review": ["merge", "build", "BITTI"],
  // Birleşmiş hâlde kırmızıysa düzeltme yine build'dedir.
  "merge": ["test", "build", "BITTI"],
  "test": ["uat", "build", "BITTI"],
  "uat": ["gate:teslim"],
  // Teslim kapısı engel gösterirse iş biter değil, geri döner: engel koda
  // aitse build'e, belgeye aitse uat'a.
  "gate:teslim": ["hafıza:remember", "build", "uat"],
  // Teslim kapısı kırmızı olsa bile hafıza yazılır: ne öğrendiğimiz, işin
  // geçip geçmemesinden bağımsızdır. Durdurucu değil, kayıt.
  "hafıza:remember": ["BITTI"],
  BITTI: [],
};

/** Hattın başladığı faz. */
export const START: Phase = "hafıza";

/**
 * Bir fazın DURMA sebebi olabilecek kapıları. Bu fazda "block" ya da onaysız
 * "human" çıkarsa hat BITTI'ye gider; başka bir yere değil.
 */
export const STOPPERS: Partial<Record<Phase, string>> = {
  "gate:spec": "spec",
  "gate:scope": "scope",
  "gate:blast": "blast",
  "gate:postbuild": "postbuild",
  "gate:review": "review",
  test: "test",
};

export function canGo(from: Phase, to: Phase): boolean {
  return (TRANSITIONS[from] ?? []).includes(to);
}

/**
 * Geçişi zorlar. Tabloda olmayan bir geçiş SESSIZCE GEÇMEZ — hat durur.
 *
 * Fail-closed olmasının sebebi: "bilinmeyen durum" ile "iyi durum" aynı şey
 * değildir. Bu oturumun tekrar eden kusuru tam olarak buydu; bir kontrolün
 * cevap verememesi "sorun yok" diye okunuyordu.
 */
export function must(from: Phase, to: Phase): void {
  if (!canGo(from, to)) {
    throw new Error(
      `GEÇERSİZ GEÇİŞ: ${from} → ${to}. İzin verilenler: ${(TRANSITIONS[from] ?? []).join(", ") || "(yok)"}`
    );
  }
}

/** Tablodaki bütün yolları BITTI'ye kadar üretir (döngü yok, sonlu). */
export function allPaths(from: Phase = START, seen: Phase[] = []): Phase[][] {
  if (seen.includes(from)) return []; // döngü koruması
  const path = [...seen, from];
  const next = TRANSITIONS[from] ?? [];
  if (!next.length) return [path];
  return next.flatMap((n) => allPaths(n, path));
}

/** Her fazın erişilebilir olduğunu doğrular — ölü faz kalmasın. */
export function unreachable(): Phase[] {
  const seen = new Set<Phase>();
  for (const p of allPaths()) for (const s of p) seen.add(s);
  return (Object.keys(TRANSITIONS) as Phase[]).filter((p) => !seen.has(p));
}

// CLI: node gates/chain.ts  → tabloyu ve yolları göster
const invokedDirectly =
  process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;
if (invokedDirectly) {
  const paths = allPaths();
  console.log(`faz: ${Object.keys(TRANSITIONS).length} · yol: ${paths.length}\n`);
  for (const [from, to] of Object.entries(TRANSITIONS)) {
    if (!to.length) continue;
    console.log(`  ${from.padEnd(18)} → ${to.join(", ")}`);
  }
  const dead = unreachable();
  console.log(dead.length ? `\nERİŞİLEMEYEN FAZ: ${dead.join(", ")}` : "\nbütün fazlar erişilebilir");
  process.exit(dead.length ? 1 : 0);
}
