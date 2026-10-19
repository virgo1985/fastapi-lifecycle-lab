## Qué cambia

<!-- Una o dos frases. -->

## Tipo (gitflow)

- [ ] `feature/*` o `bugfix/*` → `develop` — **Squash and merge**, título en Conventional Commits (`feat: …`, `fix: …`)
- [ ] `release/X.Y.Z` o `hotfix/X.Y.Z` → `main` — **Create a merge commit**
- [ ] back-merge `main` → `develop` — **Create a merge commit**

## Comprobaciones

- [ ] Tests añadidos o actualizados
- [ ] Si rompe compatibilidad: `feat!:` o `BREAKING CHANGE:` en el título/cuerpo (sube la versión mayor)
