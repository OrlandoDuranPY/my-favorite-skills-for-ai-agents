# my-favorite-skills-for-ai-agents

Catalogo de skills que mas uso con agentes IA (Claude Code, OpenCode), organizadas por categoria, instalables globalmente en un comando via el CLI oficial [`npx skills`](https://github.com/vercel-labs/skills).

Este repo no aloja codigo de skill — solo cataloga de que repo/paquete viene cada una, para reinstalar todo en una maquina nueva con un solo script.

## Catalogo

Fuente de verdad: [`skills.list`](skills.list) (formato `categoria|repo|skill|scope`). Ver contenido actual:

```bash
./install.sh --list
```

Categorias: `frontend`, `backend`, `tools` (agrega mas segun necesites).

**Scope** — decide si una skill vale en cualquier repo o solo donde se usa ese stack:
- `global` — generica, sin dependencia de stack (ej. `find-skills`, guidelines generales). Se instala una vez para toda la maquina.
- `project` — atada a un framework/lenguaje (ej. `nuxt-ui`, `spatie-laravel-php`). Instalar global mete ruido/triggers falsos en repos que no usan ese stack — instalar solo dentro del repo que corresponde.

## Instalacion

Requiere `npx` (Node).

```bash
./install.sh                       # interactivo: elige global/project/ambos, luego skills individuales o "todas" por bloque
./install.sh --scope global        # no interactivo: TODAS las globales, sin preguntar
./install.sh --scope project       # no interactivo: TODAS las de project, sin preguntar
./install.sh --category frontend   # no interactivo: instala solo una categoria
./install.sh --dry-run             # muestra los comandos sin ejecutarlos (combinable con el modo interactivo)
./install.sh --copy                # copia archivos en vez de symlink
```

Modo interactivo (default, sin flags): pregunta global/project/ambos, y por cada bloque (categoria en global, stack en project) muestra las skills individuales + una opcion "todas de este bloque", ademas de "TODAS" general.

Seleccion con checkboxes (terminal real): flechas arriba/abajo mueven el cursor, **espacio** marca/desmarca, `a` marca/desmarca todo, Enter confirma, `q` cancela. Si no hay TTY disponible (input por pipe, script no interactivo), cae automaticamente a seleccion por numeros separados por coma.

Al elegir Project, el script **pide el path del proyecto** donde instalar (Enter = directorio actual). Las skills de scope=project se instalan en ese directorio (corre `npx skills add` con `cd` a ese path), no globalmente.

Cada entrada corre:

```bash
npx skills add <repo> --skill <skill> --agent claude-code,opencode --yes [--global]   # --global solo si scope=global
```

**Agentes destino:** en modo interactivo, el script arranca con un **picker de agentes** (checkboxes) con `claude-code` y `opencode` pre-marcados; marca/desmarca los que quieras. Sin modo interactivo, se usa `--agents a1,a2` (default `claude-code,opencode`) o editas `AGENTS` en `install.sh`. Instalar a agentes que no soportan global (ej. Eve, PromptScript) solo genera un aviso inofensivo — no es un error.

## Windows

El script es bash puro (arrays, `declare -A`, `[[ ]]`) — no corre con `sh`. cmd.exe y PowerShell nativos no sirven. Necesitas una shell bash:

- **Git Bash** (incluido en Git for Windows) — abrir terminal, `cd` al repo, correr con `bash install.sh`
- **WSL** — igual, `bash install.sh` dentro de la distro

`npx` debe estar en el PATH de esa shell (viene con Node).

Probar sin instalar nada de verdad:

```bash
bash install.sh --list                        # ver catalogo
bash install.sh --dry-run                     # interactivo, solo muestra comandos, no ejecuta
printf '1\n0\n' | bash install.sh --dry-run   # simula input sin tipear (bloque global, opcion "TODAS")
```

En Linux es lo mismo, solo que `./install.sh` ya funciona directo (tiene permiso de ejecucion).

## Agregar una skill al catalogo

Agrega una linea a `skills.list`:

```
categoria|https://github.com/owner/repo|nombre-del-skill|global-o-project
```

Corre `./install.sh --category <esa-categoria>` para instalarla.

## Instalacion manual (sin script)

```bash
npx skills add <repo> --skill <skill> --agent '*' --global --yes
```
