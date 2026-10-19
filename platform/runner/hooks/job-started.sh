#!/usr/bin/env bash
# Hook ACTIONS_RUNNER_HOOK_JOB_STARTED: se ejecuta en el runner ANTES de cualquier paso
# del job. Si sale con código distinto de 0, el job falla sin ejecutar nada.
#
# Por qué: el repo es público y este runner tiene el socket de Docker de docker01.
# GitHub desaconseja runners self-hosted en repos públicos porque un PR desde un fork
# puede cambiar un workflow para que use este runner. Este hook es la defensa en
# profundidad: solo acepta jobs de este repo, lanzados por eventos de confianza,
# sobre ramas de gitflow y por actores permitidos.
set -euo pipefail

EXPECTED_REPO="${EXPECTED_REPO:-virgo1985/fastapi-lifecycle-lab}"
ALLOWED_ACTORS="${ALLOWED_ACTORS:-virgo1985}"

deny() {
  echo "::error::Runner homelab: job RECHAZADO — $1"
  echo "repo=${GITHUB_REPOSITORY:-?} event=${GITHUB_EVENT_NAME:-?} ref=${GITHUB_REF:-?} actor=${GITHUB_ACTOR:-?} triggering=${GITHUB_TRIGGERING_ACTOR:-?} workflow=${GITHUB_WORKFLOW_REF:-?}"
  exit 1
}

[[ "${GITHUB_REPOSITORY:-}" == "$EXPECTED_REPO" ]] || deny "repositorio no permitido"

case "${GITHUB_EVENT_NAME:-}" in
  push|workflow_dispatch) ;;
  *) deny "evento '${GITHUB_EVENT_NAME:-}' no permitido (nunca pull_request*)" ;;
esac

[[ "${GITHUB_REF:-}" =~ ^refs/heads/(develop|main|release/[0-9.]+|hotfix/[0-9.]+)$ ]] \
  || deny "ref '${GITHUB_REF:-}' fuera de gitflow"

[[ "${GITHUB_WORKFLOW_REF:-}" =~ ^${EXPECTED_REPO}/\.github/workflows/(ci|deploy)\.yml@ ]] \
  || deny "workflow '${GITHUB_WORKFLOW_REF:-}' no autorizado"

allowed=false
for a in ${ALLOWED_ACTORS//,/ }; do
  [[ "${GITHUB_TRIGGERING_ACTOR:-${GITHUB_ACTOR:-}}" == "$a" ]] && allowed=true
done
[[ "$allowed" == true ]] || deny "actor '${GITHUB_TRIGGERING_ACTOR:-${GITHUB_ACTOR:-}}' no permitido"

echo "Runner homelab: job aceptado (${GITHUB_EVENT_NAME} ${GITHUB_REF} por ${GITHUB_TRIGGERING_ACTOR:-$GITHUB_ACTOR})"
