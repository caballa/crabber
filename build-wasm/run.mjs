// Node runner: node run.mjs <file.crabir> [crabber flags...]
// e.g. node run.mjs ../samples/test-1.crabir -d int --print-invariants
import Crabber from './crabber.js';
import { readFileSync } from 'fs';

const [, , file, ...args] = process.argv;
if (!file) { console.error('usage: node run.mjs <file.crabir> [flags...]'); process.exit(64); }
const src = readFileSync(file, 'utf8');

let out = '';
// Filter Apron's harmless FPU-rounding warning (wasm lacks fesetround; MPQ domains are exact).
const isFpuNoise = t => /fpu rounding mode|cannot change the FPU/i.test(t);
const M = await Crabber({ print: t => out += t + '\n', printErr: t => { if (!isFpuNoise(t)) out += t + '\n'; } });
M.FS.writeFile('/prog.crabir', src);
const rc = M.callMain(['/prog.crabir', ...(args.length ? args : ['-d', 'int', '--print-invariants'])]);
process.stdout.write(out);
process.exit(rc);
