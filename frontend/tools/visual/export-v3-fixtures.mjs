// Writes the v3 web fixtures as JSON for the Android golden tests, so web and
// Android are checked against the same mockup data:
//   node tools/visual/export-v3-fixtures.mjs  ->  mobile/test/golden_v3/fixtures.json
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { V3_STATIC } from "./v3-fixtures.mjs";

const out = join(dirname(fileURLToPath(import.meta.url)), "../../../mobile/test/golden_v3/fixtures.json");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(V3_STATIC, null, 1) + "\n");
console.log(`wrote ${out}`);
