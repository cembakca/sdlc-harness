/**
 * gates/questions.ts — TEK DOSYA.
 *
 * Pipeline'da insanın incelemesi gereken en önemli şey soruların kendisi ve
 * eşik sabitleri. Hepsi burada; başka hiçbir yerde karar sabiti tanımlanmaz.
 * Ajanlar bu dosyaya kendi başına soru eklemez — insanla birlikte düzenlenir.
 *
 * Soru tipleri (Jev / TypeSafe primitives):
 *   choice → listeden biri + her seçeneğin olasılığı + confidence
 *   score  → rubriğe göre puan + seviye olasılıkları + confidence
 *   noul   → önerme doğru mu: 0–1 olasılık
 *
 * NOT: state İngilizce verilir. Türkçe BRD'yi doğrudan gönderme; spec.md
 * zaten İngilizce üretiliyor, kapıya onu besle.
 */

import { loadRoster } from "../sdlc/roster.ts";
import { loadProject } from "../sdlc/project.ts";

export type QuestionKind = "choice" | "score" | "noul";

/**
 * Soru şekli TypeSafe /v1/systemone sözleşmesini birebir izler:
 *   noul   → criteria { true, false }        → yanıt: 0–1 olasılık
 *   choice → criteria { seçim: açıklama }    → yanıt: seçim + olasılıklar
 *   score  → criteria [seviye0, seviye1, …]  → yanıt: beklenen puan (dizinin indeksi)
 */
export type Question =
  | { id: string; kind: "noul"; prompt: string; criteria?: { true?: string; false?: string } }
  | { id: string; kind: "choice"; prompt: string; criteria: Record<string, string> }
  | { id: string; kind: "score"; prompt: string; criteria: string[] };

import { extractCriteria, questionIdOf } from "./criteria.ts";

export type GateName = "spec" | "scope" | "blast" | "review";

export type Gate = {
  name: GateName;
  /** Kapıya verilecek artifact (workflow bunu dosyadan okuyup state olarak yollar). */
  stateHint: string;
  /**
   * Kodun sayabildiğini kod sayar: state modele gitmeden önce buradan geçer ve
   * ölçülebilir olgular (kriter sayısı, dosya sayısı) başa eklenir. Modele
   * "kaç madde var" diye sormak, cetveli tahmine sormaktır.
   */
  prepare?: (state: string) => string;
  /** true ise ürün hafızasından ilgili geçmiş çekilip state'e eklenir. */
  wantsProjectContext?: boolean;
  /**
   * Sabit liste ya da state'ten TUREYEN liste. Spec kapisi ikincisini kullanir:
   * her kabul kriteri icin ayri bir soru uretir (bkz. asagidaki gerekce).
   */
  questions: Question[] | ((state: string) => Question[]);
  /** Sonuçları karara çeviren saf fonksiyon. Eşikler THRESHOLDS'tan gelir. */
  /** `prepared`: prepare() ciktisi — koddan olculen olgular. Kod karar verirken
   *  modelin guvenine degil buna bakar (bkz. blast kapisi). */
  decide: (a: Answers, prepared?: string) => Decision;
};

export type Answer = {
  id: string;
  value: string | number; // choice: seçim, score: puan, noul: 0–1
  probabilities?: Record<string, number>;
  /**
   * 0–1. API `noul` yanıtlarında confidence döndürmüyor — orada belirsizliği
   * olasılığın kendisi taşıyor, bu yüzden adaptör 1 yazar ve eşik olasılığa
   * uygulanır. choice/score yanıtlarında API'nin kendi confidence'ı gelir.
   */
  confidence: number;
};

export type Answers = Record<string, Answer>;

export type Decision = {
  /** Koddan turetilen olcumler — deftere yazilir ve asagi akis (assign.ts) okur. */
  derived?: Record<string, string | number>;
  decision: "pass" | "human" | "block";
  reason: string;
};

// ---------------------------------------------------------------- eşikler

export const THRESHOLDS = {
  /** Bunun altındaki confidence'ta kapı kendi kararına güvenmez → insana döner. */
  minConfidence: 0.7,
  /**
   * spec.md ölçülebilir kabul kriteri taşıyor mu (noul olasılığı).
   * Kalibrasyon: sıkı spec 0.87, belirsiz spec 0.02. Ayrım çok geniş; 0.8
   * sıkı örneğe yakın duruyor ve bilerek öyle bırakıldı — kriterlerin
   * ölçülebilirliği pipeline'ın geri kalanının dayandığı tek şey.
   */
  /**
   * BIR KRITERIN dogrulanabilirlik tabani. Spec'in TAMAMI icin degil.
   *
   * Eskiden tek bir soru vardi: "Every acceptance criterion in this spec is
   * objectively verifiable" — yani N maddenin TUMU uzerinde tek bir olasilik.
   * Bu, madde sayisiyla yapisal olarak coker: baglaç ne kadar uzunsa olasilik o
   * kadar dusuk. Esik 0.80, kalibrasyon fixture'lari uzerinde ayarlanmisti ve o
   * fixture'lar DORT maddelik (955 bayt). Gercek spec'ler oyle degil: F4-1 15
   * madde, M1 44 madde (olculdu 22 Eyl 2026).
   *
   * Sonuc: kapi TITIZLIGI cezalandiriyordu. M1'in ilk turunda bilesik maddeleri
   * bolmesi istendi — dogru spec pratigi — ve bolme madde sayisini 18'den 44'e
   * cikardi; madde KALITESI yukseldigi halde toplam olcum 0.51'den yalnizca
   * 0.59'a gelebildi ve kapi yine durdurdu.
   *
   * Artik her kriter AYRI olculuyor ve bu taban her birine uygulaniyor: 44
   * maddelik bir spec, 4 maddelik bir spec kadar gecebilir. 0.60 uydurma bir
   * sayi degil; gates/diagnose.ts insana zaten bu esikle "dogrulanabilir degil"
   * diyordu (< 0.6 kirmizi, < 0.8 sari).
   *
   * Ayni hastalik `ambiguity` icin bir kez tedavi edilmisti (karar nokta
   * tahminine degil kutleye baglandi); `testable` o ilaci almamisti.
   */
  specCriterionMin: 0.6,
  /**
   * Belirsizlik kararı NOKTA TAHMİNİNE değil OLASILIK KÜTLESİNE bakar:
   * "bu spec'in tasarımı değiştirecek boşluk taşıma olasılığı" (seviye ≥ 3).
   *
   * Neden: 20 Eylül 2026 kalibrasyonu, sıkı yazılmış bir spec'i art arda
   * koşturunca 2.65–2.72 arasında ve confidence'ı 0.70–0.72 arasında salındı.
   * Eşik tam oraya denk geldiği için aynı dosya bir koşuda "pass", diğerinde
   * "human" okudu. Salınan bir kapı, kapı değil kura çekmedir. Puanın kendisi
   * salınırken seviye dağılımı kararlı: sıkı spec'te ≥3 kütlesi ~0.10,
   * belirsiz spec'te ~0.90. Karar artık o kütleye bağlı.
   */
  specAmbiguityRiskMax: 0.25,
  /** Otomatik geçebilecek en yüksek bulgu severity'si. */
  reviewSeverityMax: 2, // 0 none, 1 low, 2 medium, 3 high, 4 critical
  /** Bölünme: birden çok çıktı varken bağlılık bunun altındaysa bölünmeli. */
  scopeCouplingMin: 0.6,
  /** Bölünme: "tek iş" olasılığı bunun üstündeyse ticket bölünmez. */
  scopeSingleMass: 0.6,

  /** Rota: "derin iş" olasılığı bunun üstündeyse kademe deep olur. */
  routeDeepMass: 0.35,
  /** Rota: en yüksek sınıf olasılığı bunun altındaysa mekaniğe düşülmez. */
  routeDecisiveMass: 0.6,

  /** Bu blast-radius sınıfları koşulsuz insan onayı ister. */
  humanRequiredBlast: ["critical"] as const,
} as const;

/**
 * Otomatik review ne kadar temiz görünürse görünsün insan onayı isteyen alanlar.
 * Blast-radius sorusu bu listeyi "critical" olarak etiketler.
 */
/**
 * Otomatik review ne kadar temiz görünürse görünsün insan onayı isteyen alanlar.
 * PROJEYE ÖZGÜ: `sdlc/project.json` içinden gelir — harness başka bir repoya
 * taşındığında burada kod değişmez, yalnızca o dosya değişir.
 */
export const CRITICAL_SURFACES: readonly string[] = loadProject().criticalSurfaces;

/**
 * Dosya yolundan blast radius: PreToolUse hook'u bunu kullanır, model değil.
 * CRITICAL_SURFACES'ın koddaki karşılığı — ikisi birlikte güncellenir.
 */
export const CRITICAL_PATHS: { label: string; pattern: RegExp }[] = loadProject().criticalPaths.map(
  (c) => ({ label: c.label, pattern: new RegExp(c.pattern, "i") })
);

export function classifyPath(file: string): { label: string; pattern: RegExp } | null {
  const rel = file.replace(process.cwd() + "/", "");
  return CRITICAL_PATHS.find((c) => c.pattern.test(rel)) ?? null;
}

// ---------------------------------------------------------------- kapılar

export const GATES: Record<GateName, Gate> = {
  spec: {
    name: "spec",
    stateHint: "The full text of spec.md (English).",
    // Kod ne sayabiliyorsa kod sayar: kriter sayisi modele sorulmaz.
    prepare: (state) => `ACCEPTANCE_CRITERIA_COUNT: ${extractCriteria(state).length}\n\n${state}`,
    questions: (state) => [
      // HER KRITER AYRI SORU. Tek bir "hepsi dogrulanabilir mi" sorusu, madde
      // sayisiyla coken bir baglacti (bkz. THRESHOLDS.specCriterionMin).
      ...extractCriteria(state).map((c) => ({
        id: questionIdOf(c.id),
        kind: "noul" as const,
        prompt:
          `This acceptance criterion is objectively verifiable: a tester could decide ` +
          `pass/fail from it alone, without asking the author what was meant.\n\n${c.id}: ${c.body}`,
        criteria: {
          true: "It names an observable trigger and an observable outcome, or an exact value, field, call or number.",
          false: "It leaves a judgement call open: an undefined term, an unstated source of truth, or a quality word with no number behind it.",
        },
      })),
      {
        id: "ambiguity",
        kind: "score",
        prompt: "Rate how ambiguous this spec is for the engineer who has to implement it.",
        criteria: [
          "No open interpretation: an implementer could not reasonably build the wrong thing.",
          "Trivial gaps only: naming, wording, or details that do not change the design.",
          "Minor gaps an implementer can safely assume without asking anyone.",
          "Real gaps that change the design: a wrong assumption here means rework.",
          "Major contradictions: two parts of the spec ask for different things.",
          "Not implementable as written: the spec does not say what to build.",
        ],
      },
      {
        id: "scope",
        kind: "noul",
        prompt:
          "The spec states what is explicitly out of scope, and the in-scope work is small " +
          "enough to ship in one reviewable change set.",
        criteria: {
          true: "There is an explicit out-of-scope section with real exclusions, and the in-scope work is a handful of related changes.",
          false: "Out of scope is missing or empty, or the in-scope work spans many unrelated areas and should be split.",
        },
      },
    ],
    decide: (a, prepared) => {
      // Not: ambiguity bir score sorusu ve kararı kütleye bağlı, o yüzden
      // confidence kontrolünün dışında — nokta tahmininin confidence'ı
      // kalibrasyonda eşiğin dibinde salınıyordu.
      const low = lowConfidence(a, ["scope"]);
      if (low) return { decision: "human", reason: `low confidence on: ${low}` };

      // Kriter cevaplari `ac_*`; digerleri (ambiguity, scope) disarida kalir.
      const acs = Object.values(a).filter((x) => /^ac_\d/.test(x.id));
      const weak = acs.filter((x) => num(x) < THRESHOLDS.specCriterionMin);
      const mean = acs.length ? acs.reduce((t, x) => t + num(x), 0) / acs.length : 1;
      const derived = {
        criteria: acs.length,
        weak: weak.length,
        testableMean: Number(mean.toFixed(2)),
      };
      if (!acs.length)
        return {
          decision: "block",
          reason: "no acceptance criteria found — expected a '## Acceptance criteria' section with numbered items",
          derived,
        };
      if (weak.length)
        return {
          decision: "block",
          // Gerekce EYLEME DONUSMELI: hangi madde, hangi puan.
          reason:
            `${weak.length}/${acs.length} acceptance criteria are not verifiable ` +
            `(< ${THRESHOLDS.specCriterionMin}): ` +
            weak
              .sort((x, y) => num(x) - num(y))
              .slice(0, 8)
              .map((x) => `${x.id.toUpperCase().replace("_", "-")} ${num(x).toFixed(2)}`)
              .join(", ") + (weak.length > 8 ? ", …" : ""),
          derived,
        };
      const risk = massAtOrAbove(a.ambiguity, 4);
      if (risk > THRESHOLDS.specAmbiguityRiskMax)
        return {
          decision: "block",
          reason:
            `spec risks contradictions / unimplementable criteria with probability ${risk.toFixed(2)} ` +
            `(> ${THRESHOLDS.specAmbiguityRiskMax}) — answer the open questions first`,
          derived,
        };
      if (num(a.scope) < 0.6)
        return { decision: "human", reason: "scope boundaries unclear or change set too large", derived };
      return {
        decision: "pass",
        reason: `spec is testable and bounded (${derived.criteria} criteria, mean ${derived.testableMean})`,
        derived,
      };
    },
  },

  /**
   * Bölünme kapısı — spec ile plan arasında.
   *
   * 21 Eylül 2026'da ölçülen bedel: F4-1'in spec'i 15 kritere çıktı, plan onunla
   * çelişti, Codex "planı aşmadan bu spec'i karşılayamam" diyip durdu ve bir
   * build turu boşa gitti. Bölünmeyen büyük ticket, hattın HER fazında bedel
   * ödetiyor: spec belirsizleşiyor, plan çelişiyor, review dağılıyor, UAT
   * anlaşılmaz oluyor.
   *
   * Ürün hafızası burada devreye giriyor: "bu iş daha önce yapılmış bir şeye mi
   * benziyor" sorusu, projeyi bilmeden cevaplanamaz.
   */
  scope: {
    name: "scope",
    stateHint: "spec.md — the work as specified, before it is planned.",
    wantsProjectContext: true,
    prepare: (state) => {
      const section = state.split(/^##\s+/m).find((s) => /^acceptance criteria/i.test(s)) ?? "";
      const criteria = (section.match(/^\s*\d+b?\.\s/gm) ?? []).length;
      const outOfScope = (state.split(/^##\s+/m).find((s) => /^out of scope/i.test(s)) ?? "")
        .split("\n")
        .filter((l) => /^\s*[-*]\s/.test(l)).length;
      return (
        `COUNTED BY CODE (not estimated): ${criteria} acceptance criteria, ` +
        `${outOfScope} explicit exclusions.\n\n${state}`
      );
    },
    questions: [
      {
        id: "slices",
        kind: "choice",
        prompt:
          "How many independently shippable outcomes does this spec contain? An outcome is " +
          "independently shippable if releasing it alone would be useful to someone and would " +
          "leave the product in a coherent state.",
        criteria: {
          one: "One outcome. Every criterion serves the same single change; shipping half of it helps nobody.",
          two: "Two outcomes that happen to travel together — for example a data/logic change and a separate surface that displays it.",
          several:
            "Three or more outcomes bundled into one ticket: different subsystems, different audiences, or work that could be released weeks apart.",
        },
      },
      {
        id: "coupling",
        kind: "noul",
        prompt:
          "These criteria must ship together: releasing a subset would leave the product broken, " +
          "misleading, or in a half-migrated state.",
        criteria: {
          true: "A partial release breaks an existing flow, or produces data/notifications that contradict what the product says elsewhere.",
          false: "A subset could ship on its own and simply do less; the rest could follow later without harm.",
        },
      },
      {
        id: "precedent_project",
        kind: "noul",
        prompt:
          "The project context above shows this work has a close precedent in this product: " +
          "a similar feature, surface or decision already exists to follow.",
        criteria: {
          true: "The context names an existing feature, roadmap item or decision that this work mirrors.",
          false: "No precedent appears in the context, or the context is empty — this is new ground for the product.",
        },
      },
    ],
    decide: (a) => {
      // KARAR KÜTLEYE BAĞLI, confidence'a değil. Aynı fixture üç koşuda
      // 0.25 / 0.79 / 0.87 confidence verdi (ölçüldü 21 Eyl 2026) — eşik
      // oraya konduğunda kapı kura çekmeye başlıyor. Seçim olasılıkları ise
      // kararlı: "tek iş" dediğinde kütlesi de yüksek kalıyor.
      const p = (a.slices?.probabilities ?? {}) as Record<string, number>;
      const pOne = Number(p.one ?? 0);
      const pSeveral = Number(p.several ?? 0);
      const pTwo = Number(p.two ?? 0);
      const coupling = num(a.coupling);
      const precedent = num(a.precedent_project);

      if (pSeveral >= 0.5 && coupling < THRESHOLDS.scopeCouplingMin)
        return {
          decision: "block",
          reason:
            `üç ya da daha fazla bağımsız çıktı (olasılık ${pSeveral.toFixed(2)}), ` +
            `bağlılık zayıf (${coupling.toFixed(2)}) — planlamadan önce böl`,
        };

      if (pOne >= THRESHOLDS.scopeSingleMass)
        return {
          decision: "pass",
          reason: `tek çıktı (kütle ${pOne.toFixed(2)}), bağlılık ${coupling.toFixed(2)} — tek ticket doğru`,
        };

      if (precedent < 0.4 && pOne < 0.5)
        return {
          decision: "human",
          reason:
            `paketlenmiş iş (tek çıktı kütlesi ${pOne.toFixed(2)}) ve üründe emsali yok ` +
            `(${precedent.toFixed(2)}) — ilk kez yapılan iş bölünmüş halde daha güvenli`,
        };

      return {
        decision: "human",
        reason:
          `bir mi iki iş mi net değil (tek ${pOne.toFixed(2)} · iki ${pTwo.toFixed(2)} · ` +
          `çok ${pSeveral.toFixed(2)}) — bölme kararı insanın`,
      };
    },
  },

  blast: {
    name: "blast",
    stateHint: "plan.md: the ordered tasks and the files each one touches.",

    // MODEL OLCER, KOD KARAR VERIR — bu kapida kural once burada cignendi.
    //
    // Eski tasarim tek soruda dort siniftan birini sectiriyordu ("planin
    // dokundugu EN YUKSEK sinif"). 390 satirlik, 18 dosyaya dokunan gercek bir
    // planda olasilik "logic" ile "critical" arasinda bolunuyor ve guven
    // 0.40-0.53'e dusuyordu; karar da otomatik olarak insana kaliyordu.
    // Olculdu (21 Eyl 2026): F4-1'in 23 "human" kararinin 4'u tam olarak bu.
    //
    // Oysa kritik yuzey tespiti MODEL ISI DEGIL: plan dosyalari listeliyor ve
    // classifyPath() o yollari deterministik olarak siniflandiriyor. Modele
    // yalnizca koddan cikarilamayan sey sorulur: bu degisiklik kullanicinin
    // gorebilecegi bir davranis uretiyor mu, ve geri alinabilir mi.
    prepare: (state) => {
      const files = new Set<string>();
      for (const m of state.matchAll(/`([^`\n]+\.[A-Za-z0-9]+)`/g)) files.add(m[1]);
      const hits = new Map<string, string[]>();
      for (const f of files) {
        const c = classifyPath(f);
        if (!c) continue;
        hits.set(c.label, [...(hits.get(c.label) ?? []), f]);
      }
      const lines = [...hits.entries()].map(
        ([label, fs]) => `  - ${label}: ${fs.slice(0, 4).join(", ")}${fs.length > 4 ? ` (+${fs.length - 4})` : ""}`
      );
      // SAYI BAS, NUMARA YAPMA. Ilk surum "…: none" yazip decide() tarafinda
      // /:\s*(?!none)/ ile bakiyordu; "\s*" sifir bosluk eslesince ileriye bakis
      // DAIMA geciyor ve saf dokuman plani bile "kritik" sayiliyordu (kalibrasyon
      // yakaladi, 21 Eyl 2026). Makine okuyacaksa makine icin yaz.
      const header = `CRITICAL_SURFACE_HITS: ${hits.size}`;
      const detail = lines.length ? `\n${lines.join("\n")}` : "";
      return (
        `${header}${detail}\nFILES LISTED IN PLAN (counted by code): ${files.size}\n\n${state}`
      );
    },

    questions: [
      {
        // KODUN GOREMEDIGI KRITIKLIK. Yol desenleri ucuz ve kesindir ama sigdir:
        // F4-1 musteri URL'leri hakkinda e-posta/webhook/Slack'e bildirim
        // gonderiyordu — KVKK kapsaminda kritik, ama dosya adi
        // "notification_digest.py" oldugu icin hicbir desene takilmiyor
        // (olculdu 21 Eyl 2026). Bu yuzden TEK ve NET bir evet/hayir soruluyor;
        // eski dort secenekli "radius" sorusunun aksine bolunmuyor.
        id: "personal_data",
        kind: "noul",
        prompt:
          "This change causes data identifying a customer or an end user to be stored, logged, exported, or sent outside the system (email, webhook, chat, analytics, third party).",
        criteria: {
          true: "A monitored URL, account, contact address, or any customer-identifying value leaves the system or lands in a new store/log as a result of this change.",
          false: "Only internal state that no one outside the system can attribute to a specific customer.",
        },
      },
      {
        id: "behaviour",
        kind: "noul",
        prompt:
          "This change alters behaviour a user or an integration can observe at runtime.",
        criteria: {
          true: "Application logic, API responses, UI, scheduled jobs, notifications or stored data change in a way someone outside the codebase could notice.",
          false: "Only documentation, comments, tests, or values that are read but never change what the system does (formatting, constants with no behavioural effect).",
        },
      },
      {
        id: "reversible",
        kind: "noul",
        prompt:
          "This change can be rolled back in production within minutes without data loss.",
        criteria: {
          true: "A revert of the code is enough; no irreversible migration, no destructive backfill, no data written that the old code would misread.",
          false: "Rolling back needs a data fix, an irreversible migration ran, or reverting would lose or corrupt data.",
        },
      },
    ],

    decide: (a, prepared) => {
      // Kritik yuzey KODDAN gelir; modelin guveni burada rol oynamaz.
      // prepare() kosmadiysa (prepared yok) EMNIYETLI tarafa dus: insana sor.
      const m = /^CRITICAL_SURFACE_HITS:\s*(\d+)$/m.exec(prepared ?? "");
      const pathCritical = m ? Number(m[1]) > 0 : true;
      const dataCritical = num(a.personal_data) >= 0.6;
      const critical = pathCritical || dataCritical;
      if (critical)
        return {
          decision: "human",
          // TURETILMIS OLCUM: assign.ts guvenlik denetcisinin kademesini
          // blast.radius'tan okuyor. Radius artik modele SORULMUYOR, kodla
          // turetiliyor — ama defterde durmali, yoksa asagi akistaki rol
          // sinyali SESSIZCE kopar (olculdu 21 Eyl 2026: reviewer_security
          // "complexity(fallback)"e dusmustu ve kimse fark etmemisti).
          derived: { radius: "critical" },
          reason:
            pathCritical
              ? "touches a critical surface (matched by code) — human approval required regardless of review verdict"
              : "customer-identifying data leaves the system — human approval required regardless of review verdict",
        };
      const low = lowConfidence(a);
      const radiusNow = num(a.behaviour) >= 0.6 ? "logic" : "docs/config";
      if (low) return { decision: "human", reason: `low confidence on: ${low}`, derived: { radius: radiusNow } };
      if (num(a.reversible) < 0.6)
        return { decision: "human", reason: "change is not cheaply reversible", derived: { radius: radiusNow } };
      const radius = num(a.behaviour) >= 0.6 ? "logic" : "docs/config";
      return { decision: "pass", reason: `blast radius: ${radius}, reversible`, derived: { radius } };
    },
  },

  review: {
    name: "review",
    stateHint: "REVIEW.md: all findings from the security and architecture reviewers.",
    questions: [
      {
        id: "severity",
        kind: "score",
        prompt: "Rate the severity of the worst unresolved finding in this review.",
        criteria: [
          "No findings, or every finding is already marked fixed.",
          "Low: style, naming, a nit. Nothing a user would ever notice.",
          "Medium: a real bug, but in a path that is not critical and fails visibly.",
          "High: data loss, a broken user flow, or an authorization gap.",
          "Critical: exploitable, or customer data or money is at risk.",
        ],
      },
      {
        id: "spec_conformance",
        kind: "noul",
        prompt: "The reviewed change implements what the spec asked for, with nothing extra.",
        criteria: {
          true: "Every acceptance criterion is addressed and nothing outside the spec was added.",
          false: "A criterion is missing, or the change adds behaviour nobody asked for.",
        },
      },
    ],
    decide: (a) => {
      const low = lowConfidence(a);
      if (low) return { decision: "human", reason: `low confidence on: ${low}` };
      const sev = num(a.severity);
      if (sev >= 3) return { decision: "block", reason: `unresolved severity ${sev} finding` };
      if (sev > THRESHOLDS.reviewSeverityMax)
        return { decision: "human", reason: `severity ${sev} above auto-merge threshold` };
      if (num(a.spec_conformance) < 0.7)
        return { decision: "human", reason: "change drifts from the spec (scope creep or gap)" };
      return { decision: "pass", reason: "no blocking findings, conforms to spec" };
    },
  },
};

// ---------------------------------------------------------------- yönlendirme

export type TierName = "mechanical" | "standard" | "deep";

export type Routing = { tier: TierName; reason: string; confidence: number };

/**
 * Hangi işin hangi kademede koşacağını ölçen kapı.
 *
 * Kademe tanımları sdlc/roster.json'dan gelir — soru metni ile model matrisi
 * aynı yerden beslensin diye. Belirsizlik yukarı yuvarlanır: kademe emin
 * değilse ucuz modele düşmek, pahalı modelde koşmaktan riskli.
 */
export const ROUTE = {
  stateHint: "plan.md (or intent.md before a plan exists): the work to be done.",

  questions(): Question[] {
    const tiers = loadRoster().tiers;
    return [
      {
        id: "complexity",
        kind: "choice",
        prompt:
          "Classify this work so it can be routed to the right model. Pick the highest class it reaches.",
        criteria: Object.fromEntries(
          Object.entries(tiers).map(([name, t]) => [name, t.when])
        ),
      },
      {
        id: "precedent",
        kind: "noul",
        prompt:
          "This repository already contains a close precedent for this work, so an implementer can " +
          "copy an existing pattern rather than invent one.",
        criteria: {
          true: "The plan points at an existing pattern, file or sibling feature that does nearly the same thing.",
          false: "There is no precedent named, or the work is the first of its kind in this codebase.",
        },
      },
    ];
  },

  decide(a: Answers): Routing {
    const probs = (a.complexity?.probabilities ?? {}) as Record<string, number>;
    const picked = String(a.complexity?.value ?? "deep") as TierName;
    const conf = a.complexity?.confidence ?? 0;
    const precedent = num(a.precedent);
    const pDeep = Number(probs.deep ?? 0);
    const top = Math.max(0, ...Object.values(probs).map(Number));

    // Karar NOKTA TAHMINI + CONFIDENCE ile değil, OLASILIK KÜTLESİ ile veriliyor.
    // 21 Eylül 2026'da ölçüldü: aynı plan iki koşuda "deep" ve "standard" okudu,
    // çünkü confidence 0.67–0.72 arasında geziniyordu ve eşik tam 0.70'teydi.
    // Salınan bir yönlendirici, ya parayı ya kaliteyi kura ile harcar.

    // 1. Derin iş olma ihtimali kayda değerse yukarı yuvarla: yanlış kademede
    //    koşan tek bir Codex turu, bir kademe pahalı modelden çok daha pahalı.
    if (pDeep >= THRESHOLDS.routeDeepMass) {
      return {
        tier: "deep",
        reason: `derin iş olasılığı ${pDeep.toFixed(2)} ≥ ${THRESHOLDS.routeDeepMass}`,
        confidence: conf,
      };
    }
    // 2. Sınıflar arasında net bir kazanan yoksa mekaniğe düşme.
    if (top < THRESHOLDS.routeDecisiveMass && picked === "mechanical") {
      return {
        tier: "standard",
        reason: `sınıflar arası ayrım zayıf (en yüksek ${top.toFixed(2)}) — mekanik riskli`,
        confidence: conf,
      };
    }
    // 3. "Mekanik" denmiş ama repo'da emsal yoksa plan göründüğü kadar hazır değil.
    if (picked === "mechanical" && precedent < 0.6) {
      return {
        tier: "standard",
        reason: `mekanik seçildi ama repo'da emsal yok (${precedent.toFixed(2)})`,
        confidence: conf,
      };
    }
    return {
      tier: picked,
      reason: `sınıf ${picked} (kütle ${(probs[picked] ?? 0).toFixed(2)}), emsal ${precedent.toFixed(2)}`,
      confidence: conf,
    };
  },
};

// ---------------------------------------------------------------- rol ataması

/**
 * Kademe atamasında EKSİK olan iki sinyal.
 *
 * Geri kalanı zaten ölçülüyor: belirsizlik spec kapısında, yarıçap blast
 * kapısında, bulgu ağırlığı review kapısında. Rota bunları yeniden sormaz —
 * defterden okur. Burada yalnızca hiçbir kapının cevaplamadığı iki şey var.
 */
export const ASSIGN_QUESTIONS: Question[] = [
  {
    id: "audience",
    kind: "choice",
    prompt:
      "Who will act on this change once it ships, and what does a misunderstanding cost them?",
    criteria: {
      internal:
        "Only the engineering team sees it: a script, a job, an internal metric. A confusing handover costs an engineer an hour.",
      operator:
        "Someone running the product acts on it — support, ops, an admin screen. A confusing handover means wrong operational decisions until corrected.",
      customer:
        "It changes what a paying customer sees, is billed for, or is notified about. A confusing handover reaches people outside the company and costs trust or money.",
    },
  },
  {
    id: "verification_surface",
    kind: "choice",
    prompt:
      "What does it take to prove this change works? Pick the hardest thing a test must do.",
    criteria: {
      pure:
        "Call a function with inputs and compare the output. No clock, no concurrency, no external service.",
      stateful:
        "Set up state (database rows, documents) and assert state afterwards. Deterministic, but needs fixtures.",
      temporal:
        "Depends on time, ordering, concurrency, retries or an external service. Proving it means controlling something that does not hold still.",
    },
  },
];

// ---------------------------------------------------------------- paylaşılan metin

/**
 * Denetçilere verilecek severity merdiveni — kapının kullandığı rubriğin ta kendisi.
 *
 * 21 Eylül 2026'da ölçüldü: denetçiler "hiç test yazılmamış" bulgusunu critical
 * etiketledi, oysa rubrikte critical = sömürülebilir açık ya da müşteri verisi /
 * para riski. Kapı doğru kararı verdi ama yanlış gerekçeyle; denetçi ile kapı
 * aynı merdiveni okumazsa bulgu ağırlıkları enflasyona uğrar.
 */
export function reviewSeverityLadder(): string {
  const q = GATES.review.questions.find((x) => x.id === "severity");
  const levels = q && q.kind === "score" ? q.criteria : [];
  const names = ["none", "low", "medium", "high", "critical"];
  return levels.map((text, i) => `- ${names[i] ?? i}: ${text}`).join("\n");
}

// ---------------------------------------------------------------- yardımcılar

function num(a?: Answer): number {
  return typeof a?.value === "number" ? a.value : Number(a?.value ?? 0);
}

/**
 * Bir score yanıtının belirli seviyenin üstünde toplam olasılığı.
 * Nokta tahmini eşiğin dibinde salınırken kütle kararlı kalıyor.
 */
function massAtOrAbove(a: Answer | undefined, level: number): number {
  const p = a?.probabilities;
  if (!p) return num(a) >= level ? 1 : 0;
  let sum = 0;
  for (const [k, v] of Object.entries(p)) if (Number(k) >= level) sum += Number(v) || 0;
  return sum;
}

function lowConfidence(a: Answers, ids?: string[]): string | null {
  const weak = Object.values(a)
    .filter((x) => !ids || ids.includes(x.id))
    .filter((x) => x.confidence < THRESHOLDS.minConfidence)
    .map((x) => `${x.id} (${x.confidence.toFixed(2)})`);
  return weak.length ? weak.join(", ") : null;
}
