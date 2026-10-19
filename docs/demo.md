# Guion de demo (≈ 30 min)

El guion vale para cualquier vuelta: las versiones las calculan los scripts y el pipeline. Los ejemplos suponen la primera vuelta tras un reset (prod vacío, siguiente release `0.1.0`).

Prerrequisitos: `scripts/bootstrap-github.sh` ejecutado, runner online, DNS creados, `gh` autenticado en el Mac. Tres pestañas abiertas: Actions, `lab-dev…/docs` y `lab…/hello`.

```bash
scripts/demo.sh status      # qué versión sirve cada entorno
scripts/flow.sh next        # próximas versiones de release y hotfix
```

## 1. Feature → dev (5 min)

```bash
scripts/demo.sh feature     # rama feature/demo-round-N + saludo nuevo en /hello + PR a develop
```

`demo.sh feature` hace un cambio real y repetible: añade a `app/greetings.py` el saludo de la vuelta N. Si prefieres programar en directo, usa `scripts/flow.sh feature start <nombre>` y `feature finish "feat(...): ..."`, pero con un nombre nuevo en cada vuelta.

En el PR enseña:

- *Gitflow guard* y *Conventional PR title*.
- La versión calculada (`0.1.0-demo-round-N.1`), la cobertura, el SBOM como artefacto y los hallazgos de Grype en *Security*.
- Cambia la base del PR a `main`: el guard falla.

*Squash and merge* → run en `develop` → `0.1.0-alpha.N` firmada → **Deploy dev** en el runner de casa → `https://lab-dev.elpalmeral.es/hello`.

## 2. Release → staging (5 min)

```bash
scripts/flow.sh release start      # sin versión: la calcula (0.1.0, 0.2.0... o 1.0.0 si hay feat!)
```

El push de la rama publica `X.Y.Z-rc.N` en **staging**. Haz un arreglo en la rama (`fix: …`) para ver `rc.N+1`.

## 3. Publicar → prod con aprobación (8 min)

```bash
scripts/flow.sh release finish     # PR release/X.Y.Z → main, "Create a merge commit"
```

Al fusionar, en el run de `main`:

1. **Promoción:** el resumen muestra `tree-… → X.Y.Z (sin rebuild)`. Compara los digests en GHCR: `X.Y.Z` y `X.Y.Z-rc.N` son el mismo.
2. Tag `vX.Y.Z` + GitHub Release con notas agrupadas y SBOM adjunto.
3. **Deploy prod** espera tu aprobación → apruébalo.
4. `/version` en prod devuelve `version: X.Y.Z` y `built_as: X.Y.Z-rc.N`. Explica *build once, promote*.
5. El bot abre el PR de back-merge `main → develop` → fusiónalo con merge commit.

## 4. Hotfix (5 min)

```bash
scripts/flow.sh hotfix start       # sin versión: patch del último tag (X.Y.Z+1)
# arreglo + commit "fix(...): ..." + git push      → staging = X.Y.(Z+1)-rc.1
scripts/flow.sh hotfix finish
```

## 5. Rollback (3 min)

*Actions → Deploy → Run workflow* desde `main`, con `prod` y la versión anterior. El job verifica la firma, despliega por digest y pasa el smoke test. Prueba también una `-alpha` en prod: la política la rechaza.

## 6. Supply chain (4 min)

```bash
cosign verify ghcr.io/virgo1985/fastapi-lifecycle-lab:X.Y.Z \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/virgo1985/fastapi-lifecycle-lab/'
```

Cierra con el caso `trivy-action` (marzo de 2026) y por qué todas las actions van fijadas por SHA.

## Repetir la demo

| Quiero… | Cómo |
|---|---|
| **Otra vuelta**, continuando la historia | Repite el guion. `demo.sh feature` crea la vuelta N+1 y las versiones siguen subiendo (0.2.0, 0.3.0…). Que el producto evolucione también es parte del mensaje |
| **Empezar de cero** (antes de una demo con cliente) | `scripts/demo.sh reset --delete-images --purge-history --teardown` |

### Reset completo

Una vez, después de dejar `develop` como quieres que empiece la demo:

```bash
scripts/demo.sh baseline           # tag demo-baseline = origin/develop
```

Cada vez que quieras volver a cero:

```bash
gh auth refresh -h github.com -s read:packages,delete:packages   # solo la 1.ª vez, para --delete-images
scripts/demo.sh reset --delete-images --purge-history --teardown
```

El reset hace esto:

1. Desactiva los rulesets. Los reactiva al final aunque algo falle.
2. Cierra los PR abiertos y borra todas las ramas salvo `main` y `develop`.
3. Borra las GitHub Releases y los tags `v*`.
4. Con las opciones: borra las imágenes de GHCR y el historial de runs y despliegues, y para `lab-*` en docker01 por SSH.
5. Fuerza `main` y `develop` a `demo-baseline` y limpia tu clon local.

Después, `develop` vuelve a desplegar `0.1.0-alpha.N` en dev y la siguiente release es `0.1.0`. `main` no publica nada: solo el merge de una `release/*` o `hotfix/*` llega a prod.

Si cambias el pipeline o la app y quieres que forme parte del punto de partida, fusiónalo en `develop` y vuelve a ejecutar `demo.sh baseline`.

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
