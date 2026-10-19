#!/usr/bin/env bash
# Utilidades para repetir la demo. Requiere git, gh (autenticado como admin del repo), jq y curl.
#
#   scripts/demo.sh feature        cambio de ejemplo repetible: añade el saludo de la vuelta N
#                                  a /hello, rama feature/demo-round-N y PR a develop
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
set -euo pipefail

REPO="${REPO:-virgo1985/fastapi-lifecycle-lab}"
BASELINE_TAG=demo-baseline
die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "▶ $*"; }
cd "$(git rev-parse --show-toplevel)"

clean_tree() { [[ -z "$(git status --porcelain)" ]] || die "hay cambios sin commitear"; }

cmd_feature() {
  clean_tree
  git fetch -q --prune origin
  local n branch title
  n=$(( $(git show origin/develop:app/greetings.py | grep -c '^    "') + 1 ))
  branch="feature/demo-round-$n"
  title="feat(hello): saludo de la vuelta $n de la demo"
  git ls-remote -q --exit-code --heads origin "$branch" > /dev/null && die "$branch ya existe en GitHub (¿PR sin fusionar?)"
  git branch -D "$branch" 2> /dev/null || true
  git switch -q -c "$branch" origin/develop
  python3 - "$n" <<'EOF'
import datetime, pathlib, sys
p = pathlib.Path("app/greetings.py")
s = p.read_text()
line = f'    "Vuelta {sys.argv[1]} de la demo ({datetime.date.today().isoformat()})",\n'
p.write_text(s.replace("]\n", line + "]\n", 1))
EOF
  git commit -q -am "$title"
  git push -q -u origin "$branch"
  gh pr create -R "$REPO" --base develop --head "$branch" --title "$title" \
    --body "Cambio de ejemplo de la demo: \`/hello\` devuelve el saludo de la vuelta $n. Fusionar con **Squash and merge**."
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
  while read -r id; do [[ -n "$id" ]] && RULESETS+=("$id"); done \
    < <(gh api "repos/$REPO/rulesets" -q '.[] | select(.enforcement=="active") | .id')
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
  status) cmd_status ;;
  baseline) cmd_baseline ;;
  reset) shift; cmd_reset "$@" ;;
  *) sed -n '2,16p' "$0"; exit 1 ;;
esac
