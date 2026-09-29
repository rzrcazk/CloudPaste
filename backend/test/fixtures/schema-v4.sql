-- Schema from c9741cfe (v4), with runtime system_settings.
-- 创建pastes表 - 存储文本分享数据
CREATE TABLE pastes (
  id TEXT PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  content TEXT NOT NULL,
  remark TEXT,
  password TEXT,
  expires_at DATETIME,
  max_views INTEGER,
  views INTEGER DEFAULT 0,
  created_by TEXT,                     -- 创建者标识（管理员ID或API密钥ID）
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 创建索引
CREATE INDEX idx_pastes_slug ON pastes(slug);
CREATE INDEX idx_pastes_created_at ON pastes(created_at DESC);
CREATE INDEX idx_pastes_created_by ON pastes(created_by);    -- 添加创建者索引

-- 创建admins表 - 存储管理员信息
CREATE TABLE admins (
  id TEXT PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  password TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 创建admin_tokens表 - 存储管理员认证令牌
CREATE TABLE admin_tokens (
  token TEXT PRIMARY KEY,
  admin_id TEXT NOT NULL,
  expires_at DATETIME NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE CASCADE
);

-- 创建api_keys表 - 存储API密钥
CREATE TABLE api_keys (
  id TEXT PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  key TEXT UNIQUE NOT NULL,
  text_permission BOOLEAN DEFAULT 0,
  file_permission BOOLEAN DEFAULT 0,
  mount_permission BOOLEAN DEFAULT 0,
  last_used DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL -- 默认一天后过期
);

-- 创建s3_configs表 - 存储S3配置信息
CREATE TABLE s3_configs (
  id TEXT PRIMARY KEY,                 -- 配置唯一标识
  name TEXT NOT NULL,                  -- 配置名称（用户友好的名称，如"我的项目备份B2"）
  provider_type TEXT NOT NULL,         -- 提供商类型（Cloudflare R2, Backblaze B2, AWS S3, 其他）
  endpoint_url TEXT NOT NULL,          -- S3 API端点URL
  bucket_name TEXT NOT NULL,           -- 存储桶名称
  region TEXT,                         -- 存储桶区域（对AWS S3必须，对其他可选）
  access_key_id TEXT NOT NULL,         -- 访问密钥ID（加密存储）
  secret_access_key TEXT NOT NULL,     -- 秘密访问密钥（加密存储）
  path_style BOOLEAN DEFAULT 0,        -- 是否使用路径样式访问（1=是，0=否）
  default_folder TEXT DEFAULT '',      -- 默认上传文件夹路径
  is_public BOOLEAN DEFAULT 0,         -- 是否为公开允许API密钥用户使用
  is_default BOOLEAN DEFAULT 0,       -- 是否为默认配置
  total_storage_bytes BIGINT,          -- 存储桶总容量（字节数），用于计算使用百分比，NULL表示使用默认值
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_used DATETIME,                  -- 最后使用时间
  admin_id TEXT,                       -- 关联的管理员ID
  FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE CASCADE
);

-- 创建files表 - 存储已上传文件的元数据
CREATE TABLE files (
  id TEXT PRIMARY KEY,
  filename TEXT NOT NULL,              -- 原始文件名
  storage_path TEXT NOT NULL,          -- S3存储路径
  s3_url TEXT,                         -- 完整的S3访问URL（可选，可由storage_path生成）
  mimetype TEXT NOT NULL,              -- 文件MIME类型
  size INTEGER NOT NULL,               -- 文件大小（字节）
  s3_config_id TEXT NOT NULL,          -- 使用的S3配置ID
  slug TEXT UNIQUE NOT NULL,           -- 用于访问文件的短链接
  remark TEXT,                         -- 文件备注
  password TEXT,                       -- 可选密码保护
  expires_at DATETIME,                 -- 过期时间
  max_views INTEGER,                   -- 最大查看次数
  views INTEGER DEFAULT 0,             -- 当前查看次数
  etag TEXT,                           -- S3 ETag（用于验证）
  created_by TEXT,                     -- 创建者标识（可选，用于多用户系统）
  use_proxy BOOLEAN DEFAULT 1,         -- 是否使用Worker代理访问（1=是，0=否）
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (s3_config_id) REFERENCES s3_configs(id) ON DELETE CASCADE
);

-- 添加索引提升查询性能
CREATE INDEX idx_files_slug ON files(slug);
CREATE INDEX idx_files_s3_config_id ON files(s3_config_id);
CREATE INDEX idx_files_created_at ON files(created_at);
CREATE INDEX idx_files_expires_at ON files(expires_at);

-- 创建file_passwords表 - 存储文件密码
CREATE TABLE file_passwords (
  file_id TEXT NOT NULL,
  plain_password TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (file_id) REFERENCES files(id) ON DELETE CASCADE
);

-- 创建paste_passwords表 - 存储文本密码
CREATE TABLE paste_passwords (
  paste_id TEXT NOT NULL,
  plain_password TEXT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (paste_id) REFERENCES pastes(id) ON DELETE CASCADE
);

-- 创建system_settings表 - 存储系统设置
CREATE TABLE system_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 创建storage_mounts表 - 存储挂载配置
CREATE TABLE storage_mounts (
  id TEXT PRIMARY KEY,                  -- 唯一标识
  name TEXT NOT NULL,                   -- 挂载点名称
  storage_type TEXT NOT NULL,           -- 存储类型(S3, WebDAV等)
  storage_config_id TEXT,               -- 关联的存储配置ID (对S3类型，关联s3_configs表)
  mount_path TEXT NOT NULL,             -- 挂载路径，如 /photos
  remark TEXT,                          -- 备注说明
  is_active BOOLEAN DEFAULT 1,          -- 是否启用
  created_by TEXT NOT NULL,             -- 创建者标识
  sort_order INTEGER DEFAULT 0,         -- 显示排序顺序
  cache_ttl INTEGER DEFAULT 300,        -- 缓存时间(秒)，提高性能
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_used DATETIME                    -- 最后使用时间
);

-- 创建索引
CREATE INDEX idx_storage_mounts_mount_path ON storage_mounts(mount_path);
CREATE INDEX idx_storage_mounts_storage_config_id ON storage_mounts(storage_config_id);
CREATE INDEX idx_storage_mounts_created_by ON storage_mounts(created_by);
CREATE INDEX idx_storage_mounts_is_active ON storage_mounts(is_active);
CREATE INDEX idx_storage_mounts_sort_order ON storage_mounts(sort_order);


INSERT INTO system_settings (key, value) VALUES ('schema_version', '4');
