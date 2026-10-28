// Print pi's default keybindings as JSON: {id: {keys, description}}. Run with HOME pointing
// at an empty directory so no user keybindings.json is merged.
// usage: node pi.mjs PACKAGE_DIR
const { KeybindingsManager } = await import(`${process.argv[2]}/dist/core/keybindings.js`);
const m = KeybindingsManager.create();
const out = {};
for (const [id, keys] of Object.entries(m.getResolvedBindings()))
  out[id] = { keys: Array.isArray(keys) ? keys : [keys], description: m.getDefinition(id)?.description };
console.log(JSON.stringify(out));
