# shared-workflows

Workflows reutilizables de GitHub Actions para los repositorios de Andes. Cada repo los llama con `workflow_call` en lugar de copiar el YAML.

## Conflictos de merge

`.github/workflows/label-merge-conflicts.yml` pone un label cuando un pull request tiene conflictos de merge y lo saca cuando ya no los tiene. El nombre del label es un input; el default es `Conflictos`.

Ese label tiene que existir de antemano en el repositorio que llama. El token del workflow tiene `contents: read` y `pull-requests: write`: alcanza para poner y sacar labels en un pull request, y no para crear el label.

### Cómo llamarlo

El caller tiene que usar `pull_request_target` con los tipos `opened`, `synchronize` y `reopened`.

Un evento `pull_request` que viene de un fork corre con un `GITHUB_TOKEN` de solo lectura, y ese token no puede etiquetar. `pull_request_target` corre en el contexto del repositorio base y el token sí puede escribir labels ahí.

Ese mismo token tiene escritura sobre el repo base. Este workflow solo consulta la API: no hace checkout del head del pull request y no ejecuta código del fork. El caller tiene que mantener esa misma restricción.

GitHub calcula `mergeable_state` en segundo plano. En el payload del webhook el valor suele llegar `unknown` o `null`, así que el workflow vuelve a pedir el pull request y reintenta hasta tener un estado definitivo. `dirty` significa que hay conflictos.

```yaml
name: Label merge conflicts

on:
  pull_request_target:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write

jobs:
  conflicts:
    uses: andes/shared-workflows/.github/workflows/label-merge-conflicts.yml@main
    with:
      label: Conflictos
```

`with.label` es opcional.

Si este repositorio es privado, en Settings → Actions → General → Access hay que permitir que lo usen los demás repositorios de la organización.

## Dependabot

`.github/dependabot.yml` abre un pull request semanal con las actualizaciones de GitHub Actions, agrupadas en un solo PR. Cada `uses` está pineado a un commit, con el comentario de versión en la misma línea (`# vX.Y.Z`). Dependabot usa ese comentario para proponer el bump, incluidos los majors.
