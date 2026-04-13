#!/bin/bash
set -e

# === CLI Agent Auth Setup ===
# Configure agent credentials from environment variables on each container start.
# This ensures auth persists even after container rebuilds.

# Codex CLI: login with API key + set model/provider config + conditional MCP servers
if command -v codex &>/dev/null && [ -n "$OPENAI_API_KEY" ]; then
  mkdir -p /root/.codex
  echo "$OPENAI_API_KEY" | codex login --with-api-key 2>/dev/null || true

  # Write base config
  cat > /root/.codex/config.toml <<EOF
model = "${CODEX_MODEL:-qwen/qwen3.5-plus-02-15}"
model_provider = "openai"
sandbox_mode = "workspace-write"

[api_base_url]
openai = "${OPENAI_BASE_URL:-https://openrouter.ai/api/v1}"
EOF

  # Append MCP servers only when their credentials are provided via env vars
  if [ -n "$COMPOSIO_API_KEY" ]; then
    cat >> /root/.codex/config.toml <<EOF

[mcp_servers.composio]
url = "https://connect.composio.dev/mcp"
headers = { "x-consumer-api-key" = "$COMPOSIO_API_KEY" }
EOF
  fi

  if [ -n "$GARZA_MCP_TOKEN" ]; then
    cat >> /root/.codex/config.toml <<EOF

[mcp_servers.garza]
url = "https://mcp.garzaos.cloud/sse"
headers = { "Authorization" = "Bearer $GARZA_MCP_TOKEN" }
EOF
  fi

  if [ -n "$NEXTCLOUD_MCP_TOKEN" ]; then
    cat >> /root/.codex/config.toml <<EOF

[mcp_servers.nextcloud]
url = "${NEXTCLOUD_MCP_URL:-https://mcp-next.garzaos.online/mcp}"
headers = { "Authorization" = "Bearer $NEXTCLOUD_MCP_TOKEN" }
EOF
  fi
fi

# Kimi CLI: write config.toml with provider/model definitions
if command -v kimi &>/dev/null && [ -n "$KIMI_API_KEY" ]; then
  mkdir -p /root/.kimi
  cat > /root/.kimi/config.toml <<EOF
default_model = "kimi-latest"

[providers.kimi]
type = "kimi"
base_url = "https://api.moonshot.cn/v1"
api_key = "$KIMI_API_KEY"

[models.kimi-latest]
provider = "kimi"
model = "kimi-latest"
max_context_size = 131072
EOF
fi

# Qwen Code CLI: write settings.json with OpenRouter provider
if command -v qwen &>/dev/null && [ -n "$OPENROUTER_API_KEY" ]; then
  mkdir -p /root/.qwen
  cat > /root/.qwen/settings.json <<EOF
{
  "modelProviders": {
    "openai": [
      {
        "id": "${QWEN_MODEL:-qwen/qwen3-235b-a22b}",
        "envKey": "OPENROUTER_API_KEY",
        "baseUrl": "https://openrouter.ai/api/v1"
      }
    ]
  },
  "security": {
    "auth": {
      "selectedType": "openai"
    }
  },
  "model": {
    "name": "${QWEN_MODEL:-qwen/qwen3-235b-a22b}"
  },
  "\$version": 3
}
EOF
fi

# OpenCode: uses OPENAI_API_KEY + OPENAI_BASE_URL env vars directly (no config needed)
# Remove any stale config that might conflict
rm -f /root/.config/opencode/config.json 2>/dev/null || true

echo "[entrypoint] CLI agent auth + MCP servers configured"

# Start the server
exec bun dist-server/server.mjs
