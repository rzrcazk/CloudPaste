import { DbTables } from "../../../../constants/index.js";
import {
  deleteLegacySchemaKeysFromSystemSettings,
  getExistingTableSet,
  getLegacySchemaVersionFromSystemSettings,
  looksLikeExistingDatabase,
  makeVersionMigrationId,
  markMigrationsApplied,
  APP_SCHEMA_VERSION,
} from "./adoptUtils.js";
import { initDatabase } from "../engine/initDatabase.js";

const ADOPT_ID = "app-adopt-schema-migrations";


export default {
  id: ADOPT_ID,
  async up({ db }) {
    const existingTables = await getExistingTableSet(db);
    const hasSystemSettings = existingTables.has(DbTables.SYSTEM_SETTINGS);

    // 若已执行过 adopt，则直接退出
    try {
      const already = await db.prepare(`SELECT 1 AS ok FROM schema_migrations WHERE id = ?`).bind(ADOPT_ID).first();
      if (already) return false;
    } catch {
      // schema_migrations 不存在时会由 runner 先创建；这里忽略
    }

    // legacyVersion 仅用于“旧库接管”：若旧库有 schema_version，则按其版本上限预标记 app-v01..app-vN
    const legacyVersion = hasSystemSettings ? await getLegacySchemaVersionFromSystemSettings(db) : 0;

    const isExistingDb = await looksLikeExistingDatabase(db, existingTables);
    const needsInitialization = legacyVersion === 0 && !isExistingDb;

    // 老库缺少新版表是正常升级场景，必须先按版本迁移。
    // 直接初始化最终态会在旧表缺少新列时提前创建索引并失败。
    // 只有无旧版本、无业务数据的新库才初始化并 squash。
    if (needsInitialization) {
      await initDatabase(db);
    }

    // adopt 标记范围：
    // - 旧库：按 legacy schema_version（上限为当前应用版本）
    // - 新库：按当前应用版本（已初始化到最终态）
    const capVersion =
      legacyVersion > 0
        ? Math.min(legacyVersion, APP_SCHEMA_VERSION)
        : needsInitialization
          ? APP_SCHEMA_VERSION
          : 0;

    if (capVersion <= 0) {
      // 极少数情况：老库存在业务数据，但缺失 schema_version，无法安全推断版本。
      // 这里不做 squash 标记，避免错误接管。
      return false;
    }
    const ids = [];
    for (let v = 1; v <= capVersion; v++) {
      ids.push(makeVersionMigrationId(v));
    }

    await markMigrationsApplied(db, ids);

    if (hasSystemSettings) {
      await deleteLegacySchemaKeysFromSystemSettings(db);
    }

    return true;
  },
};
