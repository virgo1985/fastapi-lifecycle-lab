# Guion de demo (≈ 30 min)

Escrito para la primera vuelta (repo recién creado: `develop` en `0.1.0-alpha.N`, prod vacío). En vueltas siguientes, sube las versiones.

Prerrequisitos: `scripts/bootstrap-github.sh` ejecutado, runner online, DNS creados, `gh` autenticado en el Mac, tres pestañas abiertas: Actions, `lab-dev…/docs`, `lab…/version`.

## 1. Feature → dev (5 min)

```bash
scripts/flow.sh feature start items-search
# editar app/main.py: GET /items?q=... filtra por nombre; añadir test
git commit -am "feat(items): búsqueda por nombre"
scripts/flow.sh feature finish "feat(items): búsqueda por nombre"
```

Enseñar en el PR: *Gitflow guard*, *Conventional PR title*, versión calculada (`0.1.0-items-search.1`), cobertura, SBOM como artefacto, hallazgos de Grype en *Security*. Intentar cambiar la base a `main` → el guard falla.

*Squash and merge* → run en `develop` → `0.1.0-alpha.N` firmada → **Deploy dev** en el runner de casa → `https://lab-dev.elpalmeral.es/version`.

## 2. Release → staging (5 min)

```bash
scripts/flow.sh release start 0.1.0
```

Push de la rama = `0.1.0-rc.N` en **staging**. Hacer un arreglo en la rama (`fix: …`) para ver `rc.N+1`.

## 3. Publicar → prod con aprobación (8 min)

```bash
scripts/flow.sh release finish     # PR release/0.1.0 → main, "Create a merge commit"
```

Al fusionar, en el run de `main`:

1. **Promoción**: el resumen muestra `tree-… → 0.1.0 (sin rebuild)`. Comparar digests en GHCR: el de `0.1.0` y el de `0.1.0-rc.N` son el mismo.
2. Tag `v0.1.0` + GitHub Release con notas agrupadas y SBOM adjunto.
3. **Deploy prod** espera aprobación → aprobar.
4. `/version` en prod: `version: 0.1.0`, `built_as: 0.1.0-rc.N`. Explicar *build once, promote*.
5. PR de back-merge `main → develop` abierto por el bot → fusionar con merge commit.

## 4. Hotfix (5 min)

```bash
scripts/flow.sh hotfix start 0.1.1
git commit -am "fix(items): ..." && git push     # staging = 0.1.1-rc.1
scripts/flow.sh hotfix finish
```

## 5. Rollback (3 min)

*Actions → Deploy → Run workflow* desde `main`: `prod`, `0.1.0`. El job verifica la firma, despliega por digest y pasa el smoke test. Intentar `0.2.0-alpha.1` en prod → la política lo rechaza.

Rollback automático: desplegar en dev una versión cuyo smoke test falle (p. ej. una feature que rompa `/items`) y ver cómo vuelve sola a la anterior.

## 6. Supply chain (4 min)

```bash
cosign verify ghcr.io/virgo1985/fastapi-lifecycle-lab:0.1.0 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/virgo1985/fastapi-lifecycle-lab/'
```

Cerrar con el caso `trivy-action` (marzo 2026) y por qué todas las actions van fijadas por SHA.

## Mensajes clave

| Fase del ciclo | Dónde se ve |
|---|---|
| Plan / código | Ramas gitflow, PR con plantilla, CODEOWNERS |
| Build | Una imagen por commit publicable, versión SemVer desde git |
| Test / calidad | ruff, mypy, pytest + cobertura, hadolint |
| Seguridad | CodeQL (SAST), Grype (SCA de imagen), reglas `S` de ruff |
| Release | Tag inmutable, notas automáticas, SBOM, firma y provenance |
| Deploy | Entornos con políticas por rama, aprobación en prod, verificación de firma |
| Operate | `/health`, `/ready`, `/metrics` (Prometheus), rollback automático y manual |
