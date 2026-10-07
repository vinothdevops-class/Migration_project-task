'use strict';
const { createApp } = require('./app');
const { createMysqlStore } = require('./store');

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`missing env ${name}`);
  return v;
}

async function main() {
  // Only NON-secret configuration comes from the environment (ConfigMap).
  const store = await createMysqlStore({
    secretArn: required('DB_SECRET_ARN'),
    host: required('DB_HOST'),
    database: process.env.DB_NAME || 'orders',
    caPath: process.env.DB_CA_PATH || '/app/certs/rds-global-bundle.pem',
  });

  const { server, drain } = createApp({ store });
  const port = Number(process.env.PORT || 8080);
  server.keepAliveTimeout = 65000; // longer than the ALB idle timeout (60 s) to avoid 502s
  server.listen(port, () => console.log(JSON.stringify({ level: 'info', msg: 'listening', port })));

  const shutdown = async (sig) => {
    console.log(JSON.stringify({ level: 'info', msg: 'shutdown', sig }));
    await drain(Number(process.env.DRAIN_SECONDS || 10) * 1000);
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((err) => {
  console.error(JSON.stringify({ level: 'fatal', msg: 'startup failed', err: err.code || err.message }));
  process.exit(1);
});
