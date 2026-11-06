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

El ref es el tag flotante `v1`. Cada release 1.x lo mueve al commit publicado, así que los callers siguen en la versión 1 sin cambiar el YAML. El tag aparece con el primer release estable 1.x.

Si este repositorio es privado, en Settings → Actions → General → Access hay que permitir que lo usen los demás repositorios de la organización.

## Semantic release

`.github/workflows/semantic-release.yml` publica en GitHub a partir de commits convencionales (`feat`, `fix`, y `BREAKING CHANGE` para un major). En este repo, `.releaserc.json` también publica un patch por los bumps de Dependabot (`build(deps)` y `chore(deps)`), así el tag `v1` se mueve y los callers reciben el pin nuevo. El default no publica en npm. Corre en `ubuntu-26.04`, con Node 22, y el token tiene `contents: write`, `issues: write` y `pull-requests: write`.

Después de un release estable mueve el tag `v<major>` a ese commit. `v1` sigue a la línea 1.x. Un prerelease no lo mueve.

`.github/workflows/release.yml` lo dispara en cada push a `main`, llamando al archivo de este mismo commit. La llamada de este repo a `andes/shared-workflows/.github/workflows/semantic-release.yml@v1` queda pendiente: el tag todavía no existe.

`branches` default es `['main']` y pisa el `branches` de la config del repo. `skip_npm` default es `true`: con eso no se publica en npm y se reemplazan los plugins de esa config. `npm_token` hace falta solo cuando el paquete se publica. `release_token` es opcional; si no está, se usa el `GITHUB_TOKEN` del caller.

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
```

`skip_npm: false` deja los plugins del `package.json`. El cron de cada repo queda en el caller.

## Dependabot

`.github/dependabot.yml` abre un pull request semanal con las actualizaciones de GitHub Actions, agrupadas en un solo PR. El mensaje es `fix(deps)`, que también publica un patch. Cada `uses` está pineado a un commit, con el comentario de versión en la misma línea (`# vX.Y.Z`). Dependabot usa ese comentario para proponer el bump, incluidos los majors.
