/**
 * sdlc.js — BRD → spec → plan → build → review → test → UAT harness.
 *
 * Orkestrasyon burada, bir modelin kafasında değil: sıra, dallanma ve durma
 * koşulu bu script'e ait. Her agent() taze ve dar bir context alır; ana
 * session'a sadece dönen özet girer.
 *
 * Kullanım: make sdlc-orchestrate TICKET=HKA-123
 */

export const meta = {
  name: "sdlc",
  description: "Artifact tabanli teslim zinciri: intent → spec → plan → build → review → test → UAT, aralarinda olculen kapilar",
  whenToUse: "Bir ticket'i BRD'den UAT paketine kadar goturmek icin. args.ticket zorunlu ve docs/sdlc/<ticket>/intent.md onceden var olmali. Tek dosyalik ufak duzeltmeler icin kullanma.",
  phases: [
    { title: "hafiza", detail: "benzer islerde ne ogrendik — Cognee'den gecmisi cek" },
    { title: "olcum", detail: "spec/scope/blast kapilari + kademe + onaylar: TEK cagri" },
    { title: "spec", detail: "intent.md → spec.md, EARS tarzi kabul kriterleriyle" },
    { title: "gate:spec", detail: "kriterler olculebilir mi, belirsizlik ne kadar" },
    { title: "gate:scope", detail: "bu ticket bolunmeli mi — urun hafizasiyla" },
    { title: "plan", detail: "spec.md → plan.md: sirali gorevler, dokunulan dosyalar, rollback" },
    { title: "build", detail: "Codex izole worktree'de uygular, reviewable diff birakir" },
    { title: "gate:postbuild", detail: "build plani karsiladi mi — modelsiz denetim" },
    { title: "gate:blast", detail: "blast radius → gerekirse insan onayi" },
    { title: "review", detail: "capraz model, paralel: guvenlik + spec uyumu" },
    { title: "gate:review", detail: "en agir acik bulgu ne kadar agir" },
    { title: "merge", detail: "taban dalla birlesir ve BIRLESMIS halde test eder" },
    { title: "test", detail: "kod kosturur: scripts/sdlc/test.sh (servisler project.json'dan)" },
    { title: "uat", detail: "UAT.md paketi" },
    { title: "gate:teslim", detail: "butun kayitlar ayni anda yesil mi (modelsiz)" },
  ],
};

if (typeof command !== "function") {
  throw new Error("Güvenilir komut yürütücüsü yok; make sdlc-orchestrate kullan.");
}

// ---------------------------------------------------------------- args

const a = typeof args === "string" ? safeParse(args) : args || {};
const ticket = a.ticket || a.id;

if (!ticket) {
  return {
    started: false,
    next:
      "Bu workflow bir ticket kimliği ister. Kullanıcıya sor, sonra " +
      "make sdlc-orchestrate TICKET=HKA-123 olarak yeniden çağır. " +
      "docs/sdlc/<ticket>/intent.md yoksa önce onu yazdır.",
  };
}
if (typeof ticket !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(ticket) || ticket.includes("..")) {
  throw new Error(`geçersiz ticket: ${ticket}`);
}

// Roller ve modeller sdlc/roster.json'dan gelir; buradaki adlar
// `node sdlc/roster.ts --check` ile o dosyaya karşı doğrulanır.
const dir = `docs/sdlc/${ticket}`;
const wt = `.sdlc-worktrees/${ticket}`;
const skipBuild = a.specOnly === true; // sadece spec+plan üret, kod yazma
// Plan yenileme: spec değişmese de insan planın güncellenmesini isteyebilir
// (ör. plan ile spec arasında sonradan fark edilen bir çelişki varsa).
const forceReplan = a.replan === true;
// DEVRE KESICI: düzeltme turu sonsuza kadar dönemez. Codex bir bulguyu
// kapatırken başkasını bozabilir; iki tur sonra hâlâ kırmızıysa masa insana
// devredilir. Token ve zaman bütçesi, hattın kendi ısrarına feda edilemez.
const MAX_ROUNDS = Number(a.maxRounds ?? 2);
// Spec turu ayri sayilir: build turu pahali ama spec turu SIK — kapi her
// blokladiginda yeni bir Opus belgesi uretiliyor.
const MAX_SPEC_ROUNDS = Number(a.maxSpecRounds ?? 3);

// --- BÜTÇE -----------------------------------------------------------------
//
// Harness bir token bütçesi sunuyor (`budget.total` / `budget.remaining()`) ve
// bu script onu HİÇ kullanmıyordu (denetlendi 21 Eyl 2026: workflow'da bütçe
// kontrolü sıfır). Bütçesiz bir hat, bir düzeltme turunda sessizce üç katına
// çıkabilir; devre kesici (MAX_ROUNDS) tur SAYISINI sınırlıyor ama turun
// BÜYÜKLÜĞÜNÜ sınırlamıyor.
//
// Fail-closed: bütçe biterse hat DURUR ve nerede durduğunu söyler. Yarım
// bırakılmış bir tur, sessizce pahalıya mal olmuş bir turdan iyidir — çünkü
// artifact'ler ve defter yerinde kalır, insan devam ettirmeye karar verir.
const BUDGET_STOP = Number(a.minBudget ?? 40_000); // bu kadar kalınca yeni faza girme
function budgetLeft() {
  try {
    return budget?.total != null ? budget.remaining() : Infinity;
  } catch {
    return Infinity; // bütçe bilinmiyorsa sınırsız davran, ama SESSIZ kalma
  }
}
function budgetCheck(nextPhase) {
  const left = budgetLeft();
  if (left === Infinity) return null;
  if (left > BUDGET_STOP) return null;
  log(`bütçe sınırı: ${Math.round(left / 1000)}k kaldı — "${nextPhase}" fazına girilmiyor`);
  return {
    ticket,
    stoppedAt: nextPhase,
    reason: "budget",
    next:
      `Bütçe tükendi (${Math.round(left / 1000)}k kaldı, eşik ${Math.round(BUDGET_STOP / 1000)}k). ` +
      `Artifact'ler ve karar defteri yerinde; hattı daha büyük bir bütçeyle ` +
      `tekrar koştur ya da kalan fazları elle sürdür.`,
  };
}
{
  const stop = budgetCheck("hafıza");
  if (stop) return stop;
}
// İnsan onayı hattın DIŞINDAN gelir: kapı "human" dediğinde zincir durur ve
// ancak kullanıcı açıkça onaylayıp args.blastApproved=true ile tekrar
// başlattığında devam eder. Modelin kendi kendine onay verebileceği bir yol yok.
/**
 * İnsan onayı bir BAYRAK değil, bir KAYITTIR.
 *
 * Eskiden args.blastApproved=true yeterliydi; onayın kimden geldiği, ne zaman
 * ve neden verildiği hiçbir yere yazılmıyordu (21 Eyl 2026'da fark edildi).
 * Artık onay `scripts/sdlc/approve.sh` ile deftere düşüyor ve kapı o kaydı
 * arıyor — iz bırakmadan geçilemiyor. Onay BELGEYE verilir: belge değişirse
 * düşer, kapı yeniden ölçülünce düşmez.
 *
 * DİKKAT — resume tuzağı: bu kontrol de bir agent() çağrısıdır, yani
 * `resumeFromRunId` ile devam edildiğinde ÖNBELLEKTEN gelir. Onay kaydettikten
 * sonra hattı resume ile değil SIFIRDAN başlat, yoksa "onay yok" cevabı eski
 * koşudan replay edilir (ölçüldü 21 Eyl 2026: hat onaylı olduğu halde aynı
 * kapıda durdu, 17 ms'de, sıfır token harcayarak).
 */
async function approvalOf(gateName) {
  const result = await command("scripts/sdlc/approve.sh", ["--check", ticket, gateName], [0, 1, 2]);
  return result.code === 0 ? result.stdout.trim() : null;
}
/**
 * Kademe ölçümü. Model ve efor seçimini bir modelin sezgisine değil
 * gates/route.ts çıktısına bağlar; ölçüm okunamazsa güvenli tarafta kalır.
 */
async function route(ticketId, label) {
  const raw = (await command("node", ["gates/assign.ts", ticketId])).stdout;
  const parsed = parseJson(raw);
  if (!parsed?.assignment) {
    log(`${label}: atama okunamadı, deep kademesine düşülüyor`);
    return { tier: "deep", assignment: {} };
  }
  const m = parsed.measured || {};
  log(
    `${label}: zorluk ${m.complexity} · okuyucu ${m.audience} · doğrulama ${m.verification_surface}`
  );
  for (const [role, a] of Object.entries(parsed.assignment)) {
    log(`   ${role} → ${a.tier} (${a.model}) ← ${a.signal}`);
  }
  return { tier: m.complexity || "deep", ...parsed };
}

const pick = (routing, role, fallback) => routing.assignment?.[role]?.model || fallback;

/** Kapıyı koştur, dönen JSON metnini ver. */
// TAZE ÖLÇÜMLER. Toplu ön-ölçüm (measured.gates) fazlar BAŞLAMADAN önce koşar;
// spec.md daha yazılmamışken spec kapısı doğal olarak "artifact not found" der.
// Karar doğru yerden alınıyordu ama RAPOR eski ölçümü taşıyordu: insan
// "önceki faz spec üretmedi" diye okuyup olmayan bir sorunu kovalıyordu
// (ilk gerçek workflow koşusunda görüldü, 21 Eyl 2026 — gerçek sebep
// "testable 0.72 < 0.80" idi). Yanlış teşhis, teşhis olmamasından beterdir.
const fresh = {};

async function runGate(phaseName, artifact, label) {
  const out = (await command("node", ["gates/evaluate.ts", phaseName, artifact], [0, 10, 20])).stdout;
  fresh[phaseName] = JSON.parse(out);
  return out;
}

/** Kapı metninden kararı okur. */
function decisionOf(text) {
  const t = String(text || "");
  const m = t.match(/"decision"\s*:\s*"(pass|human|block)"/);
  return m ? m[1] : "unknown";
}

const gate = (phase, artifact) =>
  `node gates/evaluate.ts ${phase} ${artifact} komutunu çalıştır ve dönen JSON'u ` +
  `aynen struct olarak döndür. Kararı sen verme, sadece komutu koştur ve raporla.`;

// ---------------------------------------------------------------- spec

phase("hafıza");
const intentText = (await command("node", ["-e",
  "const fs=require('fs'); console.log(fs.readFileSync(process.argv[1],'utf8').split('\\n').slice(0,40).join(' ').slice(0,4000))",
  `${dir}/intent.md`])).stdout.trim();
const memoryResult = await command("scripts/sdlc/memory.sh", ["recall", intentText], [0, 13, 14]);
const recalled = memoryResult.code === 0 && memoryResult.stdout.trim()
  ? memoryResult.stdout : `HAFIZA-YOK: ${memoryResult.stderr || "hafıza kapalı veya boş yanıt"}`;
// "Hafızada emsal yok" ile "hafızaya soramadım" ayrı şeylerdir: ikincisinde
// kararın dayanağı eksiktir ve bu GÖRÜNÜR olmalı (dış denetimde bulundu
// 21 Eyl 2026 — sağlayıcı kotası bitince recall sessizce boş dönüyordu).
const memoryFailed = /HAFIZA-YOK|KAPALI|cognee kapali|recall (BASARISIZ|REDDEDILDI|yapilmadi)/i.test(
  String(recalled)
);
const memoryNote = memoryFailed ? String(recalled).split("\n")[0].slice(0, 200) : "";
if (memoryFailed) log(`hafıza sorulamadı — ${memoryNote || "sebep bildirilmedi"}`);
const memory = memoryFailed
  ? ""
  : `\n\nKURUM HAFIZASI — benzer işlerde öğrendiklerimiz (Cognee):\n${recalled}\n` +
    `Bunlar geçmiş kararlar; bugünün gerçeğiyle çeliştiğini görürsen koda güven ve çelişkiyi yaz.`;
phase("ölçüm");
// Kaç düzeltme turu döndük? Karar defterindeki build kayıtları sayılır.
const roundCount = parseJson(
  (await command("node", ["--input-type=module", "-e",
    // Defter HARNESS'in kodu, projenin degil: calisma dizini proje koku oldugu
    // icin goreli './gates/...' projede aranir ve bulunamaz.
    "const {read}=await import(process.env.SDLC_HARNESS+'/gates/journal.ts'); console.log(JSON.stringify({rounds:read(process.argv[1]).filter(x=>x.gate==='postbuild').length}))",
    ticket])).stdout
)?.rounds ?? 0;

// SPEC TURU DEVRE KESICI. Build turlarinin siniri vardi, spec turlarinin YOKTU:
// kapi blokladikca analist yeniden yaziyor ve hat kendi israriyla sinirsiz token
// yakabiliyordu. Olculdu 22 Eyl 2026 (M1): uc tur, her turda Opus'la 16 KB spec
// + ~10k token kapi olcumu, ve zayif madde sayisi 11'den 9'a ancak geldi.
// Yakinsamayan bir spec, daha fazla turla degil INSANLA duzelir.
const specBlocks = parseJson(
  (await command("node", ["--input-type=module", "-e",
    // SON GECISTEN BERI kac blok. Toplam blok sayilsaydi kesici bir kez
    // tetiklendikten sonra spec DUZELSE BILE bir daha asla acilmazdi ve tek
    // cikis 'force' olurdu — yani kesici, duzeltmeyi de engellerdi.
    "const {read}=await import(process.env.SDLC_HARNESS+'/gates/journal.ts'); " +
    "const rs=read(process.argv[1]).filter(x=>x.gate==='spec'); " +
    "let n=0; for(const r of rs){ if(r.decision==='pass') n=0; else if(r.decision==='block') n++; } " +
    "console.log(JSON.stringify({n}))",
    ticket])).stdout
)?.n ?? 0;

if (specBlocks >= MAX_SPEC_ROUNDS && !a.force) {
  return {
    ticket,
    stoppedAt: "spec-devre-kesici",
    specBlocks,
    next:
      `Spec kapisi bu bilette ${specBlocks} kez durdurdu (sinir ${MAX_SPEC_ROUNDS}). ` +
      `Yakinsamayan bir spec daha fazla turla duzelmez: ya kapsam cok genis ` +
      `(scripts/sdlc/defer.sh ile bol), ya intent.md belirsiz, ya da kalan maddeler ` +
      `gercekten kod okumadan dogrulanamaz. Son olcum: node gates/flow.ts ${ticket} · ` +
      `madde madde: node gates/diagnose.ts ${dir}/spec.md · ` +
      `bilerek devam: { "ticket": "${ticket}", "force": true }.`,
  };
}

if (roundCount >= MAX_ROUNDS && !a.force) {
  return {
    ticket,
    stoppedAt: "devre-kesici",
    rounds: roundCount,
    next:
      `Bu ticket ${roundCount} düzeltme turu gördü (sınır ${MAX_ROUNDS}). Hat kendi ` +
      `ısrarıyla token yakmasın diye durdu. Seçenekler: (a) kalan bulguları ` +
      `scripts/sdlc/defer.sh ile kendi ticket'larına taşı, (b) planı daralt, ` +
      `(c) bilinçli olarak devam et: { "ticket": "${ticket}", "force": true }.`,
  };
}
// TEK ÇAĞRI, DÖRT ÖLÇÜM. Her ölçüm ayrı bir ajan çağrısıyla yapılıyordu ve her
// ajan sistem promptunu + CLAUDE.md'yi (1.224 token) yeniden ödüyordu; on
// sorgu × ~10k token = koşu başına ~100k token, hiçbiri iş yapmadan.
const measured = parseJson(
  (await command("scripts/sdlc/measure.sh", [ticket, "plan-stage"], [0, 1])).stdout
) || { gates: {}, approvals: {}, assignment: {} };

// Taze ölçüm varsa O geçerlidir; yoksa toplu ön-ölçüme düşülür.
const g = (name) => fresh[name] ?? measured.gates?.[name] ?? {};
const rAnalysis = { tier: measured.assignment?.measured?.complexity ?? "deep", ...measured.assignment };
log(
  `ölçüm: spec=${g("spec").decision ?? "?"} · scope=${g("scope").decision ?? "?"} · ` +
    `blast=${g("blast").decision ?? "?"} · kademe=${rAnalysis.tier}`
);

phase("spec");
// Idempotans: spec.md zaten varsa ve kapısını geçiyorsa yeniden yazılmaz.
// Düzeltme turunda kapıdan geçmiş bir belgeyi silip baştan yazmak, ölçülmüş
// işi çöpe atmaktır (21 Eyl 2026'da fark edildi).
let specDecision = g("spec").decision ?? "unknown";
let spec = "";

let specRewritten = false;

if (specDecision === "pass") {
  log("spec.md var ve kapıyı geçiyor — yeniden üretilmiyor");
  spec = `${dir}/spec.md mevcut ve spec kapısını geçti; bu turda yeniden yazılmadı.`;
} else {
  specRewritten = true;

  // DUZELTME TURUNUN GERI BILDIRIM KANALI.
  //
  // Kapi blokladiginda analist NEDEN bloklandigini hic ogrenmiyordu: bir
  // sonraki kosuda spec'i sifirdan yaziyor, insanin duzeltmesi de cope
  // gidiyordu. Yani dongu vardi ama ogrenme yoktu — ayni belge ayni sekilde
  // yeniden yazilip ayni kapiya tosluyordu (olculdu 22 Eyl 2026, M1'in ilk
  // uctan uca kosusunda: 18 kriterin 17'si esigin altinda kaldi ve hicbiri
  // analiste geri donmedi).
  //
  // Teshis bir model cagrisidir (~6k token) ama bosa giden bir spec turundan
  // ucuzdur; yalnizca ZATEN VAR OLAN ve bloklanan bir belge icin kosar.
  let weakness = "";
  const specOnDisk = parseJson(
    (await command("node", ["-e",
      "console.log(JSON.stringify({exists:require('fs').existsSync(process.argv[1])}))",
      `${dir}/spec.md`])).stdout
  )?.exists === true;

  if (specOnDisk && specDecision !== "unknown") {
    // Kapi artik zayif maddeleri KENDI gerekcesinde adiyla soyluyor (kriter
    // basina olcume gecince). O yuzden ayri bir teshis cagrisi yapilmiyor:
    // ~10k token tasarrufu, ve iki ayri olcumun birbirinden ayrisma riski yok.
    // Gerekce yoksa (eski satir) teshise dusulur.
    const reason = g("spec").reason ?? "";
    const named = /acceptance criteria are not verifiable/.test(reason);
    const detail = named
      ? reason
      : (await command("node", ["gates/diagnose.ts", `${dir}/spec.md`], [0, 1])).stdout;
    weakness =
      `\n\nBU BELGE ZATEN VAR VE KAPI ONU DURDURDU. Kapinin olcumu:\n` +
      `${detail}\n` +
      `BASTAN YAZMA: esigi gecen maddelere dokunma, belgenin geri kalanini koru.\n` +
      `Zayif maddeler icin uc secenek var ve UCU DE MESRU:\n` +
      `  1. YENIDEN YAZ — madde tek bir gozlenebilir tetikleyici ve tek bir gozlenebilir ` +
      `sonuc anlatsin.\n` +
      `  2. BOL — tek maddede birden cok iddia varsa ayri maddelere ayir.\n` +
      `  3. BIRLESTIR YA DA SIL — baska bir maddenin soyledigini tekrar eden madde ` +
      `KALDIRILIR. Madde sayisini korumak diye bir kural YOK; kisa ve ayrik bir liste, ` +
      `uzun ve tekrarli bir listeden iyidir.\n` +
      `Dusuk puanin tipik sebepleri: (a) tek maddede birden cok tetikleyici ve iddia; ` +
      `(b) madde bir UYGULAMA kisitini anlatiyor ("su sabitten turetilmeli") — ` +
      `gozlenebilir davranisa cevrilmeli; (c) madde YAZILI OLMAYAN bir temele atifta ` +
      `bulunuyor ("as it does today", "M1'den onceki halinden fazla degil") — temel ` +
      `acikca yazilmali ya da madde dusmeli; (d) madde var olmayan bir seye atif yapiyor.`;
  }

  log(
    specOnDisk && weakness
      ? `${ticket}: spec.md kapida durdu — zayif maddeler analiste geri veriliyor`
      : `${ticket}: intent.md okunuyor, spec.md üretiliyor`
  );
  spec = await agent(
    `brd-analyst skill'ini oku. ${dir}/intent.md dosyasından ${dir}/spec.md için ` +
      `İngilizce, EARS tarzı ölçülebilir kabul kriterleri, kapsam dışı başlığı ve ` +
      `açık sorular içeren TAM Markdown belgeyi döndür. İlk karakter # olsun. ` +
      `Dosya yazma; belgeyi orkestratör kaydedecek. CEVABIN TAMAMI BELGE OLSUN: giriş cümlesi, açıklama, '---' ayıracı ya da kapanış yorumu ekleme.` + memory + weakness,
    { label: "spec", model: pick(rAnalysis, "analyst", "opus") }
  );
  writeArtifact(`${dir}/spec.md`, spec);
  phase("gate:spec");
  specDecision = decisionOf(await runGate("spec", `${dir}/spec.md`, "gate:spec"));
}

const specApproval = specDecision === "human" ? await approvalOf("spec") : null;
if (specDecision !== "pass" && !specApproval) {
  return {
    ticket,
    stoppedAt: "gate:spec",
    spec,
    gate: g("spec"),
    next:
      `Spec kapısı geçilmedi. Hangi kriterin çektiğini gör: node gates/diagnose.ts ` +
      `${dir}/spec.md — zayıf maddeleri ölçülebilir hale getir, sonra hattı tekrar koş. Kod yazma.`,
  };
}

phase("gate:scope");
// Bölünme kapısı spec ile plan ARASINDA durur. Bölünmeyen büyük ticket hattın
// her fazında bedel ödetiyor: 21 Eyl 2026'da F4-1'in spec'i 15 kritere çıktı,
// plan çelişti ve bir build turu boşa gitti.
if (specRewritten) await runGate("scope", `${dir}/spec.md`, "gate:scope");
const scopeDecision = g("scope").decision ?? "unknown";
const scopeGate = JSON.stringify(g("scope"));
const scopeApproval = scopeDecision === "human" ? await approvalOf("scope") : null;
if (scopeApproval) log(`bölünme kapısı insan onaylı — ${scopeApproval}`);

if (scopeDecision !== "pass" && !scopeApproval) {
  return {
    ticket,
    stoppedAt: "gate:scope",
    spec,
    gate: scopeGate,
    next:
      scopeDecision === "block"
        ? `Bu ticket birden çok bağımsız işi paketliyor. ${dir}/spec.md'yi bölüp ` +
          `her parçayı kendi ticket'ına taşı; sonra hattı her biri için ayrı koştur.`
        : `Bölünme kapısı emin değil — kullanıcıya kapının gerekçesini göster. ` +
          `Bölmemeye karar verilirse onayı KAYDA GEÇİR ve hattı tekrar koş:\n` +
          `  scripts/sdlc/approve.sh ${ticket} scope "<neden bölmüyoruz>"`,
  };
}

phase("plan");
// Aynı idempotans planda da geçerli: plan.md varsa ve blast kapısı bloke
// etmiyorsa yeniden üretilmez.
let blastGate = JSON.stringify(g("blast"));
let blastDecisionRaw = g("blast").decision ?? "unknown";
let plan = "";

// TUTARLILIK: spec bu turda yeniden yazıldıysa plan da yenilenmeli. 21 Eyl 2026
// koşusunda analist spec'i yeniden yazdı (15 kriter, yeni bir UI rozeti dahil),
// plan eski kaldı ve Codex spec ile planın çeliştiğini görüp DURDU — haklıydı.
// İki belge birbirinden ayrılırsa hattın geri kalanı yanlış işi doğru yapar.
const planMissing =
  decisionOf(blastGate) === "unknown" || String(blastGate).includes("artifact not found");

if (planMissing || specRewritten || forceReplan) {
  if (forceReplan && !planMissing) log("plan yenileme istendi — architect planı spec'e göre güncelliyor");
  else if (specRewritten && !planMissing) log("spec yeniden yazıldı — plan da yenileniyor");
  plan = await agent(
    `architect skill'ini oku. ${dir}/spec.md dosyasını ${dir}/plan.md için ` +
      `TAM Markdown plana ayrıştır (plan varsa GÜNCELLE — spec bu turda değiştiyse plan onunla ` +
      `çelişiyor olabilir; her kabul kriterinin bir göreve bağlandığından emin ol). ` +
      `ayrıştır: sıralı görevler, her görev için dokunulan dosyalar, test stratejisi, ` +
      `rollback adımı ve blast-radius etiketi (docs | config | logic | critical). ` +
      `Her görevin "Done when" şartı ölçülebilir olsun — build fazı bu şartla denetleniyor. ` +
      `${dir}/REVIEW.md varsa oradaki açık bulguları kapatacak görevleri de plana ekle ve ` +
      `o bulguların dokunduğu dosyaları Files listelerine yaz — aksi halde build ` +
      `"planda olmayan dosya" diye durur. ` +
      `Kod yazma, dosya yazma. İlk karakter # olsun; tam belgeyi döndür, orkestratör kaydedecek.` + memory,
    { label: "plan", model: pick(rAnalysis, "architect", "opus") }
  );
  writeArtifact(`${dir}/plan.md`, plan);
  phase("gate:blast");
  blastGate = await runGate("blast", `${dir}/plan.md`, "gate:blast");
  blastDecisionRaw = decisionOf(blastGate);
} else {
  log("plan.md var — yeniden üretilmiyor");
  plan = `${dir}/plan.md mevcut; bu turda yeniden yazılmadı.`;
}

// "human" da DURDURUR. 21 Eyl 2026 koşusunda kapı "human" dedi (radius
// confidence 0.53) ve zincir build'e devam etti — insan kapısının atlanması,
// bu hattın var oluş sebebine aykırı. Onay insanın, atlama hakkı kimsenin.
const blastDecision = blastDecisionRaw;
const blastApproval =
  blastDecision === "human"
    ? await approvalOf("blast")
    : null;
if (blastApproval) log(`blast kapısı insan onaylı — ${blastApproval}`);

if (blastDecision !== "pass" && !blastApproval) {
  return {
    ticket,
    stoppedAt: "gate:blast",
    plan,
    gate: blastGate,
    next:
      blastDecision === "human"
        ? `Blast kapısı İNSAN ONAYI istiyor (kritik yüzey ya da güvenilmez ölçüm). ` +
          `Kullanıcıya kapının gerekçesini göster ve açık onay al; onaydan sonra ` +
          `Onayı KAYDA GEÇİR, sonra hattı SIFIRDAN koş (resume değil — onay ` +
          `sorgusu önbellekten gelir):\n` +
          `  scripts/sdlc/approve.sh ${ticket} blast "<neden güvenli>"`
        : `Blast kapısı bloke etti; plan.md'yi düzeltmeden build'e geçme.`,
  };
}

if (skipBuild) {
  return { ticket, spec, plan, next: `specOnly istendi; ${dir}/plan.md hazır, build yapılmadı.` };
}

{
  const stop = budgetCheck("build");
  if (stop) return stop;
}
phase("build");
// DIKKAT: kademe (rBuild) build'den SONRA olculuyor — burada henuz yok.
// Once `rBuild.tier` yaziliyordu ve bu, gecici olu bolge hatasiyla hatti
// build fazina varir varmaz COKERTIYORDU. Kimse gormedi cunku bu faz
// workflow uzerinden hic kosmamisti (olculdu 21 Eyl 2026: 17 ajanin 5'i
// kosmus). Kademeyi burada bildigimiz kaynaktan, analiz olcumunden yaziyoruz.
log(`build Codex'e devrediliyor (izole worktree, kademe: ${rAnalysis.tier})`);

// Build'in plana uymamasi BEKLENEN bir sonuc: onarim dongusu tam bunun icin
// var. Cikis kodunu allowed'a almazsak `command()` ham Error firlatiyor ve
// kosu yigin iziyle oluyor — kapi kararlarinin urettigi yapisal durusun
// yerine cokme geciyor (olculdu 22 Eyl 2026, M1'in build fazinda).
// Cikis kodlari hattin her yerinde ayni anlami tasir: 0 gec, 10 INSANA dus,
// 20 durdur. 10'u "build uymadi" saymak, postbuild kapisinin insana dusen
// kararini bir cokmeye cevirirdi — oysa akisin devaminda zaten onay araniyor
// (olculdu 22 Eyl 2026: sekiz gorev de bitti, testler yesildi, kapi yalnizca
// plandaki bir test dosyasini diff'te goremedigi icin insana dustu).
const build = await command("scripts/sdlc/codex-build.sh", [ticket], [0, 10, 20]);
if (build.code >= 20) {
  return {
    ticket,
    stoppedAt: "build",
    buildExit: build.code,
    diff: build.stdout.slice(-4000),
    next:
      `Build plana uymadan bitti. Codex'in raporu ${dir}/.codex-build.md icinde; ` +
      `postbuild kapisinin "problems" maddeleri yukarida. Once ONLARI kapat, ` +
      `sonra hatti tekrar kostur. Kod yazmasi gereken Codex'tir; plan yanlissa ` +
      `plani duzelt ve --replan ile kos.`,
  };
}
const diff = build.stdout;

phase("gate:postbuild");
// Build sonrası ölçümler de tek çağrıda: plan uygunluğu + commit disiplini + kademe.
const buildMeasured =
  parseJson(
    (await command("scripts/sdlc/measure.sh", [ticket, "build-stage"], [0, 1])).stdout
  ) || {};
const postbuild = JSON.stringify(buildMeasured.postbuild ?? {});
const rBuild = {
  tier: buildMeasured.assignment?.measured?.complexity ?? "deep",
  ...(buildMeasured.assignment ?? {}),
};
if (buildMeasured.commits?.length) log(`commit disiplini: ${buildMeasured.commits[1] ?? ""}`);

const postbuildDecision = decisionOf(postbuild);
const postbuildApproval = postbuildDecision === "human" ? await approvalOf("postbuild") : null;
if (postbuildDecision !== "pass" && !postbuildApproval) {
  return {
    ticket,
    stoppedAt: "gate:postbuild",
    postbuild,
    next:
      `Build planı karşılamıyor (eksik dosya ya da plandaki testler yazılmamış). ` +
      `Review fazına geçme — eksikleri build'e geri gönder: eksik maddeleri ` +
      `${dir}/plan.md'deki görevlere bağlayıp scripts/sdlc/codex-build.sh ${ticket} tekrar koş.`,
  };
}

// ---------------------------------------------------------------- review

{
  const stop = budgetCheck("review");
  if (stop) return stop;
}
phase("review");
log("çapraz model review: güvenlik + mimari, paralel");
await command("bash", ["scripts/sdlc/worktree-clean.sh", ticket]);
const reviewPatch = (await command("scripts/sdlc/review-scope.sh", [ticket, "--patch"])).stdout;
if (!reviewPatch.trim()) throw new Error("review için kod diff'i yok; boş diff temiz sayılmaz");

// Denetçiye NE OKUYACAĞINI kod söyler: ilk turda tüm diff, düzeltme turunda
// yalnızca delta + geçen turun açık bulguları. İnsan code review'ında da ikinci
// turda dosya baştan okunmaz.
const reviewMeta = parseJson(
  (await command("scripts/sdlc/measure.sh", [ticket, "review-stage"], [0, 1])).stdout
) || {};
const rDelivery = {
  tier: reviewMeta.assignment?.measured?.complexity ?? "deep",
  ...(reviewMeta.assignment ?? {}),
};
const scopeRule = `\n\nNE OKUYACAKSIN (kod belirledi, kendin genişletme):\n${reviewMeta.reviewScope ?? "FULL"}\n`;

// Denetçiler kapının kendi severity merdivenini görür — tek kaynak.
const ladder = reviewMeta.severityLadder ?? "";
const machineBlock =
  `\n\nÇIKTININ SONUNA ŞU BLOĞU EKLE (zorunlu, tek satır JSON dizisi):\n` +
  "```findings-json\n" +
  `[{"severity":"high","file":"path.py:120","status":"open","title":"tek cümle"}]\n` +
  "```\n" +
  `Bu blok makine tarafından okunuyor. Serbest metin biçimi değişebilir ama bu blok ` +
  `değişemez — bir ayrıştırıcının bulgu sayamaması, bulgu yok demek değildir ve ` +
  `sessizce "temiz" okunmasına yol açar.`;

const severityRule =
  `\n\nSEVERITY MERDİVENİ (kapının kullandığı rubriğin aynısı — kendi ölçeğini uydurma):\n${ladder}\n` +
  `Eksik test ya da eksik doğrulama tek başına critical DEĞİLDİR; onu kapsamı ` +
  `karşılamayan bir bulgu olarak yaz ve gerçek ağırlığını ver.`;

const [sec, arch] = await parallel([
  () =>
    agent(
      `Aşağıdaki doğrulanmış kod diff'ini oku. Bu değişikliğe saldırgan bir güvenlik ` +
        `review'ı yap. Kodu Codex yazdı; senin işin onun göremediğini görmek. Odak: authz/authn ` +
        `boşlukları, girdi doğrulama, injection, secret sızıntısı, SSRF, KVKK kapsamındaki ` +
        `müşteri verisinin log'a/analitiğe/üçüncü tarafa kaçması. Yazarın yetkin olduğunu ve ` +
        `hatanın ince olduğunu varsay. Kod düzeltme. Her bulgu: \`SEVERITY | dosya:satır | bulgu\` ` +
        `(critical|high|medium|low). Bulgu yoksa tam olarak: NO FINDINGS.` + severityRule + scopeRule + machineBlock +
        `\n\n--- KOD DIFF ---\n${reviewPatch}`,
      { label: "review:sec", model: pick(rBuild, "reviewer_security", "opus") }
    ),
  () =>
    agent(
      `Aşağıdaki doğrulanmış kod diff'ini ${dir}/spec.md ve ${dir}/plan.md karşısında denetle: spec uyumu, ` +
        `mimari tutarlılık, mevcut kodla tekrar, ölü kod, migration/rollback güvenliği. ` +
        `Kod yazma, sadece bulgu üret; her bulgu severity + dosya:satır taşısın.\n\n--- KOD DIFF ---\n${reviewPatch}`,
      { label: "review:arch", model: pick(rBuild, "reviewer_spec", "sonnet") }
    ),
]);

// Denetimin GERCEKTEN hangi modelde kostugunu deftere yaz (atama ile
// karsilastirilabilsin diye — bkz. gates/readiness.ts "kademe uyumu").
await command("scripts/sdlc/ran.sh", [ticket, "reviewer_security", pick(rBuild, "reviewer_security", "opus")]);
await command("scripts/sdlc/ran.sh", [ticket, "reviewer_spec", pick(rBuild, "reviewer_spec", "sonnet")]);

phase("gate:review");
const reviewDocument = await agent(
  `Aşağıdaki bulgulardan ${dir}/REVIEW.md için TAM Markdown belge döndür ` +
    `(severity'ye göre sıralı, findings-json bloğu dahil). İlk karakter # olsun. ` +
    `Dosya yazma; belgeyi orkestratör kaydedecek. CEVABIN TAMAMI BELGE OLSUN: giriş cümlesi, açıklama, '---' ayıracı ya da kapanış yorumu ekleme.\n\n--- GÜVENLİK ---\n${sec}\n\n--- MİMARİ ---\n${arch}`,
  { label: "review:write" }
);
writeArtifact(`${dir}/REVIEW.md`, reviewDocument);
const reviewGate = await runGate("review", `${dir}/REVIEW.md`, "gate:review");

// Review kapısı BLOKE ederse zincir DURUR. Bu kontrol yoktu (21 Eyl 2026'da
// dış denetimde bulundu): kapı "block" diyordu, hat merge/test/UAT'a devam
// edip "zincir bitti" diyordu. Teslim kapısı sonradan yakaladığı için hiçbir
// şey merge edilmedi — ama kırmızı bir iş tamamlanmış gibi sunulabiliyordu.
const reviewDecision = decisionOf(reviewGate);
const reviewApproval =
  reviewDecision === "human" ? (await approvalOf("review")) : null;

if (reviewDecision !== "pass" && !reviewApproval) {
  return {
    ticket,
    stoppedAt: "gate:review",
    review: { sec, arch },
    gate: reviewGate,
    next:
      reviewDecision === "block"
        ? `Review kapısı bloke etti. ${dir}/REVIEW.md içindeki ağır bulgular ` +
          `kapatılmadan test ve UAT fazlarına geçilmez — düzeltme turu için hattı ` +
          `tekrar koş, Codex açık bulguları prompt'unda görecek.`
        : `Review kapısı insan onayı istiyor. Kapının gerekçesini kullanıcıya göster; ` +
          `kabul edilirse: scripts/sdlc/approve.sh ${ticket} review "<neden kabul edilebilir>"`,
  };
}

// ---------------------------------------------------------------- test

phase("merge");
// Birleşme durumu testten ÖNCE: worktree eski bir HEAD'den açıldı, taban dal
// ilerlemiş olabilir. Testlerin "kendi dünyasında" yeşil olması yetmez —
// birleşmiş hâlde de yeşil olmalı. merge-check temiz birleşirse testleri
// birleşmiş hâlde koşturur.
const mergeResult = await command("scripts/sdlc/merge-check.sh", [ticket], [0, 10, 20]);
const mergeOut = mergeResult.stdout;

if (mergeResult.code !== 0) {
  return {
    ticket,
    stoppedAt: "merge",
    merge: mergeOut,
    next:
      `Taban dalla birleşme sorunlu. Çakışma varsa worktree'de çöz ve hattı tekrar koş; ` +
      `birleşmiş hâlde testler kırmızıysa bu, tek başına yeşil olan işin taban dalla ` +
      `çeliştiği anlamına gelir — önce onu düzelt.`,
  };
}

// Üçüncü atama: review kapısı bulgu ağırlığını ölçtükten SONRA. UAT'ın kademesi
// implementasyonun zorluğundan değil, kimin okuyacağından ve kaç ağır bulgunun
// anlatılması gerektiğinden türer — o bilgi ancak burada var.
phase("test");
const testResult = await command("scripts/sdlc/test.sh", [ticket], [0, 10, 20]);
const tests = testResult.stdout;

// Test fazının sonucu KONTROL EDİLİR. Bu da yoktu: script kırmızı dönse bile
// hat UAT üretip bitiyordu. "Yeşil" kaydının gerçekten çalışan testlere
// karşılık gelmesi, bu hattın tek varlık sebebi.
if (testResult.code !== 0) {
  return {
    ticket,
    stoppedAt: "test",
    tests,
    next:
      `Testler kırmızı. ${dir}/TESTS.md içindeki "Real failures" satırına bak: ` +
      `gerçek hata varsa düzeltme turu gerekir. İzolasyon ya da altyapı kusuru ise ` +
      `script bunu zaten ayırıyor ve zinciri durdurmuyordu — bu durumda kırmızı olan gerçek.`,
  };
}

{
  const stop = budgetCheck("uat");
  if (stop) return stop;
}
phase("uat");
const uat = await agent(
  `uat-packager skill'ini oku. ${dir}/ altındaki spec.md, plan.md, REVIEW.md ve ` +
    `test sonuçlarından ${dir}/UAT.md için TAM Markdown belge döndür: senaryolar, ` +
    `hazırlık adımları, bilinen sınırlar, rollback. İlk karakter # olsun. ` +
    `Dosya yazma; belgeyi orkestratör kaydedecek. CEVABIN TAMAMI BELGE OLSUN: giriş cümlesi, açıklama, '---' ayıracı ya da kapanış yorumu ekleme.`,
  { label: "uat", model: pick(rDelivery, "uat", "sonnet") }
);
writeArtifact(`${dir}/UAT.md`, uat);

phase("gate:teslim");
// Teslim kapısı: modelsiz, yalnızca kayıtları okur. Hattın sonunda "hazır mı"
// sorusunun cevabı bir modelin özeti değil, kayıtların kesişimi olmalı.
const readyResult = await command("node", ["gates/readiness.ts", ticket], [0, 20]);
const readiness = readyResult.stdout;
const isReady = readyResult.code === 0;
log(isReady ? "teslim kapısı: HAZIR" : "teslim kapısı: engeller var");

// Faz adi tabloyla ayni: "hafıza" giriste, "hafıza:remember" cikista.
// Ayni adi iki kez kullanmak, gecis tablosunda dongu gibi gorunuyordu.
phase("hafıza:remember");
await command("scripts/sdlc/memory.sh", ["remember-ticket", ticket], [0, 13, 14]);
await command("scripts/sdlc/memory.sh", ["remember-decisions", ticket], [0, 13, 14]);

return {
  ticket,
  artifacts: [`${dir}/spec.md`, `${dir}/plan.md`, `${dir}/REVIEW.md`, `${dir}/UAT.md`],
  spec,
  plan,
  diff,
  tiers: { analiz: rAnalysis.tier, uygulama: rBuild.tier, teslim: rDelivery.tier },
  // Hafıza gerçekten sorulabildi mi: "emsal yok" ile "soramadım" karışmasın.
  memory: memoryFailed ? { consulted: false, reason: memoryNote } : { consulted: true },
  readiness,
  ready: isReady,
  // `specGate` diye bir degisken HIC yoktu — spec kapisinin sonucu g("spec")
  // uzerinden okunuyor. Donus nesnesi hattin en sonunda kuruluyor ve o noktaya
  // hicbir kosuda gelinmemisti, o yuzden bu ReferenceError yillarca sessiz
  // kalabilirdi (olculdu 21 Eyl 2026, kuru kosumda patladi).
  gates: { spec: g("spec"), blast: blastGate, review: reviewGate },
  review: { sec, arch },
  tests,
  uat,
  next: isReady
    ? `Zincir bitti ve teslim kapısı YEŞİL. Taşıma kararı insanın: ` +
      `make sdlc-land TICKET=${ticket} — kapı tekrar koşar, geçerse merge eder.`
    : `Zincir bitti ama hiçbir şey merge edilmedi. Kullanıcıya şunu göster: blast gate ` +
    `sonucu, açık review bulguları, kalan test başarısızlıkları. İnsan onayı gerekiyorsa ` +
    `(gates.blast) bunu açıkça söyle. Onay gelmeden worktree'yi ana branch'e taşıma; ` +
    `taşıma komutu: git -C ${wt} commit → git merge --no-ff sdlc/${ticket}.`,
};

// ---------------------------------------------------------------- yardımcılar

function safeParse(s) {
  try {
    return JSON.parse(s);
  } catch {
    return { ticket: String(s).trim() };
  }
}

function parseJson(text) {
  const t = String(text || "");
  const start = t.indexOf("{");
  const end = t.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    return JSON.parse(t.slice(start, end + 1));
  } catch {
    return null;
  }
}

function blocked(result) {
  const t = String(result || "").toLowerCase();
  return t.includes('"decision": "block"') || t.includes('"decision":"block"');
}
