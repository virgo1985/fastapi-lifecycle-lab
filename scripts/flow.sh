#!/usr/bin/env bash
# Atajos de gitflow sobre GitHub (sin git-flow AVH). Requiere git y gh autenticado.
#
#   scripts/flow.sh feature start <nombre>      rama feature/<nombre> desde develop
#   scripts/flow.sh feature finish "<título>"   PR -> develop (squash; título Conventional Commit)
#   scripts/flow.sh release start [X.Y.Z]       rama release/X.Y.Z desde develop -> staging
#   scripts/flow.sh release finish              PR release/X.Y.Z -> main (merge commit)
#   scripts/flow.sh hotfix start [X.Y.Z]        rama hotfix/X.Y.Z desde main -> staging
#   scripts/flow.sh hotfix finish               PR hotfix/X.Y.Z -> main (merge commit)
#   scripts/flow.sh next                        próximas versiones de release y hotfix
#
# Sin X.Y.Z, release sube la minor del último tag (o la major si develop trae un
# breaking change) y hotfix sube la patch. El back-merge main -> develop lo abre el pipeline.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
current() { git rev-parse --abbrev-ref HEAD; }

refresh() { git fetch -q --prune --prune-tags origin; }

latest_tag() {
  git tag -l 'v[0-9]*.[0-9]*.[0-9]*' --merged origin/main | sed 's/^v//' | sort -V | tail -1
}

next_release() {
  local t; t=$(latest_tag)
  [[ -z "$t" ]] && { echo "0.1.0"; return; }
  IFS=. read -r M m _ <<<"$t"
  if git log "v$t..origin/develop" --format='%s%n%b' | grep -qE '^[a-z]+(\([^)]*\))?!:|BREAKING CHANGE:'; then
    echo "$((M + 1)).0.0"
  else
    echo "$M.$((m + 1)).0"
  fi
}

next_hotfix() {
  local t; t=$(latest_tag)
  [[ -n "$t" ]] || die "no hay ninguna versión publicada en main: no hay nada que parchear"
  IFS=. read -r M m p <<<"$t"
  echo "$M.$m.$((p + 1))"
}

start_branch() { # <origen> <rama>
  if git show-ref -q --verify "refs/heads/$2"; then
    die "la rama local '$2' ya existe (¿de una vuelta anterior?). Bórrala con: git branch -D $2"
  fi
  if git ls-remote -q --exit-code --heads origin "$2" > /dev/null; then
    die "la rama '$2' ya existe en GitHub"
  fi
  git switch -q -c "$2" "origin/$1"
  git push -q -u origin "$2"
  echo "✔ $2 creada desde $1"
}

case "${1:-} ${2:-}" in
  "feature start")
    [[ -n "${3:-}" ]] || die "falta el nombre"
    refresh; start_branch develop "feature/$3" ;;
  "feature finish")
    [[ "$(current)" == feature/* ]] || die "no estás en una feature/*"
    [[ -n "${3:-}" ]] || die 'falta el título, p. ej. "feat(items): filtro por nombre"'
    git push -q
    gh pr create --base develop --title "$3" --fill-verbose
    echo "Fusiona con 'Squash and merge' (el título del PR será el commit en develop)." ;;
  "release start")
    refresh; v="${3:-$(next_release)}"
    [[ "$v" =~ $semver_re ]] || die "versión X.Y.Z requerida"
    start_branch develop "release/$v"
    echo "El pipeline publicará $v-rc.N y desplegará en staging." ;;
  "hotfix start")
    refresh; v="${3:-$(next_hotfix)}"
    [[ "$v" =~ $semver_re ]] || die "versión X.Y.Z requerida"
    start_branch main "hotfix/$v"
    echo "Commitea el arreglo (fix: ...) y haz push: staging recibirá $v-rc.N." ;;
  "release finish"|"hotfix finish")
    b="$(current)"
    [[ "$b" =~ ^(release|hotfix)/([0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "no estás en release/X.Y.Z ni hotfix/X.Y.Z"
    git push -q
    gh pr create --base main --title "chore(release): ${BASH_REMATCH[2]}" \
      --body "Gitflow: publica \`${BASH_REMATCH[2]}\`. Fusionar con **Create a merge commit**. Al fusionar: tag v${BASH_REMATCH[2]}, GitHub Release, aprobación y despliegue en prod, PR de back-merge a develop."
    ;;
  "next "*)
    refresh
    echo "último tag:   $(latest_tag)"
    echo "release:      $(next_release)"
    echo "hotfix:       $( (next_hotfix) 2>/dev/null || echo -)" ;;
  *)
    sed -n '2,13p' "$0"; exit 1 ;;
esac
