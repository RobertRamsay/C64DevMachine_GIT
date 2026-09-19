#!/usr/bin/env node
/** Real MCP client for the local smoke test. Does not use an AI model/API. */
import { spawn, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline/promises';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import { Lines, loadConfig } from './bridge.mjs';

if (process.argv.length !== 3 || process.argv[2] !== '--live') {
  console.error('Usage: node tools/cdm-mcp/smoke.mjs --live');
  process.exit(2);
}
const config = loadConfig();
const bridge = join(dirname(fileURLToPath(import.meta.url)), 'bridge.mjs');
const child = spawn(process.execPath, [bridge], { stdio: ['pipe', 'pipe', 'inherit'], env: process.env });
const pending = new Map();
let seq = 0;
let stopped = false;
let prompt;
let failed = false;
function rejectAll(message) {
  stopped = true;
  for (const p of pending.values()) { clearTimeout(p.timer); p.reject(new Error(message)); }
  pending.clear();
  prompt?.close();
}
child.on('error', error => rejectAll(error.message));
child.on('exit', code => rejectAll(`Bridge exited (${code}); check for another running bridge.`));
child.stdin.on('error', error => rejectAll(error.message));
child.stdout.on('data', chunk => {
  try { lines.push(chunk); }
  catch (error) { rejectAll(error.message); child.kill(); }
});
const lines = new Lines(line => {
  const message = JSON.parse(line);
  const p = pending.get(message.id);
  if (!p) return;
  pending.delete(message.id); clearTimeout(p.timer);
  if (message.error) p.reject(new Error(message.error.message));
  else p.resolve(message.result);
});
function rpc(method, params = {}) {
  if (stopped) return Promise.reject(new Error('Bridge is not running.'));
  const id = ++seq;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id); reject(new Error('MCP request timed out; do not repeat edits blindly.'));
    }, 18000);
    pending.set(id, { resolve, reject, timer });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
async function call(name, args = {}) {
  const result = await rpc('tools/call', { name, arguments: args });
  if (result.isError) throw new Error(result.content?.[0]?.text ?? 'Tool failed');
  return JSON.parse(result.content[0].text);
}
try {
  const init = await rpc('initialize', { protocolVersion: '2025-11-25', capabilities: {},
    clientInfo: { name: 'cdm-live-smoke', version: '0.1.0' } });
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  const tools = await rpc('tools/list');
  console.log(`MCP initialized (${init.protocolVersion}); ${tools.tools.length} tools discovered.`);
  const key = `cdm1:${config.port}:${config.token}`;
  let copied = false;
  if (process.platform === 'win32') {
    copied = spawnSync('clip.exe', { input: key, encoding: 'utf8', windowsHide: true }).status === 0;
  } else if (process.platform === 'darwin') {
    copied = spawnSync('pbcopy', { input: key, encoding: 'utf8' }).status === 0;
  }
  console.log('\nOpen the REBUILT Dev Machine, close its welcome screen and open a small scratch project.');
  if (copied) console.log('The local pairing key is now on your clipboard.');
  else console.log(`Copy this local pairing key (not into an AI chat):\n${key}`);
  console.log('Press Ctrl+Shift+F12 in Dev Machine. Look for the green MCP TEST: CONNECTED badge.');
  console.log('This test will add one "Hello from MCP!" comment, then disconnect. Normal autosave settings still apply.');
  prompt = createInterface({ input: process.stdin, output: process.stdout });
  await prompt.question('\nOnce connected, return here and press Enter to run the test: ');
  prompt.close(); prompt = undefined;
  const pong = await call('cdm_ping');
  if (pong.pong !== true || pong.application !== 'C64 Dev Machine') throw new Error('Unexpected ping response.');
  const before = await call('cdm_project_summary', { limit: 5 });
  console.log(`PASS: live ping. Project: ${before.project}; nodes before: ${before.node_count}`);
  const added = await call('cdm_add_comment', {
    expected_workspace: before.workspace_key, text: 'Hello from MCP!',
  });
  if (!added.created || added.created.type !== 'COMMENT' || added.created.text !== 'Hello from MCP!') {
    throw new Error('Unexpected create result; inspect Dev Machine before retrying.');
  }
  const after = await call('cdm_project_summary', { limit: 5 });
  if (after.node_count !== before.node_count + 1) {
    throw new Error('Node count did not increase by exactly one; inspect the project.');
  }
  console.log(`PASS: created COMMENT uid=${added.created.uid}; nodes after: ${after.node_count}`);
  console.log('PASS: MCP initialize -> tools/list -> ping -> read -> add comment -> read.');
  console.log('Check the comment in Dev Machine. Ctrl+Z should remove it; Ctrl+Y should restore it.');
  console.log('The bridge is closing. The editor badge may take up to 15 seconds to show disconnected.');
} catch (error) {
  console.error(`TEST FAILED: ${error.message}`);
  process.exitCode = 1; failed = true;
} finally {
  prompt?.close();
  child.stdin.end();
  const killTimer = setTimeout(() => child.kill(), 1500);
  killTimer.unref();
  if (failed) console.error('No automatic retry was made. Check the live project before repeating the test.');
}
