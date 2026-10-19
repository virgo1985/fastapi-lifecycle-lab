#!/usr/bin/env bash
# Atajos de gitflow sobre GitHub (sin git-flow AVH). Requiere git y gh autenticado.
#
#   scripts/flow.sh feature start <nombre>      rama feature/<nombre> desde develop
#   scripts/flow.sh feature finish "<título>"   PR -> develop (squash; título Conventional Commit)
#   scripts/flow.sh release start <X.Y.Z>       rama release/X.Y.Z desde develop -> staging
#   scripts/flow.sh release finish              PR release/X.Y.Z -> main (merge commit)
#   scripts/flow.sh hotfix start <X.Y.Z>        rama hotfix/X.Y.Z desde main -> staging
#   scripts/flow.sh hotfix finish               PR hotfix/X.Y.Z -> main (merge commit)
#   scripts/flow.sh version                     versión que calcularía GitVersion (necesita docker)
#
# El back-merge main -> develop lo abre el pipeline al publicar.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
current() { git rev-parse --abbrev-ref HEAD; }

sync_from() {
  git fetch origin "$1"
  git switch -c "$2" "origin/$1"
  git push -u origin "$2"
}

case "${1:-} ${2:-}" in
  "feature start")
    [[ -n "${3:-}" ]] || die "falta el nombre"
    sync_from develop "feature/$3" ;;
  "feature finish")
    [[ "$(current)" == feature/* ]] || die "no estás en una feature/*"
    [[ -n "${3:-}" ]] || die 'falta el título, p. ej. "feat(items): filtro por nombre"'
    git push
    gh pr create --base develop --title "$3" --fill-verbose
    echo "Fusiona con 'Squash and merge' (el título del PR será el commit en develop)." ;;
  "release start")
    [[ "${3:-}" =~ $semver_re ]] || die "versión X.Y.Z requerida"
    sync_from develop "release/$3"
    echo "release/$3 creada: el pipeline publicará $3-rc.N y desplegará en staging." ;;
  "hotfix start")
    [[ "${3:-}" =~ $semver_re ]] || die "versión X.Y.Z requerida"
    sync_from main "hotfix/$3"
    echo "hotfix/$3 creada desde main: commitea el arreglo (fix: ...) y haz push." ;;
  "release finish"|"hotfix finish")
    b="$(current)"
    [[ "$b" =~ ^(release|hotfix)/([0-9]+\.[0-9]+\.[0-9]+)$ ]] || die "no estás en release/X.Y.Z ni hotfix/X.Y.Z"
    git push
    gh pr create --base main --title "chore(release): ${BASH_REMATCH[2]}" \
      --body "Gitflow: publica \`${BASH_REMATCH[2]}\`. Fusionar con **Create a merge commit**. Al fusionar: tag v${BASH_REMATCH[2]}, GitHub Release, aprobación y despliegue en prod, PR de back-merge a develop."
    ;;
  "version "*)
    docker run --rm -v "$(git rev-parse --show-toplevel):/repo" gittools/gitversion:6.8.2 /repo /showvariable SemVer ;;
  *)
    sed -n '2,13p' "$0"; exit 1 ;;
esac
