#!/bin/bash
# 作者: wangqiupei
# 功能: 根据账号截止日期自动更新优先级
# 优先级 = 剩余天数
# 使用方法: ./update_priority_by_expiry.sh

set -e

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/config/config.json}"
MAX_RETRIES="${MAX_RETRIES:-3}"  # 最大重试次数
RETRY_DELAY="${RETRY_DELAY:-2}"  # 重试延迟（秒）

# 从配置文件读取配置信息
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件不存在: $CONFIG_FILE"
    exit 1
fi

# 读取 Admin API Key
ADMIN_API_KEY=$(jq -r '.adminApiKey' "$CONFIG_FILE")
if [ -z "$ADMIN_API_KEY" ] || [ "$ADMIN_API_KEY" = "null" ]; then
    echo "错误: 无法从配置文件读取 adminApiKey"
    exit 1
fi

# 读取服务地址和端口（如果未通过环境变量指定）
if [ -z "$API_BASE_URL" ]; then
    HOST=$(jq -r '.host // "0.0.0.0"' "$CONFIG_FILE")
    PORT=$(jq -r '.port // 8990' "$CONFIG_FILE")

    # 如果 host 是 0.0.0.0，替换为 localhost
    if [ "$HOST" = "0.0.0.0" ]; then
        HOST="localhost"
    fi

    # 检查是否在 Docker 环境中运行，尝试从 docker-compose.yml 读取端口映射
    DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
    if [ -f "$DOCKER_COMPOSE_FILE" ]; then
        # 尝试提取端口映射（格式：主机端口:容器端口）
        MAPPED_PORT=$(grep -A 5 "ports:" "$DOCKER_COMPOSE_FILE" | grep -E "\"[0-9]+:$PORT\"" | sed -E 's/.*"([0-9]+):.*/\1/' | head -1)
        if [ -n "$MAPPED_PORT" ] && [ "$MAPPED_PORT" != "$PORT" ]; then
            echo "检测到 Docker 端口映射: $MAPPED_PORT -> $PORT" >&2
            PORT=$MAPPED_PORT
        fi
    fi

    API_BASE_URL="http://${HOST}:${PORT}/api/admin"
fi

# 带重试的 API 调用函数
call_api_with_retry() {
    local url="$1"
    local attempt=1
    local response=""

    while [ $attempt -le $MAX_RETRIES ]; do
        response=$(curl -s -H "x-api-key: $ADMIN_API_KEY" "$url")
        local error_msg=$(echo "$response" | jq -r '.error.message // empty')

        if [ -z "$error_msg" ]; then
            echo "$response"
            return 0
        fi

        # 网络错误且未达到最大重试次数则重试
        if echo "$error_msg" | grep -q "error sending request"; then
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "  ⚠️  网络错误 (尝试 $attempt/$MAX_RETRIES)，${RETRY_DELAY}秒后重试..." >&2
                sleep $RETRY_DELAY
                attempt=$((attempt + 1))
                continue
            fi
        fi

        echo "$response"
        return 1
    done
}

echo "========================================="
echo "  根据截止日期自动更新账号优先级"
echo "========================================="
echo ""
echo "配置信息："
echo "  API 地址: $API_BASE_URL"
echo "  配置文件: $CONFIG_FILE"
echo ""

# 获取当前时间戳（秒）
CURRENT_TIMESTAMP=$(date +%s)

# 获取所有账号 ID
echo "正在获取账号列表..."
CREDENTIALS_RESPONSE=$(curl -s -H "x-api-key: $ADMIN_API_KEY" "$API_BASE_URL/credentials")

# 检查响应是否为空
if [ -z "$CREDENTIALS_RESPONSE" ]; then
    echo "错误: API 无响应"
    echo ""
    echo "故障排查："
    echo "1. 检查服务是否运行："
    echo "   docker compose ps"
    echo ""
    echo "2. 检查服务日志："
    echo "   docker compose logs kiro-rs"
    echo ""
    echo "3. 测试 API 连接："
    echo "   curl -H \"x-api-key: $ADMIN_API_KEY\" $API_BASE_URL/credentials"
    exit 1
fi

# 检查是否有错误
API_ERROR=$(echo "$CREDENTIALS_RESPONSE" | jq -r '.error.message // empty')
if [ -n "$API_ERROR" ]; then
    echo "错误: API 返回错误"
    echo "  错误信息: $API_ERROR"
    echo ""
    echo "故障排查："
    echo "1. 检查 Admin API Key 是否正确"
    echo "2. 检查配置文件: $CONFIG_FILE"
    exit 1
fi

# 提取账号 ID
CREDENTIAL_IDS=$(echo "$CREDENTIALS_RESPONSE" | jq -r '.credentials[].id')

if [ -z "$CREDENTIAL_IDS" ]; then
    echo "错误: 无法获取账号列表（响应中没有账号数据）"
    echo ""
    echo "API 响应内容："
    echo "$CREDENTIALS_RESPONSE" | jq '.' 2>/dev/null || echo "$CREDENTIALS_RESPONSE"
    exit 1
fi

TOTAL_COUNT=$(echo "$CREDENTIAL_IDS" | wc -l | tr -d ' ')
echo "找到 $TOTAL_COUNT 个账号"
echo ""

# 统计信息
SUCCESS_COUNT=0
SKIP_COUNT=0
ERROR_COUNT=0

# 遍历每个账号
for ID in $CREDENTIAL_IDS; do
    echo "处理账号 ID: $ID"

    # 获取账号余额信息（包含 freeTrialExpiry），带重试
    BALANCE_RESPONSE=$(call_api_with_retry "$API_BASE_URL/credentials/$ID/balance")

    # 检查是否有错误
    ERROR_MSG=$(echo "$BALANCE_RESPONSE" | jq -r '.error.message // empty')
    if [ -n "$ERROR_MSG" ]; then
        echo "  ❌ 跳过: $ERROR_MSG"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        echo ""
        continue
    fi

    # 提取 freeTrialExpiry
    FREE_TRIAL_EXPIRY=$(echo "$BALANCE_RESPONSE" | jq -r '.freeTrialExpiry // empty')

    if [ -z "$FREE_TRIAL_EXPIRY" ] || [ "$FREE_TRIAL_EXPIRY" = "null" ]; then
        echo "  ⚠️  跳过: 无截止日期信息"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        echo ""
        continue
    fi

    # 计算剩余天数（向上取整）
    # freeTrialExpiry 是浮点数，需要转换为整数
    EXPIRY_INT=$(echo "$FREE_TRIAL_EXPIRY" | awk '{printf "%.0f", $1}')
    REMAINING_SECONDS=$((EXPIRY_INT - CURRENT_TIMESTAMP))
    REMAINING_DAYS=$(( (REMAINING_SECONDS + 86399) / 86400 ))  # 向上取整

    # 如果已过期，剩余天数为 0
    if [ $REMAINING_DAYS -lt 0 ]; then
        REMAINING_DAYS=0
    fi

    # 计算新优先级（优先级 = 剩余天数）
    NEW_PRIORITY=$REMAINING_DAYS

    # 格式化截止日期（兼容 macOS 和 Linux）
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        EXPIRY_DATE=$(date -d "@$EXPIRY_INT" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "无效日期")
    else
        # BSD date (macOS)
        EXPIRY_DATE=$(date -r "$EXPIRY_INT" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "无效日期")
    fi

    echo "  截止日期: $EXPIRY_DATE"
    echo "  剩余天数: $REMAINING_DAYS 天"
    echo "  新优先级: $NEW_PRIORITY"

    # 更新优先级
    UPDATE_RESPONSE=$(curl -s -X POST \
        -H "x-api-key: $ADMIN_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"priority\": $NEW_PRIORITY}" \
        "$API_BASE_URL/credentials/$ID/priority")

    # 检查更新结果
    UPDATE_ERROR=$(echo "$UPDATE_RESPONSE" | jq -r '.error.message // empty')
    if [ -n "$UPDATE_ERROR" ]; then
        echo "  ❌ 更新失败: $UPDATE_ERROR"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    else
        echo "  ✅ 更新成功"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi

    echo ""
done

# 输出统计信息
echo "========================================="
echo "  更新完成"
echo "========================================="
echo "总计: $TOTAL_COUNT 个账号"
echo "成功: $SUCCESS_COUNT 个"
echo "跳过: $SKIP_COUNT 个"
echo "失败: $ERROR_COUNT 个"
echo ""
