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

resolve_path() {
    local target="$1"
    local resolved=""

    if resolved="$(readlink -f "$target" 2>/dev/null)" && [[ -n "$resolved" ]]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    local suffix=""
    local cur="$target"
    while [[ ! -e "$cur" && "$cur" != "/" && "$cur" != "." ]]; do
        suffix="/$(basename "$cur")$suffix"
        cur="$(dirname "$cur")"
    done

    if [[ -d "$cur" ]]; then
        cur="$(cd "$cur" 2>/dev/null && pwd -P)"
    elif [[ -e "$cur" ]]; then
        cur="$(cd "$(dirname "$cur")" 2>/dev/null && pwd -P)/$(basename "$cur")"
    fi

    if [[ -z "$suffix" ]]; then
        printf '%s\n' "$cur"
    else
        printf '%s%s\n' "${cur%/}" "$suffix"
    fi
}

is_within_dir() {
    local path="$1"
    local root="$2"

    if [[ "$root" == "/" ]]; then
        [[ "$path" == /* ]]
    else
        [[ "$path" == "$root" || "$path" == "$root/"* ]]
    fi
}

compute_relative_path() {
    local target="$1"
    local base_dir="$2"

    target="${target%/}"
    base_dir="${base_dir%/}"

    if [[ "$target" == "$base_dir" ]]; then
        printf '.\n'
        return 0
    fi

    local -a target_parts=()
    local -a base_parts=()

    if [[ -n "${target#/}" ]]; then
        IFS='/' read -r -a target_parts <<< "${target#/}"
    fi
    if [[ -n "${base_dir#/}" ]]; then
        IFS='/' read -r -a base_parts <<< "${base_dir#/}"
    fi

    local common=0
    local max_common="${#target_parts[@]}"
    if [[ "${#base_parts[@]}" -lt "$max_common" ]]; then
        max_common="${#base_parts[@]}"
    fi

    while [[ "$common" -lt "$max_common" && "${target_parts[$common]}" == "${base_parts[$common]}" ]]; do
        common=$((common + 1))
    done

    local rel=""
    local i
    for ((i = common; i < ${#base_parts[@]}; i++)); do
        rel="${rel:+$rel/}.."
    done
    for ((i = common; i < ${#target_parts[@]}; i++)); do
        rel="${rel:+$rel/}${target_parts[$i]}"
    done

    printf '%s\n' "${rel:-.}"
}

resolve_link_target() {
    local src="$1"
    local dest="$2"

    local canonical_opencode
    local canonical_src
    local canonical_dest_dir

    canonical_opencode="$(resolve_path "$OPENCODE_DIR")"
    canonical_src="$(resolve_path "$src")"
    canonical_dest_dir="$(resolve_path "$(dirname "$dest")")"

    if is_within_dir "$canonical_src" "$canonical_opencode" && is_within_dir "$canonical_dest_dir" "$canonical_opencode"; then
        compute_relative_path "$canonical_src" "$canonical_dest_dir"
    else
        printf '%s\n' "$src"
    fi
}

link_item() {
    local src="$1"
    local dest="$2"
    local label="$3"

    local link_target
    link_target="$(resolve_link_target "$src" "$dest")"

    if [[ -L "$dest" ]]; then
        local raw_target
        raw_target="$(readlink "$dest")"
        local current_target
        current_target="$(resolve_path "$dest")"
        local expected_target
        expected_target="$(resolve_path "$src")"

        if [[ "$current_target" == "$expected_target" ]]; then
            if [[ "$raw_target" == "$link_target" ]]; then
                log_ok "$label já está vinculado: $dest -> $link_target"
                return 0
            fi

            if [[ "$FORCE" == true ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    log_info "[dry-run] Atualizaria symlink: $dest -> $link_target"
                else
                    ln -sfn "$link_target" "$dest"
                    log_ok "$label atualizado: $dest -> $link_target"
                fi
            else
                log_warn "$label já está vinculado com outro formato ($raw_target). Use --force para atualizar para: $link_target"
            fi
            return 0
        fi

        if [[ "$FORCE" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[dry-run] Atualizaria symlink: $dest -> $link_target"
            else
                ln -sfn "$link_target" "$dest"
                log_ok "$label atualizado: $dest -> $link_target"
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
                log_info "[dry-run] Moveria existente para $backup e criaria symlink: $dest -> $link_target"
            else
                mv "$dest" "$backup"
                ln -s "$link_target" "$dest"
                log_ok "$label substituído (backup em $backup): $dest -> $link_target"
            fi
        else
            log_warn "$label já existe e não é um link simbólico. Use --force para fazer backup e substituir: $dest"
        fi
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[dry-run] Criaria symlink: $dest -> $link_target"
    else
        mkdir -p "$(dirname "$dest")"
        ln -s "$link_target" "$dest"
        log_ok "$label vinculado: $dest -> $link_target"
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
    current_target="$(resolve_path "$dest")"
    local expected_target
    expected_target="$(resolve_path "$src")"

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

