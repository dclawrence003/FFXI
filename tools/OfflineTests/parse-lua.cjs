const fs = require('node:fs');
const path = require('node:path');
const luaparse = require('luaparse');

const root = process.argv[2];
if (!root || !fs.statSync(root).isDirectory()) {
  throw new Error('Supply the addon directory to parse.');
}
let checked = 0;
let failed = 0;
function visit(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) throw new Error(`Unexpected link: ${file}`);
    if (entry.isDirectory()) visit(file);
    else if (entry.isFile() && entry.name.endsWith('.lua')) {
      checked++;
      try {
        luaparse.parse(fs.readFileSync(file, 'utf8'), { luaVersion: '5.1' });
      } catch (error) {
        failed++;
        console.error(`${file}: ${error.message}`);
      }
    }
  }
}
visit(root);
if (!checked) throw new Error('No Lua files found.');
console.log(`Lua 5.1 syntax: ${checked} files checked, ${failed} failures.`);
process.exitCode = failed ? 1 : 0;
