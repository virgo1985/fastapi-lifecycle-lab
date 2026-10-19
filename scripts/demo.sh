#!/usr/bin/env bash
# Utilidades para repetir la demo. Requiere git, gh (autenticado como admin del repo), jq y curl.
#
#   scripts/demo.sh feature        rama feature/<cambio> desde develop y escribe el código y los
#                                  tests del siguiente cambio del catálogo SIN commitear
#                                  (para enseñarlo en el IDE). Catálogo: scripts/demo_changes.py
#   scripts/demo.sh hotfix         igual, desde main en hotfix/X.Y.Z+1, con un arreglo del catálogo
#   scripts/demo.sh pr ["título"]  checks locales (ruff, mypy, pytest), commit, push y PR a develop
#                                  (en hotfix: solo push -> staging; luego flow.sh hotfix finish)
#   scripts/demo.sh abort          descarta el cambio sin subir y borra la rama local
#   scripts/demo.sh status         qué versión sirve cada entorno
#   scripts/demo.sh baseline       marca origin/develop como estado "limpio" (tag demo-baseline)
#   scripts/demo.sh reset [opciones]
#                                  vuelve el repo a demo-baseline: cierra PR, borra ramas,
#                                  releases y tags v*, y fuerza main y develop a la línea base.
#                                  La siguiente release vuelve a ser 0.1.0.
#       --delete-images   borra el paquete de GHCR (necesita: gh auth refresh -s delete:packages)
#       --purge-history   borra runs de Actions y el historial de despliegues
#       --teardown        para los contenedores lab-* en docker01 (ssh ${LAB_SSH:-pfj@docker01})
#       --yes             no pide confirmación
# Si se lanza con "sh script" (bash en modo POSIX en macOS), relanzar con bash.
if [ -z "${BASH_VERSION:-}" ] || (set -o | grep -q '^posix[[:space:]]*on'); then exec bash "$0" "$@"; fi
set -euo pipefail

REPO="${REPO:-virgo1985/fastapi-lifecycle-lab}"
BASELINE_TAG=demo-baseline
die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "▶ $*"; }
cd "$(git rev-parse --show-toplevel)"

clean_tree() { [[ -z "$(git status --porcelain)" ]] || die "hay cambios sin commitear"; }

prepare_change() { # <feature|hotfix> <rama base> <prefijo de rama, con versión si aplica>
  local kind=$1 base=$2 prefix=$3 plan slug title branch
  plan=$(python3 scripts/demo_changes.py plan "$kind" "origin/$base") || exit 1
  slug=${plan%%$'\t'*}
  title=${plan#*$'\t'}
  if [[ "$kind" == feature ]]; then branch="feature/$slug"; else branch="$prefix"; fi
  git ls-remote -q --exit-code --heads origin "$branch" > /dev/null \
    && die "$branch ya existe en GitHub (¿PR sin fusionar de una vuelta anterior?)"
  git branch -q -D "$branch" 2> /dev/null || true
  git switch -q -c "$branch" "origin/$base"
  python3 scripts/demo_changes.py apply "$slug"
  git add -N .                                   # los ficheros nuevos también salen en el diff
  git config "branch.$branch.demotitle" "$title" # lo usa "demo.sh pr"

  step "$branch — $title"
  git -c color.ui=always diff --stat
  echo
  echo "  Enséñalo en el IDE (pestaña Source Control) o con: git diff"
  echo "  Siguiente paso: scripts/demo.sh pr"
  if [[ -z "${DEMO_NO_IDE:-}" ]] && command -v "${DEMO_IDE:-code}" > /dev/null; then
    # shellcheck disable=SC2046
    "${DEMO_IDE:-code}" . $(git diff --name-only)
  fi
}

cmd_feature() {
  clean_tree
  git fetch -q --prune origin
  prepare_change feature develop ""
}

cmd_hotfix() {
  clean_tree
  local v
  v=$(scripts/flow.sh next | awk '/^hotfix:/ {print $2}')
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "no hay ninguna versión en prod que parchear (haz antes una release)"
  prepare_change hotfix main "hotfix/$v"
}

cmd_pr() {
  local branch title
  branch=$(git rev-parse --abbrev-ref HEAD)
  [[ "$branch" == feature/* || "$branch" == hotfix/* ]] || die "no estás en una feature/* ni hotfix/*"
  [[ -n "$(git status --porcelain)" ]] || die "no hay cambios que commitear"
  title=${1:-$(git config --get "branch.$branch.demotitle" || true)}
  [[ -n "$title" ]] || die 'falta el título (Conventional Commit): scripts/demo.sh pr "feat(x): ..."'

  if command -v uv > /dev/null; then
    step "Shift-left: las mismas comprobaciones que hará CI, ahora en local"
    if ! (uv run ruff check . && uv run ruff format --check . && uv run mypy && uv run pytest -q); then
      die "las comprobaciones locales fallan: corrígelo antes de subirlo"
    fi
  else
    echo "(uv no está instalado: se salta la comprobación local; CI lo hará igualmente)"
  fi

  step "Commit y push"
  git add -A
  git commit -q -m "$title"
  git push -q -u origin "$branch"
  git log -1 --format='  %h %s'

  if [[ "$branch" == feature/* ]]; then
    step "PR a develop"
    gh pr create -R "$REPO" --base develop --head "$branch" --title "$title" \
      --body "Cambio de la demo (\`scripts/demo_changes.py\`). Fusionar con **Squash and merge**: el título del PR será el commit en \`develop\`."
  else
    step "Hotfix subido: CI publica ${branch#hotfix/}-rc.N y lo despliega en staging"
    echo "  Cuando lo valides en staging: scripts/flow.sh hotfix finish"
  fi
}

cmd_abort() {
  local branch
  branch=$(git rev-parse --abbrev-ref HEAD)
  [[ "$branch" == feature/* || "$branch" == hotfix/* ]] || die "no estás en una feature/* ni hotfix/*"
  git reset -q --hard
  git clean -q -fd -- app tests
  git switch -q develop
  git branch -q -D "$branch"
  echo "✔ $branch descartada (si ya la habías subido, borra también la remota: git push origin --delete $branch)"
}

cmd_status() {
  for env in dev staging prod; do
    local host; host=$([[ $env == prod ]] && echo lab.elpalmeral.es || echo "lab-$env.elpalmeral.es")
    printf '%-8s ' "$env"
    curl -fsS -m 5 "https://$host/version" 2> /dev/null \
      | jq -r '"\(.version)\t(built_as \(.build.built_as), \(.build.git_ref))"' \
      || echo "— sin respuesta"
  done
}

cmd_baseline() {
  git fetch -q origin develop
  local sha; sha=$(git rev-parse origin/develop)
  echo "Línea base = origin/develop $(git log -1 --format='%h %s' "$sha")"
  read -r -p "¿Marcar como $BASELINE_TAG? [s/N] " a; [[ "$a" == [sS] ]] || exit 1
  git tag -f -a "$BASELINE_TAG" -m "Estado limpio para resetear la demo" "$sha"
  git push -q -f origin "refs/tags/$BASELINE_TAG"
  echo "✔ $BASELINE_TAG → ${sha:0:7}"
}

# --- reset -------------------------------------------------------------------
RULESETS=()
restore_rulesets() {
  for id in ${RULESETS[@]+"${RULESETS[@]}"}; do
    gh api -X PUT "repos/$REPO/rulesets/$id" -f enforcement=active --silent \
      && echo "  ruleset $id reactivado" || echo "  ⚠️ NO se pudo reactivar el ruleset $id: hazlo a mano"
  done
}

cmd_reset() {
  local delete_images=false purge=false teardown=false yes=false
  for a in "$@"; do
    case "$a" in
      --delete-images) delete_images=true ;;
      --purge-history) purge=true ;;
      --teardown) teardown=true ;;
      --yes) yes=true ;;
      *) die "opción desconocida: $a" ;;
    esac
  done
  clean_tree
  git fetch -q --prune --prune-tags --force origin
  git rev-parse -q --verify "refs/tags/$BASELINE_TAG" > /dev/null \
    || die "no existe $BASELINE_TAG; márcala antes con: scripts/demo.sh baseline"
  local base; base=$(git rev-parse "$BASELINE_TAG^{commit}")
  if $delete_images && ! gh auth status 2>&1 | grep -q 'delete:packages'; then
    die "para --delete-images ejecuta antes: gh auth refresh -h github.com -s read:packages,delete:packages"
  fi

  cat <<EOF
Esto RESETEA $REPO:
  - cierra todos los PR abiertos y borra todas las ramas salvo main y develop
  - borra todas las GitHub Releases y los tags v*
  - fuerza main y develop a $BASELINE_TAG ($(git log -1 --format='%h %s' "$base"))
  $($delete_images && echo "- borra el paquete ghcr.io/$REPO (todas las imágenes)")
  $($purge && echo "- borra los runs de Actions y el historial de despliegues")
  $($teardown && echo "- para lab-dev, lab-staging y lab-prod en ${LAB_SSH:-pfj@docker01}")
EOF
  if ! $yes; then
    read -r -p "Escribe el nombre del repo para confirmar: " a
    [[ "$a" == "${REPO#*/}" ]] || die "cancelado"
  fi

  step "Desactivando rulesets (se reactivan al salir, pase lo que pase)"
  local active_ids
  active_ids=$(gh api "repos/$REPO/rulesets" -q '.[] | select(.enforcement=="active") | .id')
  for id in $active_ids; do RULESETS+=("$id"); done
  trap restore_rulesets EXIT
  for id in ${RULESETS[@]+"${RULESETS[@]}"}; do gh api -X PUT "repos/$REPO/rulesets/$id" -f enforcement=disabled --silent; done

  step "Cerrando PR abiertos"
  gh pr list -R "$REPO" --state open --json number -q '.[].number' \
    | while read -r n; do gh pr close -R "$REPO" "$n" --comment "Reset de la demo" > /dev/null && echo "  #$n"; done

  step "Borrando ramas remotas (salvo main y develop)"
  git ls-remote --heads origin | awk '{print $2}' | sed 's#^refs/heads/##' | grep -vxE 'main|develop' \
    | while read -r b; do git push -q origin --delete "$b" && echo "  $b"; done

  step "Borrando releases y tags v*"
  gh release list -R "$REPO" --limit 500 --json tagName -q '.[].tagName' \
    | while read -r t; do gh release delete -R "$REPO" "$t" --yes --cleanup-tag && echo "  release $t"; done
  git ls-remote --tags --refs origin 'v*' | awk '{print $2}' \
    | while read -r t; do git push -q origin --delete "$t" && echo "  ${t#refs/tags/}"; done

  if $delete_images; then
    step "Borrando paquete GHCR"
    gh api -X DELETE "/user/packages/container/${REPO#*/}" --silent && echo "  ghcr.io/$REPO borrado" \
      || echo "  (no existía)"
  fi

  if $purge; then
    step "Borrando historial de Actions y despliegues"
    gh run list -R "$REPO" --limit 1000 --json databaseId -q '.[].databaseId' \
      | while read -r id; do gh run delete -R "$REPO" "$id" > /dev/null 2>&1 || true; done
    gh api --paginate "repos/$REPO/deployments" -q '.[].id' | while read -r id; do
      gh api -X POST "repos/$REPO/deployments/$id/statuses" -f state=inactive --silent || true
      gh api -X DELETE "repos/$REPO/deployments/$id" --silent || true
    done
    echo "  hecho"
  fi

  if $teardown; then
    step "Parando contenedores del lab en docker01"
    ssh "${LAB_SSH:-pfj@docker01}" 'sudo docker rm -f lab-dev-api lab-staging-api lab-prod-api' || true
  fi

  step "Forzando main y develop a la línea base"
  git push -q --force origin "$base:refs/heads/main" "$base:refs/heads/develop"
  echo "  main = develop = ${base:0:7}"

  step "Reactivando rulesets"
  restore_rulesets; trap - EXIT

  step "Limpiando el clon local"
  git switch -q --detach
  git for-each-ref --format='%(refname:short)' refs/heads \
    | grep -E '^(feature|bugfix|release|hotfix)/' | while read -r b; do git branch -q -D "$b"; done
  git branch -q -f main origin/main
  git branch -q -f develop origin/develop
  git switch -q develop

  cat <<EOF

✅ Demo reseteada. El push a develop despliega en dev la 0.1.0-alpha.N.
   Siguiente vuelta: scripts/demo.sh feature   ·   scripts/flow.sh release start  (→ 0.1.0)
EOF
}

case "${1:-}" in
  feature) cmd_feature ;;
  hotfix) cmd_hotfix ;;
  pr) shift; cmd_pr "$@" ;;
  abort) cmd_abort ;;
  status) cmd_status ;;
  baseline) cmd_baseline ;;
  reset) shift; cmd_reset "$@" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
