# Puesta en marcha

## 1. Configuración de GitHub

Ejecuta una vez desde tu Mac (idempotente):

```bash
scripts/bootstrap-github.sh
```

Deja el repo así:

| Ajuste | Valor |
|---|---|
| Rama por defecto | `develop` (los PR apuntan ahí por defecto) |
| Ruleset `main` | Solo vía PR, solo *merge commit*, checks `Lint`, `Unit tests`, `Build image`; sin borrado ni force-push |
| Ruleset `develop` | Solo vía PR, *squash* o *merge commit*, mismos checks; sin borrado ni force-push |
| Ruleset tags `v*` | Solo GitHub Actions crea tags de versión; nadie los borra ni los mueve |
| Bypass | Rol *admin* del repo, solo en PR (para fusionar el back-merge, que abre el bot y no relanza checks) |
| Entornos | `dev` ← `develop`, `main` · `staging` ← `release/*`, `hotfix/*`, `main` · `prod` ← `main`, **aprobación de @virgo1985** |
| Actions | Permisos del token por defecto de solo lectura; Actions puede abrir PR (back-merge); los PR de forks externos requieren aprobación |
| Merge | Squash y merge commit permitidos, rebase no; borrar rama al fusionar |

`main` se permite en `dev` y `staging` para poder lanzar el rollback manual (`Deploy`) desde `main`.

## En el homelab

### 2. DNS

En Technitium, tres registros A hacia docker01 (o un comodín `*.elpalmeral.es` si ya lo tienes):

```
lab.elpalmeral.es          A  <IP de docker01>
lab-dev.elpalmeral.es      A  <IP de docker01>
lab-staging.elpalmeral.es  A  <IP de docker01>
```

El certificado ya lo cubre el comodín `*.elpalmeral.es` de Traefik.

### 3. Token para el runner

GitHub → Settings → Developer settings → **Fine-grained tokens** → Generate:

- Resource owner: `virgo1985`; Repository access: **Only select repositories** → `fastapi-lifecycle-lab`
- Permissions → Repository → **Administration: Read and write** (lo necesita para registrar runners). Nada más.
- Caducidad: 90 días (apúntalo en 1Password).

### 4. Stack del runner en Portainer

*Stacks → Add stack → Repository*

| Campo | Valor |
|---|---|
| Name | `lifecycle-lab-runner` |
| Repository URL | `https://github.com/virgo1985/fastapi-lifecycle-lab` |
| Reference | `refs/heads/main` |
| Compose path | `platform/runner/compose.yaml` |
| Enable relative path volumes | ✔ activado (monta `hooks/`) |
| Local filesystem path | **ruta absoluta** de docker01, la misma que traefik: `/mnt/fastpool-docker` |
| Environment variables | `GH_RUNNER_PAT` = el token del paso 3 |

> Portainer clona el repo en `<Local filesystem path>/portainer-compose-unpacker/stacks/<stack>/…` y monta `hooks/` desde ahí. Con una ruta relativa (p. ej. `hooks`) falla con *"mount path must be absolute"*.

Al arrancar debe aparecer en *Settings → Actions → Runners* como `docker01-…` con la etiqueta `homelab-deploy`. Es efímero: tras cada job el contenedor se reinicia y se vuelve a registrar.

### 5. Primer despliegue

Los jobs `Deploy dev` que hayan quedado en cola se ejecutan solos cuando el runner aparece. Si caducaron (24 h), haz *Re-run failed jobs* en el último run de `develop`.

`main` no tiene nada en prod hasta la primera release: el commit inicial no es un merge y el pipeline no lo publica (regla de gitflow). Prod se estrena con la primera `release/0.1.0` del [guion de demo](demo.md).

## Comprobaciones

```bash
curl -s https://lab-dev.elpalmeral.es/version | jq
sudo docker ps --filter name=lab- --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

## Riesgos aceptados y siguiente paso

- **El runner tiene el socket de Docker de docker01** → quien ejecute un job en él controla Docker (≈ root). Mitigaciones activas: hook que rechaza PR, forks, otros repos, otras ramas y otros actores; runner efímero; aprobación para PR de forks; prod tras aprobación. **Mejora recomendada:** moverlo a una VM `docker02` dedicada (ya tienes el plan de Terraform empezado).
- Los registros en memoria de la API se pierden en cada despliegue: es intencionado.
