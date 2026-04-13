FROM node:20-slim AS builder
WORKDIR /app

# Install bun
RUN npm install -g bun

# Install all dependencies (including devDeps for build)
COPY package.json bun.lock ./
COPY patches/ patches/
COPY scripts/postinstall.js scripts/postinstall.js
RUN bun install

# Copy source
COPY . .

# Build renderer (no Electron needed) and server bundle
RUN bun run build:renderer:web
RUN node scripts/build-server.mjs

# ---- Runtime image ----
FROM oven/bun:latest AS runtime
WORKDIR /app

# Install system deps for CLI agents
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget ca-certificates python3 ruby ruby-dev build-essential git \
    && rm -rf /var/lib/apt/lists/*

# Install lightweight CLI agents (~50MB RAM each, thin API wrappers)
# Kimi CLI (Moonshot)
RUN npm install -g @anthropic-ai/kimi-cli@latest 2>/dev/null || \
    npm install -g kimi-cli@latest 2>/dev/null || true
# Qwen Code CLI (Alibaba/OpenRouter)
RUN npm install -g @anthropic-ai/qwen-code@latest 2>/dev/null || \
    npm install -g @qwen-code/qwen-code@latest 2>/dev/null || true
# OpenCode (Go binary)
RUN curl -fsSL https://opencode.ai/install | bash 2>/dev/null || true
# OpenAI Codex CLI (~200MB RAM, remote LLM calls via OpenRouter)
RUN npm install -g @openai/codex@latest 2>/dev/null || true
# Google Gemini CLI (~50MB RAM, free tier 60 req/min)
RUN npm install -g @google/gemini-cli@latest 2>/dev/null || true
# Nano Bot is NOT ACP-compatible — intentionally excluded

# Create Qwen wrapper to auto-inject --auth-type openai for ACP mode
RUN if [ -f /usr/local/lib/node_modules/@qwen-code/qwen-code/cli.js ]; then \
    rm -f /usr/local/bin/qwen && \
    printf '#!/bin/bash\nREAL_QWEN=/usr/local/lib/node_modules/@qwen-code/qwen-code/cli.js\ncase "$1" in\n  auth|config|mcp|extensions|hooks|channel)\n    exec "$REAL_QWEN" "$@"\n    ;;\n  *)\n    exec "$REAL_QWEN" --auth-type openai "$@"\n    ;;\nesac\n' > /usr/local/bin/qwen && \
    chmod +x /usr/local/bin/qwen; \
    fi

# Copy build artifacts and pre-built node_modules from builder
COPY --from=builder /app/dist-server ./dist-server
COPY --from=builder /app/out/renderer ./out/renderer
COPY --from=builder /app/node_modules ./node_modules

# Entrypoint script configures CLI agent auth from env vars on each start
COPY docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

ENV PORT=3000
ENV NODE_ENV=production
ENV ALLOW_REMOTE=true
ENV DATA_DIR=/data

# SQLite data volume — mount with: -v $(pwd)/data:/data
VOLUME ["/data"]
EXPOSE 3000

ENTRYPOINT ["/app/docker-entrypoint.sh"]
