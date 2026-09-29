import test from 'node:test';
import assert from 'node:assert/strict';
import Database from 'better-sqlite3';
import { readFileSync } from 'node:fs';
import { ensureDatabaseReady } from '../src/db/ensureDatabaseReady.js';
import { APP_SCHEMA_VERSION } from '../src/db/migrations/sqlite/engine/version.js';

function makeDatabase(t) {
  const sqlite = new Database(':memory:');
  sqlite.pragma('foreign_keys = ON');
  t.after(() => sqlite.close());
  return {
    sqlite,
    prepare(sql) {
      const statement = sqlite.prepare(sql);
      let params = [];
      return {
        bind(...values) { params = values; return this; },
        async run() { const result = statement.run(...params); return { success: true, meta: result }; },
        async first() { return statement.get(...params) ?? null; },
        async all() { return { results: statement.all(...params) }; },
      };
    },
  };
}

async function makeLegacyDatabase(db, { withRows = true } = {}) {
  await ensureDatabaseReady({ db });
  // v20 has no paste visibility/title, nor the tables introduced in v21+.
  db.sqlite.exec(`
    DELETE FROM schema_migrations;
    INSERT INTO system_settings (key, value) VALUES ('schema_version', '20');
    DROP INDEX idx_pastes_is_public;
    ALTER TABLE pastes DROP COLUMN is_public;
    ALTER TABLE pastes DROP COLUMN title;
    DROP TABLE fs_meta;
    DROP TABLE metrics_cache;
    DROP TABLE upload_parts;
    DROP TABLE vfs_nodes;
    DROP TABLE scheduled_job_runs;
    DROP TABLE scheduled_jobs;
    DROP TABLE upload_sessions;
    DROP TABLE tasks;
  `);
  if (withRows) {
    db.sqlite.prepare('INSERT INTO pastes (id, slug, content) VALUES (?, ?, ?)').run('legacy-paste', 'keep-me', 'existing content');
    db.sqlite.prepare('UPDATE admins SET password = ?').run('existing-password-hash');
  } else {
    db.sqlite.exec('DELETE FROM admins; DELETE FROM api_keys;');
  }
}

for (const withRows of [true, false]) {
  test(`upgrades v20 with missing newer tables (${withRows ? 'with data' : 'empty business tables'})`, async t => {
    const db = makeDatabase(t);
    await makeLegacyDatabase(db, { withRows });
    await ensureDatabaseReady({ db });
    const columns = db.sqlite.prepare('PRAGMA table_info(pastes)').all().map(row => row.name);
    assert.ok(columns.includes('is_public'));
    assert.ok(columns.includes('title'));
    assert.ok(db.sqlite.prepare("SELECT name FROM sqlite_master WHERE name = 'metrics_cache'").get());
    assert.ok(db.sqlite.prepare("SELECT name FROM sqlite_master WHERE name = 'scheduled_jobs'").get());
    assert.equal(db.sqlite.prepare("SELECT COUNT(*) AS n FROM schema_migrations WHERE id LIKE 'app-v%'").get().n, APP_SCHEMA_VERSION);
    if (withRows) {
      const paste = db.sqlite.prepare("SELECT * FROM pastes WHERE id = 'legacy-paste'").get();
      assert.equal(paste.content, 'existing content');
      assert.equal(paste.is_public, 1);
      assert.equal(db.sqlite.prepare('SELECT password FROM admins').get().password, 'existing-password-hash');
    }
    await ensureDatabaseReady({ db });
    assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get().n, APP_SCHEMA_VERSION + 1);
  });
}

test('initializes a fresh database and seeds one admin only', async t => {
  const db = makeDatabase(t);
  await ensureDatabaseReady({ db });
  await ensureDatabaseReady({ db });
  assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM admins').get().n, 1);
  assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get().n, APP_SCHEMA_VERSION + 1);
});

test('upgrades the deployed v4 schema and preserves existing admin and paste', async t => {
  const db = makeDatabase(t);
  db.sqlite.exec(readFileSync(new URL('./fixtures/schema-v4.sql', import.meta.url), 'utf8'));
  db.sqlite.prepare('INSERT INTO admins (id, username, password) VALUES (?, ?, ?)').run('existing-admin', 'owner', 'keep-password-hash');
  db.sqlite.prepare('INSERT INTO pastes (id, slug, content) VALUES (?, ?, ?)').run('existing-paste', 'saved', 'keep-content');
  await ensureDatabaseReady({ db });
  assert.equal(db.sqlite.prepare('SELECT password FROM admins').get().password, 'keep-password-hash');
  assert.equal(db.sqlite.prepare('SELECT content FROM pastes').get().content, 'keep-content');
  assert.ok(db.sqlite.prepare('PRAGMA table_info(pastes)').all().some(c => c.name === 'is_public'));
  assert.ok(db.sqlite.prepare("SELECT name FROM sqlite_master WHERE name = 'storage_configs'").get());
  assert.equal(db.sqlite.prepare('SELECT COUNT(*) AS n FROM schema_migrations').get().n, APP_SCHEMA_VERSION + 1);
  await ensureDatabaseReady({ db });
});
