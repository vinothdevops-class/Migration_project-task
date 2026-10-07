'use strict';
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { createApp, validateOrder } = require('../src/app');

// In-memory fake that mimics the MySQL store's contract (idempotency included).
function fakeStore() {
  const byKey = new Map();
  const byId = new Map();
  return {
    healthy: true,
    async ping() { if (!this.healthy) throw new Error('down'); },
    async createOrder({ idempotencyKey, requestHash, order }) {
      const hit = byKey.get(idempotencyKey);
      if (hit) return hit.hash === requestHash ? { created: false, order: hit.order } : { conflict: true };
      const o = { id: '00000000-0000-4000-8000-' + String(byId.size).padStart(12, '0'), ...order, status: 'PENDING' };
      byKey.set(idempotencyKey, { hash: requestHash, order: o });
      byId.set(o.id, o);
      return { created: true, order: o };
    },
    async getOrder(id) { return byId.get(id) || null; },
    async close() {},
  };
}

let base, app, store;
before(async () => {
  store = fakeStore();
  app = createApp({ store, logger: { error() {} } });
  await new Promise((r) => app.server.listen(0, r));
  base = `http://127.0.0.1:${app.server.address().port}`;
});
after(() => app.server.close());

const order = { customerId: 'C-1', items: [{ sku: 'SKU-1', quantity: 2 }] };
const post = (body, key) => fetch(`${base}/orders`, {
  method: 'POST',
  headers: { 'content-type': 'application/json', ...(key ? { 'idempotency-key': key } : {}) },
  body: typeof body === 'string' ? body : JSON.stringify(body),
});

test('liveness is always 200', async () => {
  assert.equal((await fetch(`${base}/healthz`)).status, 200);
});

test('readiness follows the database', async () => {
  assert.equal((await fetch(`${base}/readyz`)).status, 200);
  store.healthy = false;
  assert.equal((await fetch(`${base}/readyz`)).status, 503);
  store.healthy = true;
});

test('creates an order, then a retry with the same key returns the same order', async () => {
  const a = await post(order, 'key-aaaa-0001');
  assert.equal(a.status, 201);
  const first = await a.json();
  const b = await post(order, 'key-aaaa-0001');
  assert.equal(b.status, 200);
  assert.equal((await b.json()).id, first.id);
  const got = await fetch(`${base}/orders/${first.id}`);
  assert.equal(got.status, 200);
});

test('same key with a different body is a 409', async () => {
  await post(order, 'key-bbbb-0001');
  const r = await post({ ...order, customerId: 'C-2' }, 'key-bbbb-0001');
  assert.equal(r.status, 409);
});

test('rejects missing idempotency key, bad JSON and invalid orders', async () => {
  assert.equal((await post(order)).status, 400);
  assert.equal((await post('{nope', 'key-cccc-0001')).status, 400);
  assert.equal((await post({ customerId: '', items: [] }, 'key-cccc-0002')).status, 422);
});

test('validateOrder flags bad SKUs and quantities', () => {
  assert.deepEqual(validateOrder({ customerId: 'C', items: [{ sku: 'bad sku', quantity: 0 }] }), ['items.sku', 'items.quantity']);
});
