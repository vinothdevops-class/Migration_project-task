'use strict';
// MySQL store. Credentials come from AWS Secrets Manager at runtime (never env vars,
// files or the image). The pod's IRSA role is the only identity allowed to read the secret.

const crypto = require('node:crypto');
const fs = require('node:fs');
const mysql = require('mysql2/promise');
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const sm = new SecretsManagerClient({}); // credentials: IRSA web-identity token, injected by EKS

async function fetchDbSecret(secretArn) {
  const out = await sm.send(new GetSecretValueCommand({ SecretId: secretArn }));
  const s = JSON.parse(out.SecretString);
  return { user: s.username, password: s.password };
}

async function createMysqlStore({ secretArn, host, database, caPath }) {
  const ssl = { ca: fs.readFileSync(caPath), rejectUnauthorized: true, minVersion: 'TLSv1.2' };
  let pool;

  async function connect() {
    const creds = await fetchDbSecret(secretArn);
    const next = mysql.createPool({ host, database, ...creds, ssl, connectionLimit: 10, waitForConnections: true });
    const old = pool;
    pool = next;
    if (old) old.end().catch(() => {});
  }

  // If Secrets Manager rotated the password, the next login fails with ER_ACCESS_DENIED:
  // re-read the secret once and retry, so rotation needs no pod restart.
  async function query(sql, params) {
    try {
      return await pool.query(sql, params);
    } catch (err) {
      if (err.code !== 'ER_ACCESS_DENIED_ERROR') throw err;
      await connect();
      return pool.query(sql, params);
    }
  }

  await connect();

  return {
    async ping() {
      await query('SELECT 1');
    },

    async createOrder({ idempotencyKey, requestHash, order }) {
      const [existing] = await query(
        'SELECT id, request_hash, customer_id, items, status, created_at FROM orders WHERE idempotency_key = ?',
        [idempotencyKey],
      );
      if (existing.length) {
        const row = existing[0];
        if (row.request_hash !== requestHash) return { conflict: true };
        return { created: false, order: toOrder(row) };
      }
      const id = crypto.randomUUID();
      try {
        await query(
          'INSERT INTO orders (id, idempotency_key, request_hash, customer_id, items, status) VALUES (?, ?, ?, ?, ?, ?)',
          [id, idempotencyKey, requestHash, order.customerId, JSON.stringify(order.items), 'PENDING'],
        );
      } catch (err) {
        // Two concurrent retries with the same key: the UNIQUE index decides the winner.
        if (err.code === 'ER_DUP_ENTRY') return this.createOrder({ idempotencyKey, requestHash, order });
        throw err;
      }
      return { created: true, order: { id, customerId: order.customerId, items: order.items, status: 'PENDING' } };
    },

    async getOrder(id) {
      const [rows] = await query('SELECT id, customer_id, items, status, created_at FROM orders WHERE id = ?', [id]);
      return rows.length ? toOrder(rows[0]) : null;
    },

    async close() {
      if (pool) await pool.end();
    },
  };
}

function toOrder(row) {
  return {
    id: row.id,
    customerId: row.customer_id,
    items: typeof row.items === 'string' ? JSON.parse(row.items) : row.items,
    status: row.status,
    createdAt: row.created_at,
  };
}

module.exports = { createMysqlStore };
