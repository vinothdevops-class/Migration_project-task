'use strict';
// Order service HTTP layer. Plain node:http keeps the image small and the attack surface low.
// The data store is injected so the HTTP behaviour can be unit-tested without a database.

const http = require('node:http');
const crypto = require('node:crypto');

const MAX_BODY_BYTES = 16 * 1024;

function send(res, status, body) {
  const payload = body === undefined ? '' : JSON.stringify(body);
  res.writeHead(status, {
    'content-type': 'application/json',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  res.end(payload);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('body too large'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}'));
      } catch {
        reject(Object.assign(new Error('invalid JSON'), { status: 400 }));
      }
    });
    req.on('error', reject);
  });
}

function validateOrder(o) {
  const errors = [];
  if (typeof o.customerId !== 'string' || o.customerId.length < 1 || o.customerId.length > 64) errors.push('customerId');
  if (!Array.isArray(o.items) || o.items.length < 1 || o.items.length > 50) errors.push('items');
  else {
    for (const it of o.items) {
      if (typeof it.sku !== 'string' || !/^[A-Z0-9-]{1,32}$/.test(it.sku)) errors.push('items.sku');
      if (!Number.isInteger(it.quantity) || it.quantity < 1 || it.quantity > 1000) errors.push('items.quantity');
    }
  }
  return [...new Set(errors)];
}

function createApp({ store, logger = console }) {
  const state = { ready: true };

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    try {
      // Liveness: is the process able to serve at all? Never checks dependencies,
      // so a DB outage does not cause a restart storm.
      if (req.method === 'GET' && url.pathname === '/healthz') return send(res, 200, { status: 'ok' });

      // Readiness: can this pod do useful work right now? Removed from the Service/ALB if not.
      if (req.method === 'GET' && url.pathname === '/readyz') {
        if (!state.ready) return send(res, 503, { status: 'draining' });
        const ok = await store.ping().then(() => true, () => false);
        return send(res, ok ? 200 : 503, { status: ok ? 'ready' : 'db-unavailable' });
      }

      if (req.method === 'POST' && url.pathname === '/orders') {
        const key = req.headers['idempotency-key'];
        if (typeof key !== 'string' || !/^[A-Za-z0-9-]{8,64}$/.test(key)) {
          return send(res, 400, { error: 'Idempotency-Key header required' });
        }
        const body = await readJson(req);
        const errors = validateOrder(body);
        if (errors.length) return send(res, 422, { error: 'validation failed', fields: errors });

        const requestHash = crypto.createHash('sha256').update(JSON.stringify(body)).digest('hex');
        const result = await store.createOrder({ idempotencyKey: key, requestHash, order: body });
        if (result.conflict) return send(res, 409, { error: 'Idempotency-Key reused with a different body' });
        return send(res, result.created ? 201 : 200, result.order);
      }

      const m = url.pathname.match(/^\/orders\/([0-9a-f-]{36})$/);
      if (req.method === 'GET' && m) {
        const order = await store.getOrder(m[1]);
        return order ? send(res, 200, order) : send(res, 404, { error: 'not found' });
      }

      return send(res, 404, { error: 'not found' });
    } catch (err) {
      if (err.status) return send(res, err.status, { error: err.message });
      // Never log request bodies or credentials - only the error class and message.
      logger.error(JSON.stringify({ level: 'error', msg: 'request failed', path: url.pathname, err: err.code || err.message }));
      return send(res, 500, { error: 'internal error' });
    }
  });

  // Graceful shutdown: fail readiness first so the ALB/Service stops routing,
  // wait for in-flight requests, then close DB connections.
  async function drain(waitMs = 10000) {
    state.ready = false;
    await new Promise((r) => setTimeout(r, waitMs));
    await new Promise((r) => server.close(r));
    await store.close();
  }

  return { server, drain, state };
}

module.exports = { createApp, validateOrder };
