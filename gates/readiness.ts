#!/usr/bin/env node
/**
 * gates/readiness.ts — teslim kapısı. MODEL YOK, yalnızca kayıt okur.
 *
 *   node gates/readiness.ts F4-1
 *
 * Hat UAT paketini üretiyordu ama hiçbir şey land'i engellemiyordu: testler
 * kırmızıyken, critical bulgular açıkken, insan onayı kayda geçmemişken bile
 * "git merge" komutları basılabiliyordu (21 Eyl 2026'da fark edildi).
 *
 * Bu kapı bir yargı üretmez — kayıtları toplar. Yargılar zaten verildi:
 * testler koştu, denetçiler yazdı, kapılar ölçtü, insan onayladı ya da
 * onaylamadı. Burada sorulan tek şey: hepsi aynı anda yeşil mi?
 */

import { existsSync, readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { read, record, verify } from "./journal.ts";
import { projectRoot } from "./root.ts";

const ticket = process.argv[2];
if (!ticket) {
  console.error("usage: node gates/readiness.ts <TICKET>");
  process.exit(1);
}

const root = projectRoot();
const dir = `${root}/docs/sdlc/${ticket}`;
const rows = read(ticket);
const last = (gate: string) => [...rows].reverse().find((r) => r.gate === gate);

const blockers: string[] = [];
const checks: { name: string; ok: boolean; detail: string }[] = [];

const add = (name: string, ok: boolean, detail: string) => {
  checks.push({ name, ok, detail });
  if (!ok) blockers.push(`${name}: ${detail}`);
};

// 1. Artifact'ler var mı
for (const f of ["spec.md", "plan.md", "REVIEW.md", "TESTS.md", "UAT.md"]) {
  add(`artifact ${f}`, existsSync(`${dir}/${f}`), existsSync(`${dir}/${f}`) ? "var" : "eksik");
}

// 1b. DEFTER KURCALANMIS MI — her seyden once.
//
// Bu kapinin butun cevabi deftere dayaniyor: onaylar, testler, birlesme, kademe.
// Defter guvenilir degilse asagidaki hicbir satirin anlami yok. Denetlendi
// 21 Eyl 2026: journal.ts'te hic butunluk kontrolu yoktu — kabuk erisimi olan
// bir ajan sahte bir "approve:blast" satiri ekleyip teslimi acabilirdi.
const sealed = verify(ticket);
add(
  "defter bütünlüğü",
  sealed.ok,
  sealed.ok
    ? sealed.reason
    : `KURCALANMIŞ — ${sealed.reason}. Defter bir kanıttır; bozulduysa ` +
      `aşağıdaki hiçbir kaydın anlamı yok. git ile son temiz hâle dön.`
);

// 2. Kapılar ne dedi — ve "human" diyen her kapının KAYITLI onayı var mı
//
// Onay kuralı TEK YERDE: aşağıdaki gateVerdict(). Daha önce bu mantık yalnızca
// spec/scope/blast/review döngüsünde vardı, postbuild kontrolü ise ayrı yazılmış
// ve "block değilse yeterli" diyordu — yani plan dışı dosya için postbuild
// "human" dediğinde teslim, kayıtlı onay OLMADAN mümkün oluyordu (dış denetimde
// bulundu 21 Eyl 2026). Kural kopyalandığında biri eskiyor; artık kopya yok.
const hashOf = (p?: string) => {
  if (!p) return "";
  try {
    const abs = p.startsWith("/") ? p : `${root}/${p}`;
    return createHash("sha256").update(readFileSync(abs)).digest("hex").slice(0, 16);
  } catch {
    return ""; // artifact bir dosya değil (ör. worktree diff'i) — hash yok
  }
};

type Row = { at: string; gate: string; artifact?: string; decision?: string; reason?: string; measures?: Record<string, unknown> };

const gateVerdict = (gate: string, g: Row | undefined): { ok: boolean; detail: string } => {
  if (!g) return { ok: false, detail: "hiç ölçülmemiş" };

  if (g.decision === "block") return { ok: false, detail: `block — ${g.reason}` };

  // Yeşil bir karar, ölçtüğü BELGE değişmişse artık o belge hakkında değildir.
  // spec/plan/REVIEW yeniden yazıldığında eski "pass" geçerli görünüyordu
  // (dış denetimde bulundu 21 Eyl 2026).
  const measuredHash = g.measures?.artifactHash as string | undefined;
  const nowHash = hashOf(g.artifact);
  if (measuredHash && nowHash && measuredHash !== nowHash) {
    return { ok: false, detail: `BAYAT — ${g.decision} kararından sonra belge değişti (${g.artifact}); kapıyı yeniden koştur` };
  }

  if (g.decision === "pass") return { ok: true, detail: "pass" };

  // human: onay kaydı aranır. Onay BELGEYE verilir, ölçüme değil — kapı
  // yeniden ölçülünce onay düşmemeli, belge değişince düşmeli. Aynı kural
  // approve.sh --check içinde de var; ikisi ayrı yazıldığında teslim kapısı
  // geçerli onayları görmedi (ölçüldü 21 Eyl 2026).
  const approval = [...rows].reverse().find((r) => r.gate === `approve:${gate}`) as Row | undefined;
  const approvedHash = approval?.measures?.artifactHash as string | undefined;
  const valid =
    Boolean(approval) &&
    (measuredHash && approvedHash
      ? measuredHash === approvedHash // belge aynı sürümde mi
      : approval!.at >= g.at);        // hash yoksa zaman damgasına düş (AYNI AN dahil:
                                      // saniye çözünürlüğünde yazılan kayıtlarda ">"
                                      // geçerli onayı rastgele düşürüyordu)
  return {
    ok: valid,
    detail: valid
      ? `human, onaylı — ${approval!.reason}`
      : approval
        ? "human, onay var ama BELGE DEĞİŞMİŞ — yeniden onay gerek"
        : `human, KAYITLI ONAY YOK (make sdlc-approve TICKET=${ticket} GATE=${gate} WHY="...")`,
  };
};

for (const gate of ["spec", "scope", "blast", "review"]) {
  const v = gateVerdict(gate, last(gate) as Row | undefined);
  add(`kapı ${gate}`, v.ok, v.detail);
}

// 3. Testler — ve karar GÜNCEL koda mı ait?
//
// Kod değiştikten sonra eski yeşil kayıt geçerli görünüyordu (dış denetimde
// bulundu 21 Eyl 2026). Artık test ve birleşme kararları worktree HEAD'ine
// bağlı: kod ilerlemişse karar bayattır.
// Karsilastirma edilecek HEAD nereden okunur? Sira onemli:
//   1) worktree            — normal yerel akis
//   2) SDLC_HEAD_SHA       — CI acikca soyler (PR'da checkout DETACHED'dir)
//   3) kok repo            — yalnizca GERCEKTEN biletin dalindaysa
//
// CI'da .sdlc-worktrees yoktur; ustelik GitHub bir PR'i varsayilan olarak
// detached HEAD (merge commit) uzerinde checkout eder, yani "kok biletin
// dalinda mi" kosulu HIC gerceklesmez ve bayatlik kontrolu sessizce kapanirdi
// (dis denetimde bulundu 21 Eyl 2026; bir onceki turda eklenen kok-fallback
// yalnizca normal dal checkout'unu kurtariyordu). Bu yuzden CI head SHA'sini
// acikca gecirir ve gecirmedigi durum da gorunur: kaynak "yok" yazilir.
let currentHead = "";
const wtDir = `${root}/.sdlc-worktrees/${ticket}`;
let headSource = "yok";
const gitIn = (d: string, ...args: string[]) =>
  execFileSync("git", ["-C", d, ...args], { encoding: "utf8" }).trim();
const short = (sha: string) => sha.trim().slice(0, 12);

try {
  currentHead = gitIn(wtDir, "rev-parse", "--short=12", "HEAD");
  headSource = "worktree";
} catch {
  const envSha = (process.env.SDLC_HEAD_SHA ?? "").trim();
  if (envSha) {
    currentHead = short(envSha);
    headSource = "SDLC_HEAD_SHA";
  } else {
    try {
      // Detached checkout'ta "rev-parse --abbrev-ref HEAD" = "HEAD"; GitHub PR
      // kosusunda dal adi yalnizca GITHUB_HEAD_REF'te bulunur.
      const branch = gitIn(root, "rev-parse", "--abbrev-ref", "HEAD");
      const ghRef = (process.env.GITHUB_HEAD_REF ?? "").trim();
      const onTicketBranch = branch === `sdlc/${ticket}` || ghRef === `sdlc/${ticket}`;
      if (onTicketBranch) {
        currentHead = gitIn(root, "rev-parse", "--short=12", "HEAD");
        headSource = `dal sdlc/${ticket}`;
      }
    } catch {
      /* git yok */
    }
  }
}
// Kontrol KAPALIYSA bunu SOYLE. currentHead bulunamadiginda staleOf her zaman
// false doner, yani bayatlik kontrolu sessizce devre disi kalir — bu turda
// duzeltilen hatalarin hepsi ayni kaliptan cikti: sessizce kapanan kontrol.
const unverified = (r: { measures?: Record<string, unknown> } | undefined) =>
  Boolean(r?.measures?.headSha) && !currentHead;
const snapshotRows = [last("test"), last("merge"), last("postbuild")];
add(
  "kod anlık görüntüsü",
  !snapshotRows.some(unverified),
  currentHead ? `${currentHead} · ${headSource}` : "kod SHA'sı yok — test ve birleşme kararı doğrulanamaz"
);
if (headSource === "worktree") {
  try {
    execFileSync("bash", [`${root}/scripts/sdlc/worktree-clean.sh`, ticket], { stdio: "ignore" });
    add("iş ağacı", true, "kod değişiklikleri commit edilmiş");
  } catch {
    add("iş ağacı", false, "commit edilmemiş kod var veya ticket dalı yanlış");
  }
}
const mark = (r: { measures?: Record<string, unknown> } | undefined, detail: string) =>
  unverified(r) ? `${detail}  [bayatlık DOĞRULANMADI — kaynak: yok]` : detail;

const staleOf = (r: { measures?: Record<string, unknown> } | undefined) => {
  const sha = r?.measures?.headSha;
  if (!currentHead || typeof sha !== "string" || !sha) return false;
  // Kayitlar farkli uzunlukta kisaltilmis olabilir; onek karsilastirmasi yeter.
  const a = short(sha), b = currentHead;
  return !(a.startsWith(b) || b.startsWith(a));
};

const t = last("test");
add(
  "testler",
  t?.decision === "pass" && !staleOf(t),
  !t
    ? "hiç koşmamış"
    : staleOf(t)
      ? `BAYAT — kod değişti (karar ${t.measures?.headSha}, şimdi ${currentHead} · ${headSource})`
      : mark(t, `${t.decision} — ${t.reason}`)
);

// 4. Açık ağır bulgular — REVIEW.md'den sayılır, modele sorulmaz.
//
// DİKKAT: bir ayrıştırıcının hiçbir şey bulamaması, hiçbir şey olmadığı
// anlamına GELMEZ. 21 Eyl 2026'da denetçiler formatı değiştirdi (tablo yerine
// "### N — high · ..." başlıkları) ve kapı sessizce "ağır bulgu yok" dedi —
// oysa review kapısı aynı dosyada 3.02 ölçmüştü. Artık iki format da okunuyor
// ve okunamıyorsa bu bir ENGEL olarak raporlanıyor.
if (existsSync(`${dir}/REVIEW.md`)) {
  const review = readFileSync(`${dir}/REVIEW.md`, "utf8");
  const lines = review.split("\n");

  // ÖNCE makine bloğu: denetçiler artık ```findings-json fenced blok basıyor.
  // Serbest metin biçimi değişse de bu blok sabit kalır.
  let machineRead = false;
  const machine = review.match(/```findings-json\s*([\s\S]*?)```/);
  if (machine) {
    try {
      const items = JSON.parse(machine[1].trim()) as {
        severity?: string;
        status?: string;
      }[];
      const heavyOpen = items.filter(
        (i) => /^(critical|high)$/i.test(String(i.severity)) && !/fixed|closed/i.test(String(i.status ?? "open"))
      ).length;
      add(
        "ağır açık bulgu",
        heavyOpen === 0,
        heavyOpen === 0 ? `yok (${items.length} bulgu, makine bloğu)` : `${heavyOpen} adet critical/high açık`
      );
      machineRead = true;
    } catch {
      add("ağır açık bulgu", false, "findings-json bloğu bozuk — okunamadı");
      machineRead = true;
    }
  }

  if (!machineRead) {
  // (a) tablo satırı:  | 3 | high | file:line | sec | ... | open |
  const tableRows = lines.filter((l) => /^\|/.test(l) && /\|\s*(critical|high)\s*\|/i.test(l));
  const tableOpen = tableRows.filter((l) => /\bopen\b/i.test(l));

  // (b) başlık satırı: ### 1 — high · arch · `path:line`
  const headingOpen = lines.filter(
    (l) => /^#{2,4}\s*\d+\s*[—-]\s*(critical|high)\b/i.test(l) && !/(✅|fixed|kapand)/i.test(l)
  );

  const parsed = tableRows.length + lines.filter((l) => /^#{2,4}\s*\d+\s*[—-]\s*(critical|high|medium|low)\b/i.test(l)).length;
  const open = tableOpen.length + headingOpen.length;

  if (parsed === 0 && review.length > 400) {
    add(
      "ağır açık bulgu",
      false,
      "REVIEW.md okunamadı (bilinen formatların hiçbirine uymuyor) — sessizce 'bulgu yok' saymıyorum"
    );
  } else {
    add("ağır açık bulgu", open === 0, open === 0 ? "yok" : `${open} adet critical/high açık`);
  }
  }
}

// 5. Birleşmiş hâlde de yeşil mi — "kendi dünyasında yeşil" yetmez
const mg = last("merge") as Row | undefined;
// Birlesme kararini IKI taraf birden bayatlatir: is dali da, taban dal da.
let currentBase = "";
const baseName = (mg?.measures?.base as string) || "";
if (baseName) {
  try {
    currentBase = execFileSync("git", ["-C", root, "rev-parse", "--short=12", baseName], { encoding: "utf8" }).trim();
  } catch {
    /* dal yok */
  }
}
const recordedBase = mg?.measures?.baseSha as string | undefined;
const baseMoved = Boolean(currentBase && recordedBase && currentBase !== recordedBase);
add(
  "birleşme durumu",
  mg?.decision === "pass" && !staleOf(mg) && !baseMoved,
  !mg
    ? "hiç kontrol edilmemiş (make sdlc-merge-check)"
    : staleOf(mg)
      ? `BAYAT — kod değişti (karar ${mg.measures?.headSha}, şimdi ${currentHead} · ${headSource})`
      : baseMoved
        ? `BAYAT — taban dal (${baseName}) ilerledi (kontrol ${recordedBase}, şimdi ${currentBase}); yeniden koştur`
        : mark(mg, `${mg.decision} — ${mg.reason}`)
);

// 6. Build planı karşıladı mı
const pb = last("postbuild") as Row | undefined;
const pbv = gateVerdict("postbuild", pb);
add(
  "plan uygunluğu",
  pbv.ok && !staleOf(pb),
  staleOf(pb)
    ? `BAYAT — kod değişti (karar ${pb?.measures?.headSha}, şimdi ${currentHead} · ${headSource})`
    : mark(pb, pbv.detail)
);

// 7. KADEME UYUMU — atanan kademe gercekten kostu mu?
//
// "Kademe olculur, hissedilmez" sozu, olculen kademenin KOSTUGUNU bilmeyi de
// gerektirir. 21 Eyl 2026'da olculdu: assign.ts her role kademe atiyordu ama
// yalnizca gelistirici icin zorlaniyordu; F4-1'in review'i atanan modelde degil,
// elle yapildi ve bunu hicbir sey sormadi. Atama, kayit olmadan tavsiyedir.
//
// Bu satir TESLIMI DURDURMAZ — hangi modelin "dogru" oldugu bir yargi, kapinin
// isi degil. Ama sessiz de kalmaz: uyusmazlik ve eksik kayit GORUNUR.
try {
  const assignOut = execFileSync("node", [`${root}/gates/assign.ts`, ticket], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  const assignment = (JSON.parse(assignOut).assignment ?? {}) as Record<string, { model?: string }>;
  const ranRows = rows.filter((r) => String(r.gate).startsWith("ran:"));
  const ranBy: Record<string, string> = {};
  for (const r of ranRows) ranBy[String(r.gate).slice(4)] = String(r.measures?.model ?? "");

  const watched = ["implementer", "reviewer_security", "reviewer_spec", "tester"];
  const missing: string[] = [];
  const mismatch: string[] = [];
  for (const role of watched) {
    const want = assignment[role]?.model;
    if (!want) continue;
    const got = ranBy[role];
    if (!got) missing.push(role);
    else if (got !== want) mismatch.push(`${role}: atanan ${want}, koşan ${got}`);
  }
  // UYUSMAZLIK ENGELDIR, EKSIK KAYIT DEGILDIR.
  //
  // Ayrim su: "atanan model opus'tu, kosan haiku" bir ihlaldir — kademe olculdu
  // ve yok sayildi. "Kayit yok" ise yalnizca o rolun elle kosturulmus olmasi
  // demek olabilir; hangi modelin dogru oldugu bir yargi, kapinin isi degil.
  // Once bu satir tumuyle bilgiydi ve bu, "kademe olculur" sozunun yarisini
  // bos birakiyordu (21 Eyl 2026).
  add(
    "kademe uyumu",
    mismatch.length === 0,
    mismatch.length
      ? `UYUŞMAZLIK — ${mismatch.join(" · ")}. Atanan kademe ölçüldü ve yok sayıldı; ` +
        `ya doğru modelle yeniden koştur ya da neden saptığını yaz (make sdlc-assign TICKET=${ticket}).`
      : missing.length
        ? `kayıt yok: ${missing.join(", ")} — elle koşmuş olabilir (scripts/sdlc/ran.sh yazmadı)`
        : "atanan kademeler koştu"
  );
} catch {
  add("kademe uyumu", true, "ölçülemedi (assign okunamadı)");
}

const ready = blockers.length === 0;

console.log(`teslim hazırlığı — ${ticket}\n`);
for (const c of checks) console.log(`  ${c.ok ? "✓" : "✗"} ${c.name.padEnd(22)} ${c.detail}`);
console.log("");
console.log(
  ready
    ? "HAZIR — bütün kayıtlar yeşil. Taşıma kararı yine insanın."
    : `HAZIR DEĞİL — ${blockers.length} engel:\n` + blockers.map((b) => `  • ${b}`).join("\n")
);

record({
  gate: "readiness",
  ticket,
  artifact: `docs/sdlc/${ticket}`,
  decision: ready ? "pass" : "block",
  reason: ready ? "tüm kayıtlar yeşil" : blockers.slice(0, 3).join(" | "),
  measures: { blockers: blockers.length, checks: checks.length },
});

process.exit(ready ? 0 : 20);
