/**
 * gates/root.ts — proje kökü, harness'ın nerede durduğundan bağımsız.
 *
 * Neden. Kapılar ve script'ler kökü "kendi konumumun iki üstü" diye buluyordu
 * (ölçüldü 21 Eylül 2026: 21 kabuk script'i + 9 gate). Bu, "ben projenin
 * İÇİNDE yaşıyorum" varsayımını koda gömer. Harness ayrı bir repoya alınıp
 * submodule olarak bağlandığında (`<proje>/sdlc-harness/gates/...`) iki üst
 * artık proje kökü değil harness kökü olur — ve her şey sessizce yanlış
 * dizinde çalışır. Sessizce, çünkü dizin VAR; yalnızca yanlış.
 *
 * Sıra (ilk bulunan kazanır):
 *   1. `SDLC_PROJECT_ROOT` — açıkça söylenmiş.
 *   2. Yukarı yürü: `sdlc/project.json` taşıyan ilk dizin. Projeyi proje yapan
 *      şey yapılandırmasıdır; harness'ın kendi reposunda bu dosya yoktur.
 *   3. Bu dosyanın bir üstü — eski davranış, yapılandırma henüz yokken.
 */

import { existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

let cached: string | null = null;

export function projectRoot(): string {
  if (cached) return cached;

  const explicit = process.env.SDLC_PROJECT_ROOT;
  if (explicit) {
    cached = resolve(explicit);
    return cached;
  }

  let d = dirname(fileURLToPath(import.meta.url));
  while (d !== "/" && d !== ".") {
    if (existsSync(resolve(d, "sdlc/project.json"))) {
      cached = d;
      return cached;
    }
    const up = dirname(d);
    if (up === d) break;
    d = up;
  }

  // Yapılandırma yok. Harness submodule olarak bağlıysa bir ÜSTTE proje
  // olabilir: `<proje>/sdlc-harness/gates` → `<proje>`. Buna bakmadan harness
  // kökünü döndürmek, tüketen repoda her şeyi yanlış dizine yöneltir.
  const own = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  const up = dirname(own);
  if (existsSync(resolve(up, ".git")) || existsSync(resolve(up, "sdlc/project.json"))) {
    cached = up;
    return cached;
  }
  cached = own;
  return cached;
}

/** Proje köküne göre yol. */
export function fromRoot(...parts: string[]): string {
  return resolve(projectRoot(), ...parts);
}

/**
 * Harness'ın KENDİ kökü — proje kökünden farklı olabilir.
 *
 * Ayrıldıktan sonra iki ayrı şey var: proje (`sdlc/project.json` orada) ve
 * harness (`gates/`, `scripts/sdlc/` orada). Aynı repoda ikisi aynı dizindir;
 * ayrıldığında değildir. Karıştırılırsa her şey sessizce yanlış dizine bakar.
 */
export function harnessRoot(): string {
  return resolve(dirname(fileURLToPath(import.meta.url)), "..");
}
