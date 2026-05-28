#!/bin/bash
# 预配置 Claude Code，跳过首次引导并指向自定义 API 端点

CLAUDE_CONFIG_DIR="/work/.claude"
CLAUDE_CONFIG_FILE="${CLAUDE_CONFIG_DIR}/settings.json"
CLAUDE_ONBOARDING_FILE="/work/.claude.json"

mkdir -p "$CLAUDE_CONFIG_DIR"

# 跳过首次引导（禁止 Claude Code 要求登录）
cat > "$CLAUDE_ONBOARDING_FILE" << EOF
{
  "hasCompletedOnboarding": true
}
EOF

# 如果环境变量提供了自定义 API 信息，则生成配置文件
if [ -n "$ANTHROPIC_BASE_URL" ] && [ -n "$ANTHROPIC_AUTH_TOKEN" ]; then
    cat > "$CLAUDE_CONFIG_FILE" << EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$ANTHROPIC_BASE_URL",
    "ANTHROPIC_AUTH_TOKEN": "$ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${ANTHROPIC_MODEL:-claude-3-opus-20240229}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${ANTHROPIC_MODEL:-claude-3-sonnet-20240229}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${ANTHROPIC_MODEL:-claude-3-haiku-20240307}"
  }
}
EOF
    echo "Claude Code configured with custom endpoint: $ANTHROPIC_BASE_URL"
else
    echo "Warning: ANTHROPIC_BASE_URL or ANTHROPIC_AUTH_TOKEN not set. Claude Code will try default Anthropic endpoint."
fi

# 卸载不兼容的 nbdime 扩展
pip3 uninstall -y nbdime 2>/dev/null || true

# 启动 JupyterLab 以 root 用户运行
exec jupyter lab --allow-root --NotebookApp.token='' --NotebookApp.password=''