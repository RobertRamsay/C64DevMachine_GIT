/** Automated tests use a SIMULATED editor. They do not execute GameMaker. */
import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { once } from 'node:events';
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { Lines, EditorLink, McpServer, TOOLS, validateArgs, loadConfig } from './bridge.mjs';

const token = 'a'.repeat(64);
const delay = ms => new Promise(r => setTimeout(r, ms));
async function waitFor(fn, ms = 2000) {
  const end = Date.now() + ms;
  while (!fn()) { if (Date.now() > end) throw new Error('waitFor timeout'); await delay(5); }
}
async function connectedLink(t, options = {}) {
  const link = new EditorLink({ port: 0, token, heartbeatMs: 10000, ...options });
  await link.start(); t.after(() => link.close());
  const socket = net.createConnection({ host: '127.0.0.1', port: link.port });
  socket.on('error', () => {}); t.after(() => socket.destroy());
  await once(socket, 'connect');
  socket.write(JSON.stringify({ event: 'hello', protocol: 1, token }) + '\n');
  await waitFor(() => link.status().editor_connected);
  return { link, socket };
}

test('LF framing preserves fragmented UTF-8 and coalesced messages', () => {
  const out = []; const lines = new Lines(s => out.push(s));
  const bytes = Buffer.from('{"name":"café 漢字"}\n{"id":2}\r\n');
  for (const byte of bytes) lines.push(Buffer.from([byte]));
  assert.equal(out.length, 2); assert.equal(JSON.parse(out[0]).name, 'café 漢字');
  assert.equal(JSON.parse(out[1]).id, 2);
});
test('LF framing rejects oversized and invalid UTF-8 input', () => {
  assert.throws(() => new Lines(() => {}, 3).push(Buffer.from('abcd')), /large/);
  assert.throws(() => new Lines(() => {}).push(Buffer.from([0xff, 10])));
});
test('node schemas reject unsafe, unknown and malformed arguments', () => {
  const ok = { expected_workspace: '100001:5', text: 'Hello from MCP!' };
  assert.deepEqual(validateArgs('cdm_add_comment', ok), ok);
  for (const args of [{}, { ...ok, text: '\n' }, { ...ok, text: 'é' },
    { ...ok, text: 'a'.repeat(257) }, { ...ok, x: NaN }, { ...ok, x: Infinity },
    { ...ok, x: '5' }, { ...ok, shell: 'whoami' }, { ...ok, expected_workspace: '' }]) {
    assert.throws(() => validateArgs('cdm_add_comment', args));
  }
  assert.throws(() => validateArgs('cdm_project_summary', { limit: 101 }));
  assert.throws(() => validateArgs('cdm_project_summary', { offset: 1.2 }));
  assert.throws(() => validateArgs('cdm_focus_node', { uid: 2 }));
  assert.throws(() => validateArgs('cdm_delete', {}));
});
test('pairing config creates a reusable random secret outside source', () => {
  const dir = mkdtempSync(join(tmpdir(), 'cdm-key-'));
  try {
    const env = { CDM_MCP_TOKEN_FILE: join(dir, 'token'), CDM_MCP_PORT: '5150' };
    const a = loadConfig(env), b = loadConfig(env);
    assert.match(a.token, /^[0-9a-f]{64}$/); assert.equal(a.token, b.token);
    assert.throws(() => loadConfig({ ...env, CDM_MCP_PORT: '0' }));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
test('MCP requires initialization and negotiates known revisions', async () => {
  const out = []; const s = new McpServer({ cancel() {} }, m => out.push(m));
  await s.handle({ jsonrpc: '2.0', id: 1, method: 'tools/list' });
  assert.equal(out.pop().error.code, -32002);
  await s.handle({ jsonrpc: '2.0', id: 2, method: 'initialize', params: {
    protocolVersion: 'future-version', capabilities: {}, clientInfo: { name: 'test', version: '1' } } });
  assert.equal(out.pop().result.protocolVersion, '2025-11-25');
  await s.handle({ jsonrpc: '2.0', method: 'notifications/initialized' });
  await s.handle({ jsonrpc: '2.0', id: 3, method: 'tools/list' });
  assert.equal(out.pop().result.tools.length, 5);
  await s.handle({ jsonrpc: '2.0', id: 4, method: 'resources/list' });
  assert.equal(out.pop().error.code, -32601);
});
test('MCP returns tool errors, ignores unknown notifications and never leaks token', async () => {
  const out = []; const s = new McpServer({ status: () => ({ editor_connected: false }), cancel() {} }, m => out.push(m));
  s.state = 'ready';
  await s.handle({ jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'cdm_add_comment', arguments: {} } });
  assert.equal(out.pop().result.isError, true);
  await s.handle({ jsonrpc: '2.0', method: 'notifications/unknown' });
  assert.equal(out.length, 0);
  await s.handle({ jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'cdm_status' } });
  assert.equal(out.pop().result.isError, false);
  assert.ok(!JSON.stringify(TOOLS).includes(token));
});
test('TCP listener is loopback only and rejects unauthenticated clients', async t => {
  const link = new EditorLink({ port: 0, token }); await link.start(); t.after(() => link.close());
  assert.equal(link.server.address().address, '127.0.0.1');
  const socket = net.createConnection({ host: '127.0.0.1', port: link.port });
  socket.on('error', () => {}); await once(socket, 'connect');
  const closed = once(socket, 'close');
  socket.write(JSON.stringify({ event: 'hello', protocol: 1, token: 'b'.repeat(64) }) + '\n');
  await closed; assert.equal(link.status().editor_connected, false);
});
test('authenticated TCP forwards one command, handles fragmented replies and rejects concurrency', async t => {
  const { link, socket } = await connectedLink(t);
  const parser = new Lines(line => {
    const m = JSON.parse(line); if (!m.method) return;
    assert.equal(m.token, token); assert.equal(m.method, 'ping');
    const reply = Buffer.from(JSON.stringify({ id: m.id, ok: true, result: { pong: true, label: 'é' } }) + '\n');
    setTimeout(() => { for (const byte of reply) socket.write(Buffer.from([byte])); }, 20);
  });
  socket.on('data', c => parser.push(c));
  const pending = link.request('ping', {}, 10);
  await assert.rejects(link.request('ping', {}, 11), /pending/);
  assert.deepEqual(await pending, { pong: true, label: 'é' });
  assert.equal(link.status().command_pending, false);
});
test('timeouts close the session and never retransmit a mutation', async t => {
  const { link, socket } = await connectedLink(t, { timeoutMs: 50 });
  let count = 0;
  const parser = new Lines(line => { if (JSON.parse(line).method) count++; });
  socket.on('data', c => parser.push(c));
  await assert.rejects(link.request('add_comment', { text: 'test' }, 7), /may have completed/);
  await delay(30); assert.equal(count, 1); assert.equal(link.status().editor_connected, false);
});
test('cancellation rejects the request and disconnects instead of reporting rollback', async t => {
  const { link } = await connectedLink(t);
  const result = link.request('add_comment', { text: 'test' }, 'cancel-me');
  link.cancel('cancel-me');
  await assert.rejects(result, /cannot be rolled back/);
  assert.equal(link.status().editor_connected, false);
});
test('disconnect rejects pending requests and permits explicit fresh pairing', async t => {
  const { link, socket } = await connectedLink(t);
  const pending = link.request('ping', {}, 1);
  const rejected = assert.rejects(pending, /disconnected/);
  socket.destroy(); await rejected;
  assert.equal(link.status().editor_connected, false);
  const replacement = net.createConnection({ host: '127.0.0.1', port: link.port });
  replacement.on('error', () => {}); t.after(() => replacement.destroy());
  await once(replacement, 'connect');
  replacement.write(JSON.stringify({ event: 'hello', protocol: 1, token }) + '\n');
  await waitFor(() => link.status().editor_connected);
  assert.equal(link.seq, 0);
});
test('actual stdio subprocess: initialize -> tools/list -> simulated read/add/read', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'cdm-stdio-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const reservation = net.createServer(); reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
  const port = reservation.address().port; await new Promise(r => reservation.close(r));
  const env = { ...process.env, CDM_MCP_TOKEN_FILE: join(dir, 'token'), CDM_MCP_PORT: String(port) };
  const config = loadConfig(env);
  const child = spawn(process.execPath, [join(dirname(fileURLToPath(import.meta.url)), 'bridge.mjs')], {
    env, stdio: ['pipe', 'pipe', 'pipe'],
  });
  t.after(() => child.kill());
  let stderr = ''; child.stderr.on('data', c => { stderr += c; });
  const responses = new Map(); let nextId = 0;
  const parser = new Lines(line => {
    const m = JSON.parse(line); assert.equal(m.jsonrpc, '2.0');
    const cb = responses.get(m.id); if (cb) { responses.delete(m.id); cb(m); }
  });
  child.stdout.on('data', c => parser.push(c));
  const rpc = (method, params = {}) => new Promise(resolve => {
    const id = ++nextId; responses.set(id, resolve);
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
  await waitFor(() => stderr.includes('Listening'));
  const initialized = await rpc('initialize', { protocolVersion: '2025-11-25', capabilities: {},
    clientInfo: { name: 'unit-test', version: '1' } });
  assert.equal(initialized.result.protocolVersion, '2025-11-25');
  child.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n');
  assert.equal((await rpc('tools/list')).result.tools.length, 5);
  const app = net.createConnection({ host: '127.0.0.1', port }); app.on('error', () => {});
  t.after(() => app.destroy()); await once(app, 'connect');
  let nodeCount = 2; let writes = 0;
  const appParser = new Lines(line => {
    const m = JSON.parse(line); if (!m.method) return;
    let result;
    if (m.method === 'project_summary') result = { node_count: nodeCount, workspace_key: `test:${nodeCount}` };
    else if (m.method === 'add_comment') {
      assert.equal(m.args.expected_workspace, `test:${nodeCount}`);
      nodeCount++; writes++; result = { created: { uid: 123, type: 'COMMENT', text: m.args.text } };
    } else result = { pong: true };
    app.write(JSON.stringify({ id: m.id, ok: true, result }) + '\n');
  });
  app.on('data', c => appParser.push(c));
  app.write(JSON.stringify({ event: 'hello', protocol: 1, token: config.token }) + '\n');
  await waitFor(() => stderr.includes('paired'));
  const call = async (name, args = {}) => {
    const r = (await rpc('tools/call', { name, arguments: args })).result;
    assert.equal(r.isError, false); return JSON.parse(r.content[0].text);
  };
  const before = await call('cdm_project_summary');
  const created = await call('cdm_add_comment', { expected_workspace: before.workspace_key, text: 'Hello from MCP!' });
  const after = await call('cdm_project_summary');
  assert.equal(after.node_count, before.node_count + 1); assert.equal(writes, 1);
  assert.equal(created.created.text, 'Hello from MCP!');
  assert.ok(!stderr.includes(config.token));
  const exited = once(child, 'exit'); child.stdin.end();
  const [code] = await exited; assert.equal(code, 0);
});
test('a second editor cannot replace an already authenticated editor', async t => {
  const { link, socket } = await connectedLink(t);
  const first = link.socket;
  const second = net.createConnection({ host: '127.0.0.1', port: link.port });
  second.on('error', () => {});
  const closed = once(second, 'close');
  await closed;
  assert.equal(link.socket, first); assert.equal(socket.destroyed, false);
});
test('live smoke client executable completes against a simulated editor', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'cdm-live-client-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const reservation = net.createServer(); reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
  const port = reservation.address().port; await new Promise(r => reservation.close(r));
  const env = { ...process.env, CDM_MCP_TOKEN_FILE: join(dir, 'token'), CDM_MCP_PORT: String(port) };
  const config = loadConfig(env);
  const smoke = spawn(process.execPath, [join(dirname(fileURLToPath(import.meta.url)), 'smoke.mjs'), '--live'], {
    env, stdio: ['pipe', 'pipe', 'pipe'],
  });
  t.after(() => smoke.kill());
  let stdout = '', stderr = '';
  smoke.stdout.on('data', c => { stdout += c; }); smoke.stderr.on('data', c => { stderr += c; });
  const exited = once(smoke, 'exit');
  await waitFor(() => stdout.includes('press Enter to run'));
  const app = net.createConnection({ host: '127.0.0.1', port }); app.on('error', () => {});
  t.after(() => app.destroy()); await once(app, 'connect');
  let count = 2, mutations = 0;
  const parser = new Lines(line => {
    const m = JSON.parse(line); if (!m.method) return;
    let result;
    if (m.method === 'ping') result = { pong: true, application: 'C64 Dev Machine' };
    if (m.method === 'project_summary') result = { project: 'MOCK SCRATCH', node_count: count, workspace_key: `mock:${count}` };
    if (m.method === 'add_comment') {
      count++; mutations++; result = { created: { uid: 987, type: 'COMMENT', text: m.args.text } };
    }
    app.write(JSON.stringify({ id: m.id, ok: true, result }) + '\n');
  });
  app.on('data', c => parser.push(c));
  app.write(JSON.stringify({ event: 'hello', protocol: 1, token: config.token }) + '\n');
  await waitFor(() => stderr.includes('paired'));
  smoke.stdin.write('\n');
  const [code] = await exited;
  assert.equal(code, 0, stderr);
  assert.equal(mutations, 1);
  assert.ok(stdout.includes('PASS: MCP initialize -> tools/list -> ping -> read -> add comment -> read.'));
});
