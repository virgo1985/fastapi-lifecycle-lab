#!/usr/bin/env bash
# Configura el repo en GitHub para gitflow (idempotente: se puede relanzar).
# Requiere: gh autenticado como el propietario del repo (gh auth login).
#
#   scripts/bootstrap-github.sh [owner/repo]
set -euo pipefail

REPO="${1:-virgo1985/fastapi-lifecycle-lab}"
R="repos/$REPO"
OWNER_ID=$(gh api "users/${REPO%%/*}" -q .id)
echo "→ $REPO (owner id $OWNER_ID)"

echo "→ Opciones de merge: squash + merge commit, sin rebase; rama por defecto develop"
gh api -X PATCH "$R" --silent \
  -F allow_squash_merge=true -F allow_merge_commit=true -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY \
  -f default_branch=develop

echo "→ Actions: token de solo lectura por defecto; Actions puede abrir PR (back-merge)"
gh api -X PUT "$R/actions/permissions/workflow" --silent \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true

echo "→ PR de forks externos: requieren aprobación antes de ejecutar workflows"
gh api -X PUT "$R/actions/permissions/fork-pr-contributor-approval" --silent \
  -f approval_policy=all_external_contributors

echo "→ Entornos"
env_put() { gh api -X PUT "$R/environments/$1" --silent --input -; }
env_put dev <<<'{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
env_put staging <<<'{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
env_put prod <<EOF
{"reviewers":[{"type":"User","id":$OWNER_ID}],"prevent_self_review":false,
 "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}
EOF

policy() {
  local env=$1 pattern=$2
  if ! gh api "$R/environments/$env/deployment-branch-policies" -q '.branch_policies[].name' | grep -qxF "$pattern"; then
    gh api -X POST "$R/environments/$env/deployment-branch-policies" --silent -f name="$pattern" -f type=branch
  fi
}
policy dev develop;          policy dev main
policy staging 'release/*';  policy staging 'hotfix/*';  policy staging main
policy prod main

echo "→ Rulesets"
upsert_ruleset() {
  local name=$1 body
  body=$(cat)
  local id
  id=$(gh api "$R/rulesets" -q ".[] | select(.name==\"$name\") | .id")
  if [[ -n "$id" ]]; then
    gh api -X PUT "$R/rulesets/$id" --silent --input - <<<"$body"
  else
    gh api -X POST "$R/rulesets" --silent --input - <<<"$body"
  fi
  echo "   $name ✔"
}

checks='[{"context":"Lint"},{"context":"Unit tests"},{"context":"Build image"}]'

upsert_ruleset main <<EOF
{"name":"main","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},
 "bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}],
 "rules":[
  {"type":"deletion"},{"type":"non_fast_forward"},
  {"type":"pull_request","parameters":{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":true,
    "require_code_owner_review":false,"require_last_push_approval":false,"required_review_thread_resolution":true,
    "allowed_merge_methods":["merge"]}},
  {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,
    "required_status_checks":$checks}}
 ]}
EOF

upsert_ruleset develop <<EOF
{"name":"develop","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/heads/develop"],"exclude":[]}},
 "bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}],
 "rules":[
  {"type":"deletion"},{"type":"non_fast_forward"},
  {"type":"pull_request","parameters":{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":true,
    "require_code_owner_review":false,"require_last_push_approval":false,"required_review_thread_resolution":true,
    "allowed_merge_methods":["squash","merge"]}},
  {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,
    "required_status_checks":$checks}}
 ]}
EOF

# Solo GitHub Actions (integración 15368) crea tags de versión; nadie los mueve ni borra.
upsert_ruleset release-tags <<'EOF' || echo "   ⚠️ ruleset de tags no aplicado (revisa el bypass de GitHub Actions a mano)"
{"name":"release-tags","target":"tag","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/tags/v*"],"exclude":[]}},
 "bypass_actors":[{"actor_id":15368,"actor_type":"Integration","bypass_mode":"always"}],
 "rules":[{"type":"creation"},{"type":"update"},{"type":"deletion"}]}
EOF

echo "✅ Listo. Siguiente: DNS + stack del runner en Portainer (docs/setup.md)."
