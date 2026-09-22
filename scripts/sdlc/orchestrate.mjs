#!/usr/bin/env node
/** Standalone SDLC runner. Claude is an adapter; workflow decisions live in code. */
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { mkdirSync, writeFileSync } from "node:fs";
import { orchestrate } from "../../sdlc/orchestrator.mjs";
import { projectRoot } from "../../gates/root.ts";

// IKI KOK. Harness ayri repoya cikinca bunlar ayni dizin degil:
//   proje koku   : git, docs/sdlc/<ticket>, .sdlc-worktrees — is BURADA yapilir
//   harness koku : gates/, scripts/sdlc/, .claude/workflows — arac BURADA durur
// Onceden ikisi de "../.." idi; tuketen bir repoda orkestratör calisma dizinini
// harness'a tasiyor ve biletin belgelerini orada ariyordu (dis denetim,
// 22 Eyl 2026).
const HARNESS = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const root = projectRoot();
process.chdir(root);
// Akis (sdlc.js) harness dosyalarini bu degiskenle bulur.
process.env.SDLC_HARNESS = HARNESS;

/**
 * Harness'a ait goreli yolu mutlaklastirir.
 *
 * Akis `scripts/sdlc/test.sh` ya da `node gates/assign.ts` diye yazar; bunlar
 * ARACIN yollari, projenin degil. Calisma dizini proje koku oldugu icin
 * goreli birakilirsa projede aranir ve bulunamaz.
 */
const HARNESS_PREFIX = /^(gates|scripts\/sdlc)\//;
function harnessPath(p) {
  return typeof p === "string" && HARNESS_PREFIX.test(p) ? resolve(HARNESS, p) : p;
}

const argv = process.argv.slice(2);
const ticket = argv.shift();
if (!ticket || argv.some((arg) => !["--spec-only", "--replan"].includes(arg))) {
  console.error("usage: node scripts/sdlc/orchestrate.mjs <TICKET> [--spec-only] [--replan]");
  process.exit(2);
}

let spent = 0;
const total = process.env.SDLC_TOKEN_BUDGET == null ? null : Number(process.env.SDLC_TOKEN_BUDGET);
if (total !== null && (!Number.isFinite(total) || total < 0)) {
  console.error("SDLC_TOKEN_BUDGET sıfır veya pozitif bir sayı olmalı");
  process.exit(2);
}

function claude(prompt, { model, label } = {}) {
  return new Promise((resolve, reject) => {
    const args = ["-p", "--output-format", "json", "--no-session-persistence", "--permission-mode", "auto",
      "--tools", "Read,Glob,Grep,Skill"];
    if (model) args.push("--model", model);
    const child = spawn("claude", args, {
      cwd: root,
      env: { ...process.env, MEMORY_AUTOSTART: process.env.MEMORY_AUTOSTART ?? "0" },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.stdin.on("error", reject);
    child.on("error", reject);
    child.on("close", (code) => {
      if (code !== 0) return reject(new Error(`${label ?? "agent"}: Claude exit ${code}: ${stderr.slice(-1000)}`));
      let answer;
      try { answer = JSON.parse(stdout); }
      catch { return reject(new Error(`${label ?? "agent"}: Claude JSON çıktısı okunamadı: ${stdout.slice(-500)}`)); }
      if (answer.is_error) return reject(new Error(`${label ?? "agent"}: ${answer.result ?? "Claude hata döndürdü"}`));
      const usage = answer.usage ?? {};
      spent += (usage.input_tokens ?? 0) + (usage.cache_creation_input_tokens ?? 0) +
        (usage.cache_read_input_tokens ?? 0) + (usage.output_tokens ?? 0);
      resolve(String(answer.result ?? ""));
    });
    child.stdin.end(prompt);
  });
}

/**
 * Model ciktisini BELGEYE indirger. Gevsetme degil, normalizasyon.
 *
 * Iki bicimleme artefakti gerceklesiyor ve ikisi de icerik hatasi degil:
 *
 *   1. Belge ```markdown ... ``` icine sarmalaniyor.
 *   2. Belgeden once bir aciklama cumlesi geliyor. Olculdu 22 Eyl 2026, M1'in
 *      plan fazinda: "No REVIEW.md exists for M1, so there are no open findings
 *      to fold in. Here is the plan document. --- # Plan — M1 ..."
 *
 * Ikisinde de TAM BELGE ortada duruyor; turu bosa harcamak icin bir sebep yok.
 * Ama sart gevsemiyor: normalizasyondan sonra metin yine "# " ile baslayan bir
 * baslik tasimak ZORUNDA. Baslik hic yoksa reddedilir.
 */
function normalizeDocument(text) {
  let t = String(text ?? "").trim();
  const fenced = t.match(/^```[a-zA-Z]*\n([\s\S]*?)\n```$/);
  if (fenced) t = fenced[1].trim();
  if (t.startsWith("#")) return t;
  // Ilk ust duzey basliktan itibaren al; oncesi aciklamadir.
  const at = t.search(/^# \S/m);
  return at >= 0 ? t.slice(at).trim() : t;
}

function writeArtifact(path, content) {
  const allowed = new Set(["spec.md", "plan.md", "REVIEW.md", "UAT.md"]);
  const directory = resolve(root, "docs/sdlc", ticket);
  const target = resolve(root, path);
  if (dirname(target) !== directory || !allowed.has(target.split("/").at(-1))) {
    throw new Error(`izin verilmeyen artifact yolu: ${path}`);
  }
  const body = normalizeDocument(content);
  if (!body.startsWith("#")) {
    // REDDEDILEN CIKTI KAYBOLMAMALI. Eskiden yalnizca firlatiliyordu: kosu
    // yigin iziyle oluyor, deftere satir dusmuyor ve modelin NE dondugu hic
    // gorulemiyordu — yani hatayi teshis edecek tek kanit siliniyordu
    // (olculdu 22 Eyl 2026, M1'in plan fazinda).
    mkdirSync(directory, { recursive: true });
    const rejected = `${target}.rejected`;
    writeFileSync(rejected, String(content ?? ""), "utf8");
    const head = String(content ?? "").trim().slice(0, 200).replace(/\n/g, " ⏎ ");
    const err = new Error(
      `${path}: model tam Markdown belge döndürmedi (ilk karakter "#" değil).\n` +
      `  dönen metnin başı: ${head || "(boş)"}\n` +
      `  tamamı kaydedildi: ${rejected.replace(root + "/", "")}`
    );
    err.sdlcStop = { stoppedAt: `artifact:${target.split("/").at(-1)}`, rejected };
    throw err;
  }
  mkdirSync(directory, { recursive: true });
  writeFileSync(target, body.trimEnd() + "\n", "utf8");
}

function command(file, args = [], allowed = [0]) {
  const exe = harnessPath(file);
  const argv = args.map(harnessPath);
  return new Promise((resolve, reject) => {
    const child = spawn(exe, argv, {
      cwd: root,
      env: { ...process.env, MEMORY_AUTOSTART: process.env.MEMORY_AUTOSTART ?? "0" },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.on("error", reject);
    child.on("close", (code) => {
      if (!allowed.includes(code)) return reject(new Error(`${file} exit ${code}: ${(stderr || stdout).slice(-1000)}`));
      resolve({ stdout, stderr, code });
    });
  });
}

try {
  const result = await orchestrate({
    agent: claude,
    command,
    writeArtifact,
    args: { ticket, specOnly: argv.includes("--spec-only"), replan: argv.includes("--replan") },
    budget: { total, spent: () => spent, remaining: () => total === null ? Infinity : total - spent },
    log: (message) => console.error(message),
    onPhase: (phase) => console.error(`→ ${phase}`),
  });
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result?.ready === false || result?.stoppedAt ? 20 : 0;
} catch (error) {
  // BEKLENEN DURUS ile COKME ayri seylerdir. Sozlesme ihlali (model tam belge
  // dondurmedi) bir durustur: gerekcesi, kaniti ve bir sonraki adimi vardir ve
  // kapi kararlariyla ayni cikis koduyla (20) biter. Yigin izi yalnizca
  // gercekten beklenmeyen hata icin.
  if (error?.sdlcStop) {
    console.log(JSON.stringify({
      ticket,
      stoppedAt: error.sdlcStop.stoppedAt,
      reason: error.message,
      next:
        `Model sozlesmeye uymayan bir cikti dondurdu. Reddedilen metin ` +
        `${error.sdlcStop.rejected.replace(root + "/", "")} dosyasinda duruyor; ` +
        `once ONA bak. Cogu zaman beceri promptu belgeyi acıklamayla sarmalatiyor ` +
        `ya da model arac cagrisi donduruyor. Hat tekrar kosturulabilir.`,
    }, null, 2));
    console.error(error.message);
    process.exitCode = 20;
  } else {
    console.error(error?.stack ?? String(error));
    process.exitCode = 1;
  }
}
