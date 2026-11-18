#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="$SCRIPT_DIR/agents"
SKILLS_SRC="$SCRIPT_DIR/skills"

TARGET_DIR=""
FORCE=false
DRY_RUN=false
CREATE_DIR=false
UNINSTALL=false

usage() {
    cat <<EOF
Uso: $(basename "$0") [opções]

Procura a pasta global de configuração do OpenCode e cria links simbólicos
para os agents e skills deste repositório.

Opções:
  -t, --target DIR   Define manualmente o diretório global do OpenCode
  -c, --create       Cria o diretório global padrão (~/.config/opencode) caso não exista
  -f, --force        Substitui links ou arquivos/pastas existentes (faz backup de não-links)
  -n, --dry-run      Mostra as ações que seriam executadas sem alterar o sistema
  -u, --uninstall    Remove apenas os links simbólicos que apontam para este repositório
  -h, --help         Exibe esta ajuda
EOF
}

log_info() { printf '[info] %s\n' "$1"; }
log_ok() { printf '[ok]   %s\n' "$1"; }
log_warn() { printf '[aviso] %s\n' "$1" >&2; }
log_err() { printf '[erro] %s\n' "$1" >&2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--target)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                log_err "A opção $1 exige um caminho."
                exit 1
            fi
            TARGET_DIR="$2"
            shift 2
            ;;
        -c|--create)
            CREATE_DIR=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -u|--uninstall)
            UNINSTALL=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_err "Opção desconhecida: $1"
            usage
            exit 1
            ;;
    esac
done

find_opencode_dir() {
    if [[ -n "$TARGET_DIR" ]]; then
        printf '%s\n' "${TARGET_DIR/#\~/$HOME}"
        return 0
    fi

    if [[ -n "${OPENCODE_CONFIG_DIR:-}" ]]; then
        printf '%s\n' "${OPENCODE_CONFIG_DIR/#\~/$HOME}"
        return 0
    fi

    local candidates=(
        "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
        "$HOME/.config/opencode"
        "$HOME/.opencode"
    )

    local dir
    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done

    return 1
}

resolve_subdir() {
    local base="$1"
    local preferred="$2"
    local fallback="$3"

    if [[ -d "$base/$preferred" ]]; then
        printf '%s\n' "$base/$preferred"
    elif [[ -d "$base/$fallback" ]]; then
        printf '%s\n' "$base/$fallback"
    else
        printf '%s\n' "$base/$preferred"
    fi
}

link_item() {
    local src="$1"
    local dest="$2"
    local label="$3"

    if [[ -L "$dest" ]]; then
        local current_target
        current_target="$(readlink -f "$dest" 2>/dev/null || readlink "$dest")"
        local expected_target
        expected_target="$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")"

        if [[ "$current_target" == "$expected_target" ]]; then
            log_ok "$label já está vinculado: $dest -> $src"
            return 0
        fi

        if [[ "$FORCE" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[dry-run] Atualizaria symlink: $dest -> $src"
            else
                ln -sfn "$src" "$dest"
                log_ok "$label atualizado: $dest -> $src"
            fi
        else
            log_warn "$label já existe apontando para outro destino ($current_target). Use --force para substituir: $dest"
        fi
        return 0
    fi

    if [[ -e "$dest" ]]; then
        if [[ "$FORCE" == true ]]; then
            local backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[dry-run] Moveria existente para $backup e criaria symlink: $dest -> $src"
            else
                mv "$dest" "$backup"
                ln -s "$src" "$dest"
                log_ok "$label substituído (backup em $backup): $dest -> $src"
            fi
        else
            log_warn "$label já existe e não é um link simbólico. Use --force para fazer backup e substituir: $dest"
        fi
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[dry-run] Criaria symlink: $dest -> $src"
    else
        mkdir -p "$(dirname "$dest")"
        ln -s "$src" "$dest"
        log_ok "$label vinculado: $dest -> $src"
    fi
}

unlink_item() {
    local src="$1"
    local dest="$2"
    local label="$3"

    if [[ ! -L "$dest" ]]; then
        return 0
    fi

    local current_target
    current_target="$(readlink -f "$dest" 2>/dev/null || readlink "$dest")"
    local expected_target
    expected_target="$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")"

    if [[ "$current_target" == "$expected_target" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[dry-run] Removeria symlink: $dest"
        else
            rm "$dest"
            log_ok "$label desvinculado: $dest"
        fi
    fi
}

OPENCODE_DIR=""
if ! OPENCODE_DIR="$(find_opencode_dir)"; then
    DEFAULT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
    if [[ "$CREATE_DIR" == true ]] || command -v opencode >/dev/null 2>&1; then
        OPENCODE_DIR="$DEFAULT_DIR"
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[dry-run] Criaria diretório global do OpenCode em: $OPENCODE_DIR"
        else
            mkdir -p "$OPENCODE_DIR"
            log_info "Diretório global do OpenCode criado em: $OPENCODE_DIR"
        fi
    else
        log_err "Pasta global do OpenCode não encontrada."
        log_err "Locais verificados: \$OPENCODE_CONFIG_DIR, ${XDG_CONFIG_HOME:-$HOME/.config}/opencode, $HOME/.config/opencode, $HOME/.opencode"
        log_err "Use --create para criar $DEFAULT_DIR ou --target <caminho> para informar outro diretório."
        exit 1
    fi
elif [[ ! -d "$OPENCODE_DIR" ]]; then
    if [[ "$CREATE_DIR" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[dry-run] Criaria diretório: $OPENCODE_DIR"
        else
            mkdir -p "$OPENCODE_DIR"
            log_info "Diretório criado: $OPENCODE_DIR"
        fi
    else
        log_err "O diretório informado não existe: $OPENCODE_DIR (use --create para criá-lo)."
        exit 1
    fi
fi

log_info "Diretório global do OpenCode: $OPENCODE_DIR"

SKILLS_DEST="$(resolve_subdir "$OPENCODE_DIR" "skills" "skill")"
AGENTS_DEST="$(resolve_subdir "$OPENCODE_DIR" "agents" "agent")"

if [[ "$UNINSTALL" == false && "$DRY_RUN" == false ]]; then
    mkdir -p "$SKILLS_DEST" "$AGENTS_DEST"
fi

if [[ -d "$SKILLS_SRC" ]]; then
    for skill_dir in "$SKILLS_SRC"/*/; do
        [[ -d "$skill_dir" ]] || continue
        skill_dir="${skill_dir%/}"
        [[ -f "$skill_dir/SKILL.md" ]] || continue
        skill_name="$(basename "$skill_dir")"
        if [[ "$UNINSTALL" == true ]]; then
            unlink_item "$skill_dir" "$SKILLS_DEST/$skill_name" "Skill ($skill_name)"
        else
            link_item "$skill_dir" "$SKILLS_DEST/$skill_name" "Skill ($skill_name)"
        fi
    done
fi

if [[ -d "$AGENTS_SRC" ]]; then
    for agent_file in "$AGENTS_SRC"/*.md; do
        [[ -f "$agent_file" ]] || continue
        agent_name="$(basename "$agent_file")"
        if [[ "$UNINSTALL" == true ]]; then
            unlink_item "$agent_file" "$AGENTS_DEST/$agent_name" "Agent ($agent_name)"
        else
            link_item "$agent_file" "$AGENTS_DEST/$agent_name" "Agent ($agent_name)"
        fi
    done
fi

