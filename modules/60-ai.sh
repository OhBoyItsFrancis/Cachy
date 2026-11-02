# shellcheck shell=bash
# Claude Code (CLI), Claude Desktop, and Ollama (CUDA) for local models.
#
#  cloud: `claude` (CLI) + Claude Desktop, both from the CachyOS repo, so they
#         update with the system. Cloud sessions / Remote Control work from
#         the CLI once logged in (`claude` then /login).
#  local: Ollama on the RTX 3080 + `claude-local`, which points Claude Code at
#         Ollama's Anthropic-compatible API (Ollama >= 0.14).

pkg_install claude-code \
    git github-cli ripgrep fd jq \
    nodejs npm uv \
    bubblewrap socat

if is_true "$INSTALL_CLAUDE_DESKTOP"; then
    # optdepends: tray icon, keyring for credentials, GTK portal
    pkg_install claude-desktop libayatana-appindicator gnome-keyring xdg-desktop-portal-gtk
fi

if is_true "$INSTALL_OLLAMA"; then
    pkg_install ollama-cuda
    # Claude Code sends long prompts with many tools: give models a big context
    # window, and use flash attention + q8 KV cache so it fits in 10 GB VRAM.
    write_file /etc/systemd/system/ollama.service.d/cachy.conf <<'EOF'
# Managed by cachy-setup (modules/60-ai.sh)
[Service]
Environment="OLLAMA_CONTEXT_LENGTH=65536"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_KEEP_ALIVE=10m"
EOF
    svc_enable ollama.service
    install -Dm0755 "$CACHY_ROOT/bin/claude-local" /usr/local/bin/claude-local
    # remember the default local model for claude-local
    write_file /etc/cachy-ai.conf <<EOF
# Default model for claude-local (override per run: claude-local --model X)
OLLAMA_MODEL="${OLLAMA_MODEL}"
EOF
fi
ok "AI tools done"
