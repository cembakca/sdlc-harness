import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { START, must } from "../gates/chain.ts";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const source = readFileSync(resolve(root, ".claude/workflows/sdlc.js"), "utf8")
  .replace(/^export\s+const\s+meta\s*=/m, "const meta =");
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const workflow = new AsyncFunction(
  "agent", "command", "writeArtifact", "parallel", "pipeline", "phase", "log", "args", "budget", "workflow",
  source
);

/** Run the same workflow used by Claude, with transitions enforced in this process. */
export async function orchestrate({ agent, command, writeArtifact, args, budget = { total: null }, log = () => {}, onPhase = () => {} }) {
  if (typeof agent !== "function") throw new TypeError("agent adapter gerekli");
  if (typeof command !== "function") throw new TypeError("doğrudan komut yürütücüsü gerekli");
  if (typeof writeArtifact !== "function") throw new TypeError("artifact yazıcısı gerekli");
  const ticket = args?.ticket ?? args?.id;
  if (ticket && (typeof ticket !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(ticket) || ticket.includes(".."))) {
    throw new Error(`geçersiz ticket: ${ticket}`);
  }

  let current = null;
  function phase(next) {
    if (current === null) {
      if (next !== START) throw new Error(`HAT YANLIŞ YERDEN BAŞLADI: ${next}`);
    } else {
      must(current, next);
    }
    current = next;
    onPhase(next);
  }

  const result = await workflow(
    agent,
    command,
    writeArtifact,
    (thunks) => Promise.all(thunks.map((thunk) => thunk())),
    undefined,
    phase,
    log,
    args,
    budget,
    undefined
  );
  if (current !== null) {
    must(current, "BITTI");
    onPhase("BITTI");
  }
  return result;
}
