// Print Claude Code's built-in keybindings table as JSON: {context: {key: action}}.
// usage: node claude.cjs BINARY
// The table is a literal in the native binary starting at ANCHOR; identifiers the minifier
// left in it (platform-dependent keys) are resolved by action.
const fs = require("fs");
const s = fs.readFileSync(process.argv[2]).toString("latin1");
const ANCHOR = '[{context:"Global",bindings:{"ctrl+c":"app:interrupt"';
const start = s.indexOf(ANCHOR);
if (start < 0) { console.error("claude: keybindings table not found"); process.exit(1); }
let depth = 0, i = start, q = null;
for (; i < s.length; i++) {
  const c = s[i];
  if (q) { if (c === "\\") i++; else if (c === q) q = null; continue; }
  if (c === '"' || c === "'" || c === "`") q = c;
  else if ("[{(".includes(c)) depth++;
  else if ("]})".includes(c) && --depth === 0) break;
}
const scope = new Proxy({}, { has: (_, k) => typeof k === "string" && !(k in globalThis), get: (_, k) => `<${String(k)}>` });
const table = new Function("scope", `with (scope) { return (${s.slice(start, i + 1)}); }`)(scope);
const FIX = { "chat:cycleMode": "shift+tab", "confirm:cycleMode": "shift+tab", "chat:imagePaste": "ctrl+v" };
const out = {};
for (const { context, bindings } of table)
  for (const [k, a] of Object.entries(bindings)) (out[context] ??= {})[k.startsWith("<") ? FIX[a] ?? k : k] = a;
console.log(JSON.stringify(out));
