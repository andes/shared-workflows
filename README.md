# shared-workflows

Workflows reutilizables de GitHub Actions para los repositorios de Andes. Cada repo los llama con `workflow_call` en lugar de copiar el YAML.

## Conflictos de merge

`.github/workflows/label-merge-conflicts.yml` pone un label cuando un pull request tiene conflictos de merge y lo saca cuando ya no los tiene. El nombre del label es un input; el default es `Conflictos`.

Ese label tiene que existir de antemano en el repositorio que llama. El token del workflow tiene `contents: read` y `pull-requests: write`: alcanza para poner y sacar labels en un pull request, y no para crear el label.

### Cómo llamarlo

El caller tiene que usar `pull_request_target` con los tipos `opened`, `synchronize` y `reopened`. Además, para re-chequear los PRs abiertos cuando avanza la rama base, tiene que agregar `push` a esa rama.

Un evento `pull_request` que viene de un fork corre con un `GITHUB_TOKEN` de solo lectura, y ese token no puede etiquetar. `pull_request_target` corre en el contexto del repositorio base y el token sí puede escribir labels ahí.

Ese mismo token tiene escritura sobre el repo base. Este workflow solo consulta la API: no hace checkout del head del pull request y no ejecuta código del fork. El caller tiene que mantener esa misma restricción.

GitHub calcula `mergeable_state` en segundo plano. En el payload del webhook el valor suele llegar `unknown` o `null`, así que el workflow vuelve a pedir el pull request y reintenta hasta tener un estado definitivo. `dirty` significa que hay conflictos.

En el evento `push`, el workflow lista los PRs abiertos cuya base es la rama pusheada y actualiza el label de cada uno. Sin este trigger, un PR puede quedar con el label viejo cuando la rama base avanza y el PR no recibe un `synchronize`.

```yaml
name: Label merge conflicts

on:
  pull_request_target:
    types: [opened, synchronize, reopened]
  push:
    branches: [master] # la rama base del repositorio

permissions:
  contents: read
  pull-requests: write

jobs:
  conflicts:
    uses: andes/shared-workflows/.github/workflows/label-merge-conflicts.yml@v1
    with:
      label: Conflictos
```

`with.label` es opcional.

## Labeler

`.github/workflows/labeler.yml` aplica labels según los archivos que toca el pull request. Usa `actions/labeler` v7.0.0 pinneado (`bf12e9b00b37c5c0ca2b87b79b2daf7891dbda13`) en `ubuntu-26.04`. La config de globs no vive acá: cada repo mantiene su `.github/labeler.yml` en el formato de v7.

```yaml
name: Pull Request Labeler

on:
  pull_request:

permissions:
  contents: read
  pull-requests: write

jobs:
  triage:
    uses: andes/shared-workflows/.github/workflows/labeler.yml@v1
```

En api el archivo de globs queda así:

```yaml
script:
  - changed-files:
      - any-glob-to-any-file: scripts/*
config:
  - changed-files:
      - any-glob-to-any-file: config.private.ts.example
```

`configuration-path`, `sync-labels` y `dot` son inputs. Los defaults son `.github/labeler.yml`, `false` y `true`.

## Node CI

`.github/workflows/node-ci.yml` hace checkout, instala Node y corre los comandos del caller. No incluye el `cp` de la config ni el límite de memoria de `tsc`: eso es de api y entra en `commands`. El runner default es `ubuntu-26.04`. api pasa `ubuntu-22.04` para conservar el build actual. Node default es `22.x` y el install default es `npm ci`. `cache` default es vacío y no pide caché explícita. Acepta `npm`, `yarn` o `pnpm`. app pasa `npm` para cachear el lockfile.

```yaml
name: Build and test

on: [push]

permissions:
  contents: read

jobs:
  build:
    uses: andes/shared-workflows/.github/workflows/node-ci.yml@v1
    with:
      runner: ubuntu-22.04
      node-version: 22.x
      commands: |
        cp config.private.ts.example config.private.ts
        npm run lint
        NODE_OPTIONS=--max-old-space-size=4096 npm run tsc
        npm run test
```

Los comandos llegan por variable de entorno y se ejecutan con `bash -euo pipefail`.

El ref es el tag flotante `v1`. Cada release 1.x lo mueve al commit publicado, así que los callers siguen en la versión 1 sin cambiar el YAML. El tag aparece con el primer release estable 1.x.

Si este repositorio es privado, en Settings → Actions → General → Access hay que permitir que lo usen los demás repositorios de la organización.

## Semantic release

`.github/workflows/semantic-release.yml` publica en GitHub a partir de commits convencionales (`feat`, `fix`, y `BREAKING CHANGE` para un major). En este repo, `.releaserc.json` también publica un patch por los bumps de Dependabot (`build(deps)` y `chore(deps)`), así el tag `v1` se mueve y los callers reciben el pin nuevo. El default no publica en npm. Corre en `ubuntu-26.04`, con Node 22, y el token tiene `contents: write`, `issues: write` y `pull-requests: write`.

`floating_tag` default es `false`: no mueve tags. En `true`, después de un release estable mueve `v<major>` a ese commit. Un prerelease no lo mueve. Este repo lo prende en su caller para que `v1` siga la línea 1.x. Un 2.0.0 mueve `v2` y deja `v1` quieto.

`.github/workflows/release.yml` lo dispara en cada push a `main`, llamando al archivo de este mismo commit. La llamada de este repo a `andes/shared-workflows/.github/workflows/semantic-release.yml@v1` queda pendiente: el tag todavía no existe.

`branches` default es `['main']` y pisa el `branches` de la config del repo. `skip_npm` default es `true`: con eso no se publica en npm y se reemplazan los plugins de esa config. En `false` usa los plugins de la config del repo y corre `npm ci` solo si hay `package-lock.json`. `dry_run` default es `false`. En `true` analiza y no publica. El tag flotante, si está prendido, tampoco se mueve: la action igual informa un release, así que ese paso mira los dos inputs. `npm_token` hace falta solo cuando el paquete se publica. `release_token` es opcional; si no está, se usa el `GITHUB_TOKEN` del caller.

api y app publican desde `master`. El caller tiene que pasar esa rama. Esos repos ya tienen la config de semantic-release en `package.json` (`changelog`, `git`, `npmPublish: false`) y el secreto `DEPLOY_TOKEN`, así que no hay que crear otro.

```yaml
jobs:
  release:
    uses: andes/shared-workflows/.github/workflows/semantic-release.yml@v1
    secrets:
      release_token: ${{ secrets.DEPLOY_TOKEN }}
    with:
      branches: "['master']"
      skip_npm: false
      dry_run: true
```

`skip_npm: false` deja los plugins del `package.json`. `dry_run: true` sirve para probar ese análisis en `master` sin publicar. El cron de cada repo queda en el caller.

## Título del pull request

`.github/workflows/pr-title.yml` falla el pull request si el título no es un commit convencional: `tipo(scope): descripción`. El tipo va en minúscula y el scope es opcional. El subject no puede quedar vacío. `Feat:` y `Chore:` fallan.

Cuando el merge es squash, GitHub usa ese título como mensaje del commit. semantic-release solo lee la primera línea, así que el título es el mensaje que publica.

El revert que arma GitHub se llama `Revert "..."`. Ese título falla. Hay que retitularlo a `revert:` antes de mergear. `revert: feat(scope): descripción` pasa.

`.github/workflows/pr-title-check.yml` llama al archivo de este mismo commit en `pull_request` (`opened`, `edited`, `synchronize`, `reopened`). No corre en un push a `main`.

```yaml
name: PR title

on:
  pull_request:
    types: [opened, edited, synchronize, reopened]

permissions:
  pull-requests: read

jobs:
  title:
    uses: andes/shared-workflows/.github/workflows/pr-title.yml@v1
```

## Lint

`.github/workflows/lint.yml` corre actionlint 1.7.12 en cada `push` y `pull_request`. Revisa la sintaxis de los workflows de este repositorio, las expresiones `${{ }}` y los scripts de `run`. El binario se baja del release y se verifica con SHA-256. Los errores quedan anotados en el diff con `.github/actionlint-matcher.json`.

actionlint 1.7.12 no conoce el runner `ubuntu-26.04`. `.github/actionlint.yaml` lo declara para que el check no falle por ese label.

## Dependabot

`.github/dependabot.yml` abre un pull request semanal con las actualizaciones de GitHub Actions, agrupadas en un solo PR. El mensaje es `fix(deps)`, que también publica un patch. Cada `uses` está pineado a un commit, con el comentario de versión en la misma línea (`# vX.Y.Z`). Dependabot usa ese comentario para proponer el bump, incluidos los majors.
