#!/usr/bin/env bash
# install.sh — instala o dx (binário em ~/.local/bin) e o skill do Claude Code
# (em ~/.claude/skills/dx), ambos por symlink pro repositório.
#
# Uso:
#   ./install.sh              Instala binário + skill (symlinks; recomendado)
#   ./install.sh --copy       Copia o binário em vez de symlink (não segue updates)
#   ./install.sh --no-skill   Instala só o binário (pula o skill do Claude Code)
#   ./install.sh --uninstall  Remove binário e skill instalados
#   ./install.sh --help
#
# Env:
#   DX_BIN_DIR      (default: ~/.local/bin)       onde instalar o binário
#   DX_SKILLS_DIR   (default: ~/.claude/skills)   onde instalar o skill
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SRC_DIR/dx"
SKILL_SRC="$SRC_DIR/skill"
BIN_DIR="${DX_BIN_DIR:-$HOME/.local/bin}"
DEST="$BIN_DIR/dx"
SKILLS_DIR="${DX_SKILLS_DIR:-$HOME/.claude/skills}"
SKILL_DEST="$SKILLS_DIR/dx"

green()  { printf '\033[1;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }

mode=symlink
want_skill=1
case "${1:-}" in
  ""|--symlink) mode=symlink ;;
  --copy)       mode=copy ;;
  --no-skill)   want_skill=0 ;;
  --uninstall)
    for p in "$DEST" "$SKILL_DEST"; do
      if [[ -e "$p" || -L "$p" ]]; then rm -f "$p"; green "removido: $p"; else yellow "nada a remover em $p"; fi
    done
    exit 0 ;;
  -h|--help)
    sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//;s/^set -.*//'
    exit 0 ;;
  *) red "opção desconhecida: $1 (use --copy | --no-skill | --uninstall | --help)"; exit 1 ;;
esac

# ── Binário ─────────────────────────────────────────────────────
[[ -f "$SRC" ]] || { red "não encontrei o script em $SRC"; exit 1; }
chmod +x "$SRC"
mkdir -p "$BIN_DIR"

if [[ "$mode" == symlink ]]; then
  ln -sfn "$SRC" "$DEST"
  green "binário: symlink $DEST -> $SRC"
else
  cp "$SRC" "$DEST"; chmod +x "$DEST"
  green "binário: copiado em $DEST"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) green "OK: $BIN_DIR já está no PATH" ;;
  *)
    yellow "ATENÇÃO: $BIN_DIR não está no PATH."
    yellow "Adicione ao seu ~/.bashrc (ou ~/.profile) e reabra o shell:"
    echo  "    export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

# ── Skill do Claude Code (opcional) ─────────────────────────────
if [[ $want_skill -eq 1 ]]; then
  if [[ -f "$SKILL_SRC/SKILL.md" ]]; then
    mkdir -p "$SKILLS_DIR"
    ln -sfn "$SKILL_SRC" "$SKILL_DEST"
    green "skill:   symlink $SKILL_DEST -> $SKILL_SRC"
    echo  "         (o Claude Code carrega o skill 'dx' sob demanda em qualquer projeto)"
  else
    yellow "skill não encontrado em $SKILL_SRC/SKILL.md — pulando."
  fi
else
  yellow "skill: pulado (--no-skill)"
fi

# ── Status final ────────────────────────────────────────────────
if command -v dx >/dev/null 2>&1; then
  green "pronto: 'dx' disponível em $(command -v dx)"
  echo  "teste:  dx --help"
else
  yellow "instalado, mas 'dx' ainda não resolve no PATH deste shell — reabra o terminal."
fi
