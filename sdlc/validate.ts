#!/usr/bin/env node
/**
 * sdlc/validate.ts — `sdlc/project.json` gerçekten okunabilir mi.
 *
 *   node sdlc/validate.ts          # denetle, sorunları bas
 *   node sdlc/validate.ts --quiet  # yalnızca çıkış kodu (0 temiz, 1 hata)
 *
 * Neden. Yapılandırma harness'ın TEK projeye özgü girdisiydi ve hiç
 * doğrulanmıyordu: `project.ts` eksik alanı varsayılana düşürüyor, bozuk JSON'u
 * sessizce yutuyordu. Sonuç, çalışmayan bir hat değil — YANLIŞ çalışan bir hat:
 * `changedPattern: "^./"` hiçbir yolu eşleştirmez, o yüzden "değişen dosya yok"
 * denir ve testler "geçti" sayılır (pilot repoda ölçüldü 21 Eyl 2026).
 *
 * Bu yüzden ayrım şudur:
 *   HATA (exit 1) : hattı sessizce yanlış çalıştıracak şey.
 *   UYARI         : dikkat isteyen ama kararı bozmayan şey.
 *
 * Şema sürümü. Tüketen repo harness'ın bir SÜRÜMÜNE sabitlenir (submodule).
 * Yapılandırma şeması değişirse eski dosya sessizce yanlış okunur; bunu
 * görünür kılan tek şey dosyanın kendi `schemaVersion` alanıdır.
 */

import { existsSync, readFileSync, statSync } from "node:fs";
import { resolve } from "node:path";
import { projectRoot } from "../gates/root.ts";

/** Bu harness'ın anladığı şema sürümü. Alan uyumsuz değişince ARTAR. */
export const SCHEMA_VERSION = 1;

export type Problem = { level: "error" | "warn"; where: string; what: string; fix?: string };

function re(pattern: string): string | null {
  try {
    new RegExp(pattern);
    return null;
  } catch (err) {
    return (err as Error).message;
  }
}

/**
 * Desenden temsili bir yol uretir: "^apps/api/" -> "apps/api/x".
 *
 * Yalnizca DUZ metin onekini okur; ilk duzenli-ifade metakarakterinde durur.
 * Onek yoksa null doner — o desen icin ornek uretilemez ve golge kontrolu
 * sessizce atlanir. Yanlis bir ornek uydurup yanlis hata basmaktansa
 * olcmemek dogrudur.
 */
function samplePath(pattern: string): string | null {
  const body = pattern.startsWith("^") ? pattern.slice(1) : pattern;
  let literal = "";
  for (const ch of body) {
    if ("\\.*+?()[]{}|$".includes(ch)) break;
    literal += ch;
  }
  if (!literal) return null;
  return literal.endsWith("/") ? `${literal}x` : literal;
}

export function validate(rawText: string, root: string): Problem[] {
  const p: Problem[] = [];
  const add = (level: Problem["level"], where: string, what: string, fix?: string) =>
    p.push({ level, where, what, fix });

  let cfg: Record<string, any>;
  try {
    cfg = JSON.parse(rawText);
  } catch (err) {
    return [{ level: "error", where: "sdlc/project.json", what: `geçersiz JSON: ${(err as Error).message}` }];
  }
  if (typeof cfg !== "object" || cfg === null || Array.isArray(cfg)) {
    return [{ level: "error", where: "sdlc/project.json", what: "kök bir nesne olmalı" }];
  }

  // --- şema sürümü ---------------------------------------------------------
  const sv = cfg.schemaVersion;
  if (sv === undefined) {
    add("warn", "schemaVersion", `yazılmamış — ${SCHEMA_VERSION} varsayıldı`,
        `"schemaVersion": ${SCHEMA_VERSION} ekleyin`);
  } else if (!Number.isInteger(sv) || sv < 1) {
    add("error", "schemaVersion", `tam sayı olmalı, bulunan: ${JSON.stringify(sv)}`);
  } else if (sv > SCHEMA_VERSION) {
    add("error", "schemaVersion",
        `yapılandırma şema ${sv} yazıyor, bu harness ${SCHEMA_VERSION} anlıyor — HARNESS ESKİ`,
        "git submodule update --remote");
  }

  // --- ad ------------------------------------------------------------------
  if (typeof cfg.name !== "string" || !cfg.name.trim()) {
    add("error", "name", "boş olmayan bir dize olmalı (compose adları ve dataset'ler buradan türer)");
  }

  // --- yığınlar ------------------------------------------------------------
  if (!Array.isArray(cfg.stacks)) {
    add("error", "stacks", "dizi olmalı");
  } else if (cfg.stacks.length === 0) {
    add("error", "stacks", "hiç yığın yok — test fazı hiçbir şey koşmaz ve 'geçti' diyemez",
        "scripts/sdlc/init.sh ile iskeleti yeniden üretin");
  } else {
    const seen = new Set<string>();
    cfg.stacks.forEach((s: any, i: number) => {
      const at = `stacks[${i}]${typeof s?.name === "string" ? ` (${s.name})` : ""}`;
      if (typeof s?.name !== "string" || !s.name.trim()) add("error", at, "name gerekli");
      else if (seen.has(s.name)) add("error", at, `yığın adı yinelenmiş: ${s.name}`);
      else seen.add(s.name);

      if (typeof s?.root !== "string" || !s.root) {
        add("error", at, "root gerekli (yığının dizini, proje köküne göre)");
      } else if (!existsSync(resolve(root, s.root))) {
        add("error", at, `root diye bir dizin yok: ${s.root}`);
      } else if (!statSync(resolve(root, s.root)).isDirectory()) {
        add("error", at, `root bir dizin değil: ${s.root}`);
      }

      if (typeof s?.changedPattern !== "string" || !s.changedPattern) {
        add("error", at, "changedPattern gerekli (hangi değişiklik bu yığına ait)");
      } else {
        const err = re(s.changedPattern);
        if (err) add("error", at, `changedPattern geçersiz düzenli ifade: ${err}`);
        // Kok yigin ozel durumu: degisiklik listesi "tests/x.py" seklinde gelir,
        // "./tests/x.py" seklinde DEGIL. "^./" hicbir yolu eslestirmez ve hat
        // sessizce "degisen dosya yok" der (pilot repoda olculdu).
        else if (/^\^\.\//.test(s.changedPattern)) {
          add("error", at, `changedPattern hiçbir yolu eşleştirmez: ${s.changedPattern}`,
              'kök yığın için "^" kullanın, "^./" değil');
        }
      }

      if (typeof s?.testCommand !== "string" || !s.testCommand.trim()) {
        add("error", at, "testCommand gerekli — yoksa test fazı bu yığında hiçbir şey ölçmez");
      } else if (/(^|\s)vitest(\s|$)/.test(s.testCommand) && !/vitest run/.test(s.testCommand)) {
        add("error", at, `test komutu WATCH modunda açılır ve hattı kilitler: ${s.testCommand}`,
            '"vitest run" yazın');
      }

      for (const f of ["failureFilePattern"] as const) {
        if (typeof s?.[f] === "string") {
          const err = re(s[f]);
          if (err) add("error", at, `${f} geçersiz düzenli ifade: ${err}`);
        }
      }
      if (Array.isArray(s?.infraFailurePatterns)) {
        s.infraFailurePatterns.forEach((pat: any, k: number) => {
          if (typeof pat !== "string") add("error", at, `infraFailurePatterns[${k}] dize olmalı`);
          else { const err = re(pat); if (err) add("error", at, `infraFailurePatterns[${k}] geçersiz: ${err}`); }
        });
      }
      for (const key of ["envFile"] as const) {
        if (s?.[key] !== undefined && typeof s[key] !== "string") add("error", at, `${key} dize olmalı`);
      }
      if (s?.envFiles !== undefined && !Array.isArray(s.envFiles)) {
        add("error", at, "envFiles dizi olmalı");
      }
      if (!s?.soloCommand) {
        add("warn", at, "soloCommand yok — üçgenleme (tek testi yalnız koşturma) yapılamaz");
      }
    });
  }

  // --- yığın seçimi: gölgede kalan yığın var mı ----------------------------
  // Yığın seçimi İLK eşleşmeyi alır (`stackFor`). Daha genel bir desen daha
  // öndeyse, arkasındaki yığına hiçbir değişiklik ulaşmaz: testleri hiç koşmaz
  // ve bunu kimse fark etmez — "geçti" görünür. Monorepo düzenlerinde
  // `^apps/` ile `^apps/api/` yan yana durduğunda olan tam budur.
  if (Array.isArray(cfg.stacks)) {
    const usable = cfg.stacks.filter(
      (s: any) => typeof s?.changedPattern === "string" && !re(s.changedPattern),
    );
    usable.forEach((s: any, i: number) => {
      const sample = samplePath(s.changedPattern);
      if (sample === null) return; // desen bir yol ornegi uretmiyor: sessiz kal
      const winner = usable.find((o: any) => new RegExp(o.changedPattern).test(sample));
      if (winner && winner !== s) {
        add("error", `stacks[${i}] (${s.name})`,
            `bu yığına hiçbir değişiklik ulaşmaz: "${sample}" önce "${winner.name}" yığınına düşüyor`,
            `daha genel olan "${winner.name}" desenini listede sona alın`);
      }
    });
  }

  // --- kritik yüzeyler -----------------------------------------------------
  if (cfg.criticalPaths !== undefined) {
    if (!Array.isArray(cfg.criticalPaths)) add("error", "criticalPaths", "dizi olmalı");
    else cfg.criticalPaths.forEach((c: any, i: number) => {
      if (typeof c?.label !== "string" || !c.label) add("error", `criticalPaths[${i}]`, "label gerekli");
      if (typeof c?.pattern !== "string") add("error", `criticalPaths[${i}]`, "pattern gerekli");
      else { const err = re(c.pattern); if (err) add("error", `criticalPaths[${i}]`, `geçersiz: ${err}`); }
    });
  }
  if (cfg.criticalSurfaces !== undefined && !Array.isArray(cfg.criticalSurfaces)) {
    add("error", "criticalSurfaces", "dizi olmalı");
  }

  // --- hafıza: buraya yazılan her dosya DIŞA AKTARILIR ---------------------
  const mem = cfg.memory;
  if (mem !== undefined) {
    if (typeof mem !== "object" || mem === null) add("error", "memory", "nesne olmalı");
    else {
      for (const k of ["processDataset", "productDataset"] as const) {
        if (mem[k] !== undefined && (typeof mem[k] !== "string" || !mem[k])) {
          add("error", `memory.${k}`, "boş olmayan dize olmalı");
        }
      }
      if (mem.productDocs !== undefined) {
        if (!Array.isArray(mem.productDocs)) add("error", "memory.productDocs", "dizi olmalı");
        else mem.productDocs.forEach((d: any, i: number) => {
          const at = `memory.productDocs[${i}]`;
          if (typeof d !== "string") { add("error", at, "dize olmalı"); return; }
          if (!existsSync(resolve(root, d))) {
            add("warn", at, `dosya yok: ${d} — hafızaya hiçbir şey girmez`);
          }
          // Hafiza bir DISA AKTARIMDIR: bu listedeki her belgenin METNI
          // bulut LLM'ine gider. Sir gibi gorunen bir yol buraya girmemeli.
          if (/(^|\/)(\.env|secrets?|credentials?)(\.|$|\/)/i.test(d)) {
            add("error", at, `sır taşıyor görünen bir yol hafızaya veriliyor: ${d}`,
                "hafızaya giren her belge buluta gönderilir — bu dosyayı listeden çıkarın");
          }
        });
      }
    }
  }

  // --- CI istisna politikası ----------------------------------------------
  if (cfg.ci !== undefined) {
    if (typeof cfg.ci !== "object" || cfg.ci === null) add("error", "ci", "nesne olmalı");
    else if (cfg.ci.requireTicket !== undefined && typeof cfg.ci.requireTicket !== "boolean") {
      add("error", "ci.requireTicket", "true/false olmalı");
    }
  }

  // --- projenin kendi kalibrasyon vakaları ---------------------------------
  // Eksik bir fixture ölçülmeyen bir vakadır: kapı o durumda hiç sınanmaz ama
  // rapor "22 vakanın 22'si tuttu" der. Eskiden bu ancak ÜCRETLİ bir koşuda
  // ortaya çıkıyordu; burada bedava çıkar.
  const cal = cfg.calibration;
  if (cal !== undefined) {
    if (typeof cal !== "object" || cal === null) add("error", "calibration", "nesne olmalı");
    else if (cal.cases !== undefined) {
      if (!Array.isArray(cal.cases)) add("error", "calibration.cases", "dizi olmalı");
      else cal.cases.forEach((c: any, i: number) => {
        const at = `calibration.cases[${i}]`;
        if (typeof c?.fixture !== "string" || !c.fixture) { add("error", at, "fixture gerekli"); return; }
        if (c.fixture.includes("..") || c.fixture.startsWith("/")) {
          add("error", at, `fixture adı sdlc/fixtures içinde olmalı: ${c.fixture}`);
          return;
        }
        if (!existsSync(resolve(root, "sdlc/fixtures", c.fixture))) {
          add("error", at, `fixture yok: sdlc/fixtures/${c.fixture} — bu vaka hiç ölçülmez`);
        }
        if (c.kind === "route") {
          if (typeof c.expect !== "string") add("error", at, "route vakası için expect gerekli");
        } else {
          if (typeof c.gate !== "string" || !c.gate) add("error", at, "gate gerekli");
          if (typeof c.expect !== "string" || !c.expect) add("error", at, "expect gerekli");
        }
        if (typeof c?.because !== "string" || c.because.trim().length < 10) {
          add("warn", at, "gerekçe yok — vakanın neden o kararı beklediği yazılmalı");
        }
      });
    }
  }

  // --- sır taraması istisnaları -------------------------------------------
  const allow = cfg.secrets?.allowPaths;
  if (allow !== undefined) {
    if (!Array.isArray(allow)) add("error", "secrets.allowPaths", "dizi olmalı");
    else allow.forEach((a: any, i: number) => {
      if (typeof a !== "string") { add("error", `secrets.allowPaths[${i}]`, "dize olmalı"); return; }
      if (!existsSync(resolve(root, a))) {
        // Olu istisna sessiz bir risktir: dosya geri gelince tarama onu atlar.
        add("warn", `secrets.allowPaths[${i}]`, `yol yok: ${a} — ölü istisna`);
      }
    });
  }

  return p;
}

const invokedDirectly =
  process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;

if (invokedDirectly) {
  const quiet = process.argv.includes("--quiet");
  const root = projectRoot();
  const path = resolve(root, "sdlc/project.json");
  if (!existsSync(path)) {
    console.error(`sdlc/project.json yok: ${path}`);
    console.error("  üretmek için: scripts/sdlc/init.sh");
    process.exit(1);
  }
  const problems = validate(readFileSync(path, "utf8"), root);
  const errors = problems.filter((x) => x.level === "error");
  if (!quiet) {
    console.log(`yapılandırma denetimi · ${path.replace(root + "/", "")} · şema ${SCHEMA_VERSION}`);
    if (problems.length === 0) console.log("  temiz");
    for (const x of problems) {
      console.log(`  ${x.level === "error" ? "✗" : "•"} ${x.where}: ${x.what}`);
      if (x.fix) console.log(`      → ${x.fix}`);
    }
    if (errors.length) {
      console.log("");
      console.log(`${errors.length} hata — hat bu yapılandırmayla SESSİZCE yanlış çalışır.`);
    }
  }
  process.exit(errors.length ? 1 : 0);
}
