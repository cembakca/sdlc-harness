#!/usr/bin/env node
/**
 * PreToolUse hook — dosya düzenlemelerinde blast radius kapısı.
 *
 * Varsayılan: advisory. Kritik bir yüzeye dokunulduğunda uyarı basar, akışı
 * kesmez. SDLC_GATE=enforce ile aynı durumda izin sorulur ("ask").
 * Sınıflandırma gates/questions.ts'teki CRITICAL_PATHS'tan gelir — tek kaynak.
 */

import { classifyPath } from "../../gates/questions.ts";  // harness icinde: .claude/hooks -> gates

const raw = await new Promise<string>((resolve) => {
  let buf = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (c) => (buf += c));
  process.stdin.on("end", () => resolve(buf));
});

let input: { tool_input?: { file_path?: string; notebook_path?: string } } = {};
try {
  input = JSON.parse(raw);
} catch {
  process.exit(0);
}

const file = input.tool_input?.file_path ?? input.tool_input?.notebook_path ?? "";
const hit = file ? classifyPath(file) : null;

if (!hit) process.exit(0);

const reason =
  `Blast radius: CRITICAL — "${file}" ${hit.label} yüzeyine dokunuyor. ` +
  `Proje kuralı: bu alanda otomatik review ne kadar temiz olursa olsun insan onayı gerekir ` +
  `(.claude/CLAUDE.md #4, gates/questions.ts).`;

if (process.env.SDLC_GATE === "enforce") {
  console.log(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "ask",
        permissionDecisionReason: reason,
      },
    })
  );
} else {
  console.log(JSON.stringify({ systemMessage: `⚠️  ${reason}` }));
}
process.exit(0);
