#!/usr/bin/env node
/**
 * sdlc/project.ts — projeye özgü bilginin TEK kaynağı.
 *
 *   node sdlc/project.ts                    # tüm yapılandırma
 *   node sdlc/project.ts stacks             # bir alan
 *   node sdlc/project.ts stack backend testCommand
 *
 * Harness'ın geri kalanı hiçbir yerde "server/", "pytest", "vitest" ya da
 * "crawlens" yazmaz; hepsini buradan okur. Başka bir repoya taşırken
 * değiştirilecek tek dosya `sdlc/project.json`.
 *
 * Dosya YOKSA makul varsayılanlar döner: harness çalışmayı reddetmez, ama
 * ne varsaydığını söyler. Dosya VARSA ve bozuksa döndürmez — sesli düşer.
 * Alan-alan denetim `sdlc/validate.ts` içinde.
 */

import { existsSync, readFileSync } from "node:fs";
import { projectRoot } from "../gates/root.ts";

export type Service = {
  name: string;
  image: string;
  containerPort: number;
  envVar: string;
  urlTemplate: string;
  readyCheck?: string;
};

export type Stack = {
  name: string;
  root: string;
  changedPattern: string;
  deps?: string[];
  envFile?: string;
  testSelector?: { testDirPattern: string; sourcePattern: string; testFileGlob: string };
  testCommand?: string;
  soloCommand?: string;
  typecheckCommand?: string;
  clearEnv?: string[];
  services?: Service[];
  infraFailurePatterns?: string[];
  failureFilePattern?: string;
};

export type ProjectConfig = {
  name: string;
  memory: { processDataset: string; productDataset: string; productDocs: string[] };
  stacks: Stack[];
  criticalSurfaces: string[];
  criticalPaths: { label: string; pattern: string }[];
};

const DEFAULTS: ProjectConfig = {
  name: "project",
  memory: { processDataset: "sdlc", productDataset: "product", productDocs: ["README.md"] },
  stacks: [],
  criticalSurfaces: [
    "database migration / schema change",
    "authentication, session or authorization logic",
    "payment, billing or invoicing",
    "personal data (storage, export, logging, third-party transfer)",
    "secret, key or credential handling",
  ],
  criticalPaths: [
    { label: "database migration", pattern: "(alembic|migrations?|schema)/" },
    { label: "auth / session", pattern: "(auth|session|token|jwt|permission|rbac)" },
    { label: "payments & billing", pattern: "(billing|payment|invoice|subscription)" },
    { label: "secrets & credentials", pattern: "(^|/)(secrets?|\\.env|sops)" },
  ],
};

const root = projectRoot();

export function loadProject(): ProjectConfig {
  const path = `${root}/sdlc/project.json`;
  if (!existsSync(path)) return DEFAULTS;
  // Bozuk JSON'u SESSIZCE varsayilanlara dusurmuyoruz. Dusurmek, calismayan bir
  // hat degil YANLIS calisan bir hat uretir: yigin listesi bosalir, test fazi
  // hicbir sey kosmaz ve kimse yapilandirmanin okunamadigini ogrenmez.
  let raw: Partial<ProjectConfig>;
  try {
    raw = JSON.parse(readFileSync(path, "utf8")) as Partial<ProjectConfig>;
  } catch (err) {
    throw new Error(
      `sdlc/project.json okunamadi (${(err as Error).message})\n` +
      `  denetlemek icin: node sdlc/validate.ts`
    );
  }
  return { ...DEFAULTS, ...raw, memory: { ...DEFAULTS.memory, ...(raw.memory ?? {}) } };
}

export function stackFor(changedPath: string): Stack | undefined {
  return loadProject().stacks.find((s) => new RegExp(s.changedPattern).test(changedPath));
}

const invokedDirectly =
  process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href;

if (invokedDirectly) {
  const [, , key, name, field] = process.argv;
  const cfg = loadProject();
  if (!key) {
    console.log(JSON.stringify(cfg, null, 2));
  } else if (key === "stack") {
    const st = cfg.stacks.find((s) => s.name === name);
    if (!st) process.exit(1);
    const v = field ? (st as unknown as Record<string, unknown>)[field] : st;
    console.log(typeof v === "string" ? v : JSON.stringify(v ?? "", null, 2));
  } else {
    const v = (cfg as unknown as Record<string, unknown>)[key];
    console.log(typeof v === "string" ? v : JSON.stringify(v ?? "", null, 2));
  }
}
