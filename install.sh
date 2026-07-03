#!/usr/bin/env bash
# Instala, para todos los agentes IA detectados, las skills catalogadas en
# skills.list usando el CLI oficial `npx skills`. Scope global o project
# segun la 4ta columna del manifiesto; el picker interactivo agrupa por
# categoria (global) o stack (project, 5ta columna), con checkboxes
# (flechas + espacio) cuando stdin es un TTY real; si no, fallback numerico.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$REPO_DIR/skills.list"

CATEGORIES=""   # vacio = todas
SCOPES=""       # vacio = todos (global, project)
DRY_RUN=0
LIST_ONLY=0
INTERACTIVE=1   # se desactiva si el usuario pasa --category/--scope/--list
AGENTS="claude-code,opencode"   # agentes destino (nombres de `npx skills`)
USE_COPY=0

usage() {
  cat <<EOF
Uso: ./install.sh [opciones]

Sin opciones: modo interactivo (pregunta global / project / ambos, y
te lista las skills agrupadas por bloque -categoria en global, stack en
project- con checkboxes: flechas para moverte, espacio marca/desmarca,
"a" marca/desmarca todo, Enter confirma).

  --category c1,c2   Instala solo esas categorias (default: todas), no interactivo
  --scope global|project   Instala solo ese scope (default: ambos), no interactivo
  --agents a1,a2       Agentes destino (default: $AGENTS). Ver 'npx skills' para nombres validos
  --dry-run            Muestra los comandos sin ejecutarlos
  --list                Lista el catalogo (categoria/skill/scope/stack/repo) y sale
  --copy                 Copia en vez de symlink (pasa --copy al CLI)
  -h, --help            Muestra esta ayuda

Catalogo: $MANIFEST
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --category) CATEGORIES="$2"; INTERACTIVE=0; shift 2 ;;
    --scope) SCOPES="$2"; INTERACTIVE=0; shift 2 ;;
    --agents) AGENTS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --list) LIST_ONLY=1; INTERACTIVE=0; shift ;;
    --copy) USE_COPY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opcion desconocida: $1" >&2; usage; exit 1 ;;
  esac
done

EXTRA_ARGS=("--agent" "$AGENTS" "--yes")
[[ $USE_COPY -eq 1 ]] && EXTRA_ARGS+=("--copy")

matches_filter() {
  local value="$1" csv="$2"
  [[ -z "$csv" ]] && return 0
  IFS=',' read -ra items <<< "$csv"
  for item in "${items[@]}"; do
    [[ "$item" == "$value" ]] && return 0
  done
  return 1
}

PROJECT_PATH=""   # destino para skills scope=project (CWD del proyecto)
FAILED_SKILLS=()  # skills que fallaron al instalar (no aborta la tanda)

install_one() {
  local category="$1" repo="$2" skill="$3" scope="$4"
  local cmd=(npx skills add "$repo" --skill "$skill" "${EXTRA_ARGS[@]}")
  [[ "$scope" == "global" ]] && cmd+=("--global")

  # scope=project instala en el CWD -> correr dentro del path del proyecto
  local run_dir=""
  [[ "$scope" == "project" && -n "$PROJECT_PATH" ]] && run_dir="$PROJECT_PATH"

  if [[ $DRY_RUN -eq 1 ]]; then
    [[ -n "$run_dir" ]] && echo "(cd $run_dir && ${cmd[*]})" || echo "${cmd[*]}"
    return
  fi
  echo "Instalando [$category/$scope] $skill desde $repo ..."
  local rc=0
  if [[ -n "$run_dir" ]]; then
    ( cd "$run_dir" && "${cmd[@]}" ) || rc=$?
  else
    "${cmd[@]}" || rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    echo "  ⚠ Fallo: $skill ($repo) — continuo con el resto." >&2
    FAILED_SKILLS+=("$skill ($repo)")
  fi
}

# --- modo no interactivo: filtros clasicos / --list ---
if [[ $INTERACTIVE -eq 0 ]]; then
  declare -A count_category=() count_scope=()
  total=0
  while IFS='|' read -r category repo skill scope stack; do
    [[ -z "$category" || "$category" == \#* ]] && continue
    matches_filter "$category" "$CATEGORIES" || continue
    matches_filter "$scope" "$SCOPES" || continue

    if [[ $LIST_ONLY -eq 1 ]]; then
      echo "$category/$skill  [$scope/$stack]  ($repo)"
      count_category["$category"]=$(( ${count_category["$category"]:-0} + 1 ))
      count_scope["$scope"]=$(( ${count_scope["$scope"]:-0} + 1 ))
      total=$((total + 1))
      continue
    fi
    install_one "$category" "$repo" "$skill" "$scope"
  done < "$MANIFEST"

  if [[ $LIST_ONLY -eq 1 ]]; then
    echo
    echo "Total: $total skills"
    local_cat=""
    for local_cat in "${!count_category[@]}"; do
      echo "  $local_cat: ${count_category[$local_cat]}"
    done
    for local_scope in "${!count_scope[@]}"; do
      echo "  scope=$local_scope: ${count_scope[$local_scope]}"
    done
  fi
  exit 0
fi

# Checkbox UI: flechas mueven, espacio marca/desmarca, "a" marca/desmarca
# todo, Enter confirma, q cancela. Lee de stdin (fd 0) — solo se usa
# cuando stdin es un TTY real; si no, el caller usa numeric_select.
# Arrays de entrada: mt_type[] (header|item), mt_label[], y opcional
# mt_default[] (0/1 por indice para pre-marcar). Deja el resultado
# (0/1 por indice) en mt_selected[].
checkbox_select() {
  [[ -t 0 ]] || return 1

  local n=${#mt_type[@]}
  mt_selected=()
  local i
  for ((i = 0; i < n; i++)); do mt_selected[i]="${mt_default[$i]:-0}"; done

  local cursor=-1
  for ((i = 0; i < n; i++)); do
    if [[ "${mt_type[$i]}" == "item" ]]; then cursor=$i; break; fi
  done
  [[ $cursor -eq -1 ]] && return 1

  render() {
    printf '\033[2J\033[H' >&2
    local j mark prefix
    for ((j = 0; j < n; j++)); do
      if [[ "${mt_type[$j]}" == "header" ]]; then
        printf '%s\n' "${mt_label[$j]}" >&2
      else
        mark=' '; [[ "${mt_selected[$j]}" == "1" ]] && mark='x'
        prefix='  '; [[ $j -eq $cursor ]] && prefix='> '
        printf '%s[%s] %s\n' "$prefix" "$mark" "${mt_label[$j]}" >&2
      fi
    done
    printf 'Flechas: mover | Espacio: marcar | a: todas | Enter: confirmar | q: cancelar\n' >&2
  }

  move_cursor() {
    local dir="$1" try=$cursor
    while true; do
      try=$((try + dir))
      [[ $try -lt 0 || $try -ge $n ]] && return
      if [[ "${mt_type[$try]}" == "item" ]]; then cursor=$try; return; fi
    done
  }

  local cancelled=0
  render
  while true; do
    local key rest
    IFS= read -rsn1 key || key=""
    if [[ "$key" == $'\x1b' ]]; then
      IFS= read -rsn2 -t 0.05 rest || rest=""
      key+="$rest"
    fi
    case "$key" in
      $'\x1b[A') move_cursor -1 ;;
      $'\x1b[B') move_cursor 1 ;;
      ' ')
        [[ "${mt_selected[$cursor]}" == "1" ]] && mt_selected[$cursor]=0 || mt_selected[$cursor]=1
        ;;
      a|A)
        local any_unselected=0 j
        for ((j = 0; j < n; j++)); do
          [[ "${mt_type[$j]}" == "item" && "${mt_selected[$j]}" == "0" ]] && any_unselected=1
        done
        for ((j = 0; j < n; j++)); do
          [[ "${mt_type[$j]}" == "item" ]] && mt_selected[$j]=$any_unselected
        done
        ;;
      q|Q) cancelled=1; break ;;
      '') break ;;
    esac
    render
  done

  [[ $cancelled -eq 1 ]] && mt_selected=()
  return 0
}

# Fallback no-TTY (stdin redirigido/pipe): mismo menu pero eligiendo por
# numeros separados por coma, como antes.
numeric_select() {
  local n=${#mt_type[@]} i
  mt_selected=()
  for ((i = 0; i < n; i++)); do mt_selected[i]="${mt_default[$i]:-0}"; done

  local idx=0
  for ((i = 0; i < n; i++)); do
    if [[ "${mt_type[$i]}" == "header" ]]; then
      echo "${mt_label[$i]}"
    else
      local pre=''; [[ "${mt_default[$i]:-0}" == "1" ]] && pre=' (pre-marcado)'
      echo "  [$idx] ${mt_label[$i]}$pre"
      mt_idx_of_pos[$idx]=$i
      idx=$((idx + 1))
    fi
  done

  read -rp "Elegir (numeros separados por coma; Enter = dejar pre-marcados): " picked
  [[ -z "$picked" ]] && return   # Enter vacio: respeta los pre-marcados
  # seleccion explicita: reemplaza los defaults
  for ((i = 0; i < n; i++)); do mt_selected[i]=0; done
  local nums n2 pos
  IFS=',' read -ra nums <<< "$picked"
  for n2 in "${nums[@]}"; do
    n2="$(echo "$n2" | tr -d '[:space:]')"
    [[ "$n2" =~ ^[0-9]+$ ]] || continue
    [[ $n2 -ge $idx ]] && continue
    pos="${mt_idx_of_pos[$n2]}"
    mt_selected[$pos]=1
  done
}

# Picker generico: filtra manifest por scope, agrupa por $group_col
# (category o stack), arma menu con headers + items ("TODAS", "todas de
# bloque", individuales), pide seleccion (checkbox o numerica) e instala.
pick_and_install() {
  local scope="$1" group_col="$2" label="$3"

  local lines=() blocks=() block_seen=""
  while IFS='|' read -r category repo skill sc stack; do
    [[ -z "$category" || "$category" == \#* ]] && continue
    [[ "$sc" == "$scope" ]] || continue
    lines+=("$category|$repo|$skill|$sc|$stack")
    local block
    [[ "$group_col" == "category" ]] && block="$category" || block="$stack"
    if [[ ",$block_seen," != *",$block,"* ]]; then
      blocks+=("$block")
      block_seen="$block_seen,$block"
    fi
  done < "$MANIFEST"

  if [[ ${#lines[@]} -eq 0 ]]; then
    echo "No hay skills de scope=$scope en el catalogo."
    return
  fi

  local mt_type=() mt_label=() mt_action=() mt_arg=()
  mt_type+=("header"); mt_label+=("$label (${#lines[@]} skills):")
  mt_type+=("item"); mt_label+=("TODAS las $label (${#lines[@]})"); mt_action+=("all"); mt_arg+=("")

  local block
  for block in "${blocks[@]}"; do
    local block_count=0 i line bl
    for i in "${!lines[@]}"; do
      line="${lines[$i]}"
      [[ "$group_col" == "category" ]] && bl="$(cut -d'|' -f1 <<< "$line")" || bl="$(cut -d'|' -f5 <<< "$line")"
      [[ "$bl" == "$block" ]] && block_count=$((block_count + 1))
    done

    mt_type+=("header"); mt_label+=("")
    mt_type+=("header"); mt_label+=("$block ($block_count):")
    mt_type+=("item"); mt_label+=(">>> TODAS DE $block <<<"); mt_action+=("block"); mt_arg+=("$block")

    for i in "${!lines[@]}"; do
      line="${lines[$i]}"
      [[ "$group_col" == "category" ]] && bl="$(cut -d'|' -f1 <<< "$line")" || bl="$(cut -d'|' -f5 <<< "$line")"
      [[ "$bl" == "$block" ]] || continue
      local skill_name
      skill_name="$(cut -d'|' -f3 <<< "$line")"
      mt_type+=("item"); mt_label+=("$skill_name"); mt_action+=("skill"); mt_arg+=("$i")
    done
  done

  echo
  local mt_selected=() mt_idx_of_pos=()
  if ! checkbox_select; then
    numeric_select
  fi

  # mapea items marcados (indices de mt_type/mt_label) a lineas del manifest
  declare -A selected_idx=()
  local item_pos=0 j
  for j in "${!mt_type[@]}"; do
    [[ "${mt_type[$j]}" == "item" ]] || continue
    if [[ "${mt_selected[$j]:-0}" == "1" ]]; then
      case "${mt_action[$item_pos]}" in
        all)
          local i; for i in "${!lines[@]}"; do selected_idx["$i"]=1; done ;;
        block)
          local i line bl
          for i in "${!lines[@]}"; do
            line="${lines[$i]}"
            [[ "$group_col" == "category" ]] && bl="$(cut -d'|' -f1 <<< "$line")" || bl="$(cut -d'|' -f5 <<< "$line")"
            [[ "$bl" == "${mt_arg[$item_pos]}" ]] && selected_idx["$i"]=1
          done ;;
        skill)
          selected_idx["${mt_arg[$item_pos]}"]=1 ;;
      esac
    fi
    item_pos=$((item_pos + 1))
  done

  echo
  local i
  for i in "${!lines[@]}"; do
    [[ -n "${selected_idx[$i]+x}" ]] || continue
    IFS='|' read -r category repo skill sc stack <<< "${lines[$i]}"
    install_one "$category" "$repo" "$skill" "$sc"
  done
}

# Agentes validos de `npx skills` (claude-code y opencode primero, pre-marcados).
ALL_AGENTS=(
  claude-code opencode cursor windsurf zed gemini-cli github-copilot codex
  cline roo continue aider-desk amp antigravity antigravity-cli astrbot
  autohand-code augment bob openclaw codearts-agent codebuddy codemaker
  codestudio command-code cortex crush deepagents devin dexto droid eve
  firebender forgecode goose hermes-agent inference-sh jazz junie iflow-cli
  kilo kimi-code-cli kiro-cli kode lingma loaf mcpjam mistral-vibe moxby mux
  openhands ona pi qoder qoder-cn qwen-code replit reasonix rovodev tabnine-cli
  terramind tinycloud trae trae-cn warp zencoder zenflow neovate pochi
  promptscript adal universal
)

# Picker de agentes destino -> setea AGENTS (csv) y reconstruye EXTRA_ARGS.
pick_agents() {
  local mt_type=() mt_label=() mt_default=() mt_selected=() mt_idx_of_pos=()
  mt_type+=("header"); mt_label+=("Agentes destino (pre-marcados: claude-code, opencode):"); mt_default+=("0")
  local a def
  for a in "${ALL_AGENTS[@]}"; do
    def=0
    [[ ",$AGENTS," == *",$a,"* ]] && def=1
    mt_type+=("item"); mt_label+=("$a"); mt_default+=("$def")
  done

  echo
  if ! checkbox_select; then
    numeric_select
  fi

  local chosen=() j item_pos=0
  for j in "${!mt_type[@]}"; do
    [[ "${mt_type[$j]}" == "item" ]] || continue
    [[ "${mt_selected[$j]:-0}" == "1" ]] && chosen+=("${ALL_AGENTS[$item_pos]}")
    item_pos=$((item_pos + 1))
  done

  if [[ ${#chosen[@]} -eq 0 ]]; then
    echo "No elegiste ningun agente. Uso el default: $AGENTS"
  else
    AGENTS="$(IFS=,; echo "${chosen[*]}")"
  fi
  EXTRA_ARGS=("--agent" "$AGENTS" "--yes")
  [[ $USE_COPY -eq 1 ]] && EXTRA_ARGS+=("--copy")
  echo "Agentes: $AGENTS"
}

# --- modo interactivo ---
pick_agents

echo
echo "Instalar: [1] Global  [2] Project (por stack)  [3] Ambos"
read -rp "Opcion: " choice

do_global=0
do_project=0
case "$choice" in
  1) do_global=1 ;;
  2) do_project=1 ;;
  3) do_global=1; do_project=1 ;;
  *) echo "Opcion invalida."; exit 1 ;;
esac

[[ $do_global -eq 1 ]] && pick_and_install "global" "category" "Global"

if [[ $do_project -eq 1 ]]; then
  echo
  read -rp "Path del proyecto donde instalar las skills (Enter = directorio actual): " PROJECT_PATH
  [[ -z "$PROJECT_PATH" ]] && PROJECT_PATH="$PWD"
  PROJECT_PATH="${PROJECT_PATH/#\~/$HOME}"
  if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Error: '$PROJECT_PATH' no es un directorio." >&2
    exit 1
  fi
  pick_and_install "project" "stack" "Project"
fi

if [[ ${#FAILED_SKILLS[@]} -gt 0 ]]; then
  echo
  echo "== ${#FAILED_SKILLS[@]} skill(s) fallaron =="
  for f in "${FAILED_SKILLS[@]}"; do
    echo "  ✗ $f"
  done
  echo "Revisa el nombre del skill en skills.list contra 'npx skills add <repo> --list'."
fi
