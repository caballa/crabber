// Node runner: node run.mjs <file.crabir> [crabber flags...]
// e.g. node run.mjs ../samples/test-1.crabir -d int --print-invariants
import Crabber from './crabber.js';
import { readFileSync } from 'fs';

const [, , file, ...args] = process.argv;
if (!file) { console.error('usage: node run.mjs <file.crabir> [flags...]'); process.exit(64); }
const src = readFileSync(file, 'utf8');

let out = '';
const M = await Crabber({ print: t => out += t + '\n', printErr: t => out += t + '\n' });
M.FS.writeFile('/prog.crabir', src);
const rc = M.callMain(['/prog.crabir', ...(args.length ? args : ['-d', 'int', '--print-invariants'])]);
process.stdout.write(out);
process.exit(rc);
