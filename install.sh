#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="$SCRIPT_DIR/agents"
SKILLS_SRC="$SCRIPT_DIR/skills"

PLUGIN_NAME="site-builder-skill"
PLUGIN_DISPLAY_NAME="Site Builder Skill"
PLUGIN_DESCRIPTION="Agente e skill para criação de sites estáticos, bio-links, SEO local e deploy no Cloudflare Pages."

TARGET_DIR=""
FORCE=false
DRY_RUN=false
CREATE_DIR=false
UNINSTALL=false
ANTIGRAVITY=false

usage() {
    cat <<EOF
Uso: $(basename "$0") [opções]

Procura a pasta global de configuração do OpenCode e cria links simbólicos
para os agents e skills deste repositório.
Com -a/--antigravity, instala ou atualiza este repositório como plugin no Antigravity.

Opções:
  -a, --antigravity  Instala como plugin do Antigravity em ~/.gemini/config/plugins/$PLUGIN_NAME
  -t, --target DIR   Define manualmente o diretório base (OpenCode ou config do Antigravity)
  -c, --create       Cria o diretório alvo caso não exista
  -f, --force        Substitui links ou arquivos/pastas existentes (faz backup de não-links)
  -n, --dry-run      Mostra as ações que seriam executadas sem alterar o sistema
  -u, --uninstall    Remove apenas os vínculos/arquivos gerados por este repositório
  -h, --help         Exibe esta ajuda
EOF
}

log_info() { printf '[info] %s\n' "$1"; }
log_ok() { printf '[ok]   %s\n' "$1"; }
log_warn() { printf '[aviso] %s\n' "$1" >&2; }
log_err() { printf '[erro] %s\n' "$1" >&2; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--antigravity)
            ANTIGRAVITY=true
            shift
            ;;
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

TREE_ROOT=""

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

find_antigravity_dir() {
    if [[ -n "$TARGET_DIR" ]]; then
        printf '%s\n' "${TARGET_DIR/#\~/$HOME}"
        return 0
    fi

    if [[ -n "${ANTIGRAVITY_CONFIG_DIR:-}" ]]; then
        printf '%s\n' "${ANTIGRAVITY_CONFIG_DIR/#\~/$HOME}"
        return 0
    fi

    local default_dir="$HOME/.gemini/config"
    if [[ -d "$default_dir" || -d "$HOME/.gemini/antigravity" || "$CREATE_DIR" == true ]]; then
        printf '%s\n' "$default_dir"
        return 0
    fi

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

    local canonical_root
    local canonical_src
    local canonical_dest_dir

    canonical_root="$(resolve_path "$TREE_ROOT")"
    canonical_src="$(resolve_path "$src")"
    canonical_dest_dir="$(resolve_path "$(dirname "$dest")")"

    if is_within_dir "$canonical_src" "$canonical_root" && is_within_dir "$canonical_dest_dir" "$canonical_root"; then
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

sync_generated_file() {
    local tmp_src="$1"
    local dest="$2"
    local label="$3"

    if [[ -L "$dest" ]]; then
        if [[ "$FORCE" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[dry-run] Substituiria symlink por arquivo gerado ($label): $dest"
            else
                rm "$dest"
                mkdir -p "$(dirname "$dest")"
                cp "$tmp_src" "$dest"
                log_ok "$label criado: $dest"
            fi
        else
            log_warn "$label já existe como symlink. Use --force para substituir: $dest"
        fi
        return 0
    fi

    if [[ -e "$dest" ]]; then
        if cmp -s "$tmp_src" "$dest"; then
            log_ok "$label já está atualizado: $dest"
            return 0
        fi

        if [[ "$FORCE" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[dry-run] Atualizaria $label: $dest"
            else
                cp "$tmp_src" "$dest"
                log_ok "$label atualizado: $dest"
            fi
        else
            log_warn "$label já existe com conteúdo diferente. Use --force para atualizar: $dest"
        fi
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[dry-run] Criaria $label: $dest"
    else
        mkdir -p "$(dirname "$dest")"
        cp "$tmp_src" "$dest"
        log_ok "$label criado: $dest"
    fi
}

remove_generated_file() {
    local dest="$1"
    local label="$2"

    if [[ ! -e "$dest" && ! -L "$dest" ]]; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[dry-run] Removeria $label: $dest"
    else
        rm -f "$dest"
        log_ok "$label removido: $dest"
    fi
}

write_plugin_json() {
    local out_file="$1"
    python3 - "$out_file" "$PLUGIN_NAME" "$PLUGIN_DISPLAY_NAME" "$PLUGIN_DESCRIPTION" <<'PYEOF'
import json
import sys

out_file, name, display_name, description = sys.argv[1:5]
payload = {
    "name": name,
    "displayName": display_name,
    "version": "1.0.0",
    "description": description,
}
with open(out_file, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PYEOF
}

convert_agent_for_antigravity() {
    local src_file="$1"
    local out_file="$2"
    python3 - "$src_file" "$out_file" <<'PYEOF'
import json
import os
import re
import sys

src_file, out_file = sys.argv[1:3]
agent_name = os.path.splitext(os.path.basename(src_file))[0]

with open(src_file, "r", encoding="utf-8") as fh:
    content = fh.read()

fm_text = ""
body = content
if content.startswith("---\n"):
    end = content.find("\n---\n", 4)
    if end != -1:
        fm_text = content[4:end]
        body = content[end + 5:]
    elif content.endswith("\n---"):
        fm_text = content[4:-4]
        body = ""

description = ""
lines = fm_text.splitlines()
i = 0
while i < len(lines):
    line = lines[i]
    m = re.match(r"^description:\s*(.*)$", line)
    if m:
        parts = []
        first = m.group(1).strip()
        if first and first not in (">-", "|", ">", "|-"):
            parts.append(first)
        i += 1
        while i < len(lines) and (lines[i].startswith(" ") or lines[i].startswith("\t") or lines[i] == ""):
            if lines[i].strip():
                parts.append(lines[i].strip())
            i += 1
        description = " ".join(parts).strip()
        if len(description) >= 2 and (
            (description[0] == '"' and description[-1] == '"')
            or (description[0] == "'" and description[-1] == "'")
        ):
            description = description[1:-1]
        break
    i += 1

if not description:
    description = f"Subagent {agent_name}."

edit_denied = bool(
    re.search(r"^\s+edit:\s*deny\b", fm_text, re.MULTILINE)
    or re.search(r"action:\s*edit\s*\n(?:.*\n){0,2}?\s*effect:\s*deny\b", fm_text)
)
has_task = bool(
    re.search(r"^\s+task:", fm_text, re.MULTILINE)
    or re.search(r"action:\s*subagent\s*\n(?:.*\n){0,2}?\s*effect:\s*allow\b", fm_text)
)
has_question = bool(re.search(r"^\s+question:\s*allow\b", fm_text, re.MULTILINE))
has_all_allow = bool(re.search(r'^\s+"\*":\s*allow\b', fm_text, re.MULTILINE))
has_test_runners = bool(
    re.search(r"(composer|vendor/bin/|php artisan|npm |pnpm |yarn |mvn|gradle)", fm_text)
)

tools = ["read_file"]
if not edit_denied:
    tools.extend(["edit_file", "write_file"])
tools.append("run_command")
if (not edit_denied and agent_name != "analyst") or has_test_runners:
    tools.append("manage_task")
if has_task:
    tools.extend(["invoke_subagent", "send_message", "manage_subagents"])
if has_question:
    tools.append("ask_question")
if has_all_allow:
    tools.append("search_web")

tools_line = "[" + ", ".join(tools) + "]"
desc_escaped = json.dumps(description, ensure_ascii=False)

body_clean = body.lstrip("\n")
with open(out_file, "w", encoding="utf-8") as fh:
    fh.write("---\n")
    fh.write(f"name: {agent_name}\n")
    fh.write(f"description: {desc_escaped}\n")
    fh.write("subagent: true\n")
    fh.write("mainAgent: false\n")
    fh.write(f"tools: {tools_line}\n")
    fh.write("---\n\n")
    fh.write(body_clean)
    if body_clean and not body_clean.endswith("\n"):
        fh.write("\n")
PYEOF
}

write_plugin_rules() {
    local agents_dir="$1"
    local out_file="$2"
    python3 - "$agents_dir" "$out_file" "$PLUGIN_DISPLAY_NAME" <<'PYEOF'
import glob
import os
import re
import sys

agents_dir, out_file, display_name = sys.argv[1:4]
agent_files = sorted(glob.glob(os.path.join(agents_dir, "*.md")))

entries = []
for path in agent_files:
    name = os.path.splitext(os.path.basename(path))[0]
    with open(path, "r", encoding="utf-8") as fh:
        content = fh.read()
    desc = ""
    if content.startswith("---\n"):
        end = content.find("\n---\n", 4)
        fm_text = content[4:end] if end != -1 else ""
        lines = fm_text.splitlines()
        i = 0
        while i < len(lines):
            m = re.match(r"^description:\s*(.*)$", lines[i])
            if m:
                parts = []
                first = m.group(1).strip()
                if first and first not in (">-", "|", ">", "|-"):
                    parts.append(first)
                i += 1
                while i < len(lines) and (lines[i].startswith(" ") or lines[i].startswith("\t") or lines[i] == ""):
                    if lines[i].strip():
                        parts.append(lines[i].strip())
                    i += 1
                desc = " ".join(parts).strip()
                if len(desc) >= 2 and ((desc[0] == '"' and desc[-1] == '"') or (desc[0] == "'" and desc[-1] == "'")):
                    desc = desc[1:-1]
                break
            i += 1
    entries.append((name, desc or f"Subagent {name}."))

with open(out_file, "w", encoding="utf-8") as fh:
    fh.write(f"# Subagents de {display_name}\n\n")
    fh.write("Quando a solicitação do usuário corresponder a uma das especialidades abaixo, delegue para o subagent apropriado via `invoke_subagent`:\n\n")
    for name, desc in entries:
        fh.write(f"- `{name}`: {desc}\n")
PYEOF
}

if [[ "$ANTIGRAVITY" == true ]]; then
    if ! command -v python3 >/dev/null 2>&1; then
        log_err "python3 é necessário para instalar o plugin no Antigravity."
        exit 1
    fi

    AGY_DIR=""
    if ! AGY_DIR="$(find_antigravity_dir)"; then
        DEFAULT_AGY_DIR="$HOME/.gemini/config"
        log_err "Diretório de configuração do Antigravity não encontrado."
        log_err "Locais verificados: \$ANTIGRAVITY_CONFIG_DIR, $DEFAULT_AGY_DIR"
        log_err "Use --create para criar $DEFAULT_AGY_DIR ou --target <caminho> para informar outro diretório."
        exit 1
    elif [[ ! -d "$AGY_DIR" ]]; then
        if [[ "$CREATE_DIR" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_info "[dry-run] Criaria diretório: $AGY_DIR"
            else
                mkdir -p "$AGY_DIR"
                log_info "Diretório criado: $AGY_DIR"
            fi
        else
            log_err "O diretório informado não existe: $AGY_DIR (use --create para criá-lo)."
            exit 1
        fi
    fi

    TREE_ROOT="$AGY_DIR"
    PLUGIN_DIR="$AGY_DIR/plugins/$PLUGIN_NAME"
    SKILLS_DEST="$PLUGIN_DIR/skills"
    AGENTS_DEST="$PLUGIN_DIR/agents"
    RULES_DEST="$PLUGIN_DIR/rules"

    log_info "Diretório de configuração do Antigravity: $AGY_DIR"
    log_info "Plugin do Antigravity: $PLUGIN_DIR"

    if [[ "$UNINSTALL" == false && "$DRY_RUN" == false ]]; then
        mkdir -p "$PLUGIN_DIR"
    fi

    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT

    if [[ "$UNINSTALL" == true ]]; then
        if [[ -d "$SKILLS_SRC" ]]; then
            for skill_dir in "$SKILLS_SRC"/*/; do
                [[ -d "$skill_dir" ]] || continue
                skill_dir="${skill_dir%/}"
                [[ -f "$skill_dir/SKILL.md" ]] || continue
                skill_name="$(basename "$skill_dir")"
                unlink_item "$skill_dir" "$SKILLS_DEST/$skill_name" "Skill ($skill_name)"
            done
        fi

        if [[ -d "$AGENTS_SRC" ]]; then
            for agent_file in "$AGENTS_SRC"/*.md; do
                [[ -f "$agent_file" ]] || continue
                agent_name="$(basename "$agent_file")"
                remove_generated_file "$AGENTS_DEST/$agent_name" "Subagent ($agent_name)"
            done
            remove_generated_file "$RULES_DEST/AGENTS.md" "Regras (AGENTS.md)"
        fi

        remove_generated_file "$PLUGIN_DIR/plugin.json" "Manifesto (plugin.json)"

        if [[ "$DRY_RUN" == false ]]; then
            rmdir "$SKILLS_DEST" "$AGENTS_DEST" "$RULES_DEST" "$PLUGIN_DIR" 2>/dev/null || true
        fi
    else
        write_plugin_json "$tmp_dir/plugin.json"
        sync_generated_file "$tmp_dir/plugin.json" "$PLUGIN_DIR/plugin.json" "Manifesto (plugin.json)"

        if [[ -d "$SKILLS_SRC" ]]; then
            [[ "$DRY_RUN" == true ]] || mkdir -p "$SKILLS_DEST"
            for skill_dir in "$SKILLS_SRC"/*/; do
                [[ -d "$skill_dir" ]] || continue
                skill_dir="${skill_dir%/}"
                [[ -f "$skill_dir/SKILL.md" ]] || continue
                skill_name="$(basename "$skill_dir")"
                link_item "$skill_dir" "$SKILLS_DEST/$skill_name" "Skill ($skill_name)"
            done
        fi

        has_agents=false
        if [[ -d "$AGENTS_SRC" ]]; then
            for agent_file in "$AGENTS_SRC"/*.md; do
                [[ -f "$agent_file" ]] || continue
                has_agents=true
                agent_name="$(basename "$agent_file")"
                convert_agent_for_antigravity "$agent_file" "$tmp_dir/$agent_name"
                sync_generated_file "$tmp_dir/$agent_name" "$AGENTS_DEST/$agent_name" "Subagent ($agent_name)"
            done
        fi

        if [[ "$has_agents" == true ]]; then
            write_plugin_rules "$AGENTS_SRC" "$tmp_dir/AGENTS.md"
            sync_generated_file "$tmp_dir/AGENTS.md" "$RULES_DEST/AGENTS.md" "Regras (AGENTS.md)"
        fi
    fi

    exit 0
fi

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

TREE_ROOT="$OPENCODE_DIR"
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

