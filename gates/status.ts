#!/usr/bin/env node
/**
 * gates/status.ts — her ticket nerede duruyor?
 *
 *   node gates/status.ts
 *
 * Hat bir işi hangi aşamada bıraktığını biliyordu ama hiçbir yerde
 * göstermiyordu: "F4-1 ne durumda" sorusunun cevabı bir workflow çıktısını
 * hatırlamaktan geçiyordu. Ofis, masasındaki işlerin nerede olduğunu bilmeli.
 *
 * Model yok: durum dosyaların varlığından ve karar defterinden çıkarılır.
 */

import { readdirSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { read } from "./journal.ts";
import { projectRoot } from "./root.ts";

const root = projectRoot();
const dir = `${root}/docs/sdlc`;
if (!existsSync(dir)) {
  console.log("henüz ticket yok — make sdlc-new TICKET=X");
  process.exit(0);
}

const STAGES = [
  "intent",   // intent.md var
  "spec",     // spec.md var ve kapısı pass
  "scope",    // scope kapısı geçildi
  "plan",     // plan.md var, blast kapısı geçildi/onaylandı
  "build",    // worktree'de commit var
  "review",   // REVIEW.md var
  "test",     // test kapısı pass
  "ready",    // readiness pass
  "landed",   // outcome kaydı var
];

const git = (...args: string[]) => {
  try {
    return execFileSync("git", ["-C", root, ...args], { encoding: "utf8" }).trim();
  } catch {
    return "";
  }
};

const rows: string[] = [];
for (const d of readdirSync(dir, { withFileTypes: true })) {
  if (!d.isDirectory() || d.name === "templates") continue;
  const t = d.name;
  const p = `${dir}/${t}`;
  const entries = read(t);
  const last = (g: string) => [...entries].reverse().find((r) => r.gate === g);
  const approved = (g: string) =>
    [...entries].reverse().some((r) => r.gate === `approve:${g}`);

  let stage = "intent";
  if (existsSync(`${p}/spec.md`) && last("spec")?.decision === "pass") stage = "spec";
  if (stage === "spec" && ["pass"].includes(last("scope")?.decision ?? "") ) stage = "scope";
  if (stage === "spec" && last("scope")?.decision === "human" && approved("scope")) stage = "scope";
  if (stage === "scope" && existsSync(`${p}/plan.md`)) stage = "plan";
  const branch = `sdlc/${t}`;
  const hasBranch = git("show-ref", "--verify", "--quiet", `refs/heads/${branch}`) === "";
  const ahead = hasBranch ? git("rev-list", "--count", `HEAD..${branch}`) : "";
  if (stage === "plan" && Number(ahead || 0) > 0) stage = "build";
  if (stage === "build" && existsSync(`${p}/REVIEW.md`)) stage = "review";
  if (stage === "review" && last("test")?.decision === "pass") stage = "test";
  if (last("readiness")?.decision === "pass") stage = "ready";
  if (last("outcome")) stage = "landed";

  const blockers = entries.filter((r) => r.decision === "block").length;
  const bar = STAGES.map((s) => (STAGES.indexOf(s) <= STAGES.indexOf(stage) ? "▰" : "▱")).join("");
  const blast = last("blast")?.measures?.radius ?? "—";
  rows.push(
    `${t.padEnd(12)} ${bar}  ${stage.padEnd(7)} blast:${String(blast).padEnd(9)} ` +
      `dal:${hasBranch ? (ahead || "0") + " commit" : "YOK"}  blok:${blockers}`
  );
}

if (!rows.length) {
  console.log("henüz ticket yok");
  process.exit(0);
}
console.log(`ticket       ${STAGES.map((s) => s[0]).join("")}  aşama   risk           dal        blok`);
console.log("─".repeat(84));
for (const r of rows) console.log(r);
console.log("─".repeat(84));
console.log(STAGES.map((s, i) => `${s[0]}=${s}`).join(" · "));
