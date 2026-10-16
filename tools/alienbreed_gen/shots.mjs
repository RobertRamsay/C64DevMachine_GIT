// node shots.mjs script.json sec1,sec2,... prefix  - test build + VICE screenshots
import { execFileSync } from 'child_process';
import { runVice } from '../golazo_gen/vice.mjs';
const [script, secs, prefix] = process.argv.slice(2);
execFileSync(process.execPath, ['build.mjs', 'out/test.json', '--test', script], { stdio: 'inherit' });
for (const s of secs.split(',')) {
  const png = `out/${prefix}_${s}.png`;
  const r = runVice('out/alienbreed_test.prg', +s, png, process.env.AB_REU ? ['-reu', '-reusize', '1024', '-reuimage', 'out/alienbreed.reu'] : []);
  console.log(r.ok ? png : 'NO SHOT ' + png);
}
