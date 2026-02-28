# 账号优先级自动更新脚本

## 脚本版本

### 基础版 (`update_priority_by_expiry.sh`)
- 简单直接，快速执行
- 遇到网络错误会跳过该账号
- 适合网络稳定的环境

### 增强版 (`update_priority_by_expiry_v2.sh`)
- 支持自动重试机制（默认重试 3 次）
- 可配置重试延迟
- 适合网络不稳定的环境
- 推荐在生产环境使用

## 功能说明

根据账号的"截止日期"（`freeTrialExpiry`）自动计算并更新优先级。

**计算规则：**
```
优先级 = 剩余天数
```

- 剩余天数 = (截止日期 - 当前日期) / 86400，向上取整
- 优先级数值越小，账号优先级越高
- 这样可以确保即将过期的账号优先使用

## 使用方法

### 1. 基本用法

确保 kiro 服务正在运行：

```bash
docker compose up -d
```

执行脚本（自动从配置文件读取服务地址和端口）：

```bash
# 在项目根目录执行
./scripts/update_priority_by_expiry.sh

# 或者在任意目录执行（脚本会自动定位项目根目录）
/path/to/kiro.rs/scripts/update_priority_by_expiry.sh
```

**注意**：脚本会自动检测项目根目录，无需手动指定配置文件路径。

### 2. 自定义配置

脚本会自动从 `config/config.json` 读取以下配置：
- `adminApiKey` - Admin API 密钥（必需）
- `host` - 服务地址（默认 0.0.0.0，自动转换为 localhost）
- `port` - 服务端口（默认 8990）

也可以通过环境变量覆盖配置：

```bash
# 自定义 API 地址（完全覆盖）
API_BASE_URL=http://localhost:8990/api/admin ./scripts/update_priority_by_expiry.sh

# 自定义配置文件路径
CONFIG_FILE=/path/to/config.json ./scripts/update_priority_by_expiry.sh

# 自定义重试参数
MAX_RETRIES=5 RETRY_DELAY=3 ./scripts/update_priority_by_expiry.sh
```

### 3. 定时任务

可以使用 cron 定时执行脚本，每天自动更新优先级：

```bash
# 编辑 crontab
crontab -e

# 添加定时任务（每天凌晨 2 点执行）
0 2 * * * cd /path/to/kiro.rs && ./scripts/update_priority_by_expiry.sh >> /tmp/update_priority.log 2>&1
```

## 输出示例

```
=========================================
  根据截止日期自动更新账号优先级
=========================================

正在获取账号列表...
找到 10 个账号

处理账号 ID: 1
  截止日期: 2026-05-05 12:30:45
  剩余天数: 66 天
  新优先级: 66
  ✅ 更新成功

处理账号 ID: 2
  截止日期: 2026-03-26 21:03:49
  剩余天数: 26 天
  新优先级: 26
  ✅ 更新成功

...

=========================================
  更新完成
=========================================
总计: 10 个账号
成功: 8 个
跳过: 1 个
失败: 1 个
```

## 依赖要求

- `bash` shell
- `curl` - HTTP 请求工具
- `jq` - JSON 处理工具
- `date` - 日期计算工具（自动兼容 macOS 和 Linux）
- kiro 服务运行中（通过 `docker compose up -d` 启动）

**平台支持：**
- ✅ macOS（BSD date）
- ✅ Linux（GNU date）
- ✅ 自动检测并使用正确的 date 命令语法

## 配置说明

脚本会自动从项目根目录的 `config/config.json` 读取以下配置：

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `adminApiKey` | Admin API 密钥 | 必需 |
| `host` | 服务地址 | `0.0.0.0`（自动转换为 `localhost`） |
| `port` | 服务端口 | `8990` |

**路径说明**：
- 脚本自动检测项目根目录（脚本所在目录的上级目录）
- 配置文件路径：`项目根目录/config/config.json`
- 无需手动指定配置文件路径

环境变量优先级高于配置文件：

| 环境变量 | 说明 | 示例 |
|----------|------|------|
| `API_BASE_URL` | 完整 API 地址（覆盖 host 和 port） | `http://localhost:8990/api/admin` |
| `CONFIG_FILE` | 配置文件路径 | `/path/to/config.json` |
| `MAX_RETRIES` | 最大重试次数 | `3` |
| `RETRY_DELAY` | 重试延迟（秒） | `2` |

## 注意事项

1. **服务必须运行**：脚本通过 Admin API 更新优先级，需要 kiro 服务正在运行
2. **自动读取配置**：脚本自动从 `config/config.json` 读取 API Key、服务地址和端口
3. **环境变量优先**：可通过环境变量覆盖配置文件中的设置
4. **权限要求**：确保脚本有执行权限（`chmod +x`）
5. **数据安全**：脚本仅更新优先级字段，不会修改其他账号信息
6. **重试机制**：网络错误会自动重试（默认 3 次），其他错误直接跳过

## 工作原理

1. 从配置文件读取 Admin API Key
2. 调用 `/api/admin/credentials` 获取所有账号 ID
3. 对每个账号：
   - 调用 `/api/admin/credentials/:id/balance` 获取截止日期
   - 计算剩余天数
   - 调用 `/api/admin/credentials/:id/priority` 更新优先级
4. 输出统计信息

## 故障排查

### 错误: /bin/bash^M: 解释器错误

**原因**：脚本文件包含 Windows 风格的换行符（CRLF）

**解决方法**：

```bash
# 方法 1: 使用 dos2unix（推荐）
dos2unix scripts/update_priority_by_expiry.sh

# 方法 2: 使用 sed
sed -i 's/\r$//' scripts/update_priority_by_expiry.sh

# 方法 3: 重新克隆仓库（确保 Git 配置正确）
git config core.autocrlf input
git rm --cached -r .
git reset --hard
```

### 错误: 配置文件不存在

确保配置文件路径正确：

```bash
ls -la config/config.json
```

### 错误: 无法获取账号列表

检查服务是否运行：

```bash
docker compose ps
curl -H "x-api-key: sk-admin2012" http://localhost:8990/api/admin/credentials
```

### 错误: 命令未找到

安装缺失的依赖：

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq curl
```

## 相关文档

- [Admin API 文档](../docs/admin-api.md)
- [负载均衡模式](../docs/load-balancing.md)
