#!/usr/bin/env bash
# Lógica común de plan|apply para repos de infra Andes.
# Inputs llegan por entorno desde action.yml.
set -euo pipefail

cmd="${COMMAND:?}"
root="${GITHUB_WORKSPACE:?}"
workdir="${WORKING_DIRECTORY:?}"
state_name="${STATE_NAME:?}"
tf_version="${TERRAFORM_VERSION:?}"
cred="${INFISICAL_ENV_FILE:?}"
require_existing_state="${REQUIRE_EXISTING_STATE:-false}"
export_project_id="${EXPORT_PROJECT_ID:-true}"
install_sops="${INSTALL_SOPS:-false}"
sops_version="${SOPS_VERSION:-3.13.3}"
pre_script="${PRE_SCRIPT:-}"
post_apply_script="${POST_APPLY_SCRIPT:-}"

case "${cmd}" in
  plan|apply) ;;
  *)
    echo "uso: command=plan|apply" >&2
    exit 1
    ;;
esac

cd "${root}/${workdir}"

state_dir="/opt/andes/terraform-state/${state_name}"
state_file="${state_dir}/terraform.tfstate"

if [[ "${require_existing_state}" == "true" ]]; then
  if [[ ! -s "$state_file" ]]; then
    echo "ERROR: $state_file no existe o está vacío." >&2
    echo "Copiá el terraform.tfstate actual a esa ruta antes del primer plan." >&2
    echo "Sin ese archivo, Terraform quiere recrear recursos que ya existen." >&2
    exit 1
  fi
  if [[ ! -w "$state_file" ]]; then
    echo "ERROR: dentro del contenedor, $state_file no se puede escribir." >&2
    id >&2 || true
    ls -ld /opt/andes /opt/andes/terraform-state "$state_dir" >&2 || true
    echo "El directorio del host entra al job solo si el contenedor tiene el volumen" >&2
    echo "  /opt/andes/terraform-state:/opt/andes/terraform-state" >&2
    exit 1
  fi
else
  if [[ ! -d "$state_dir" || ! -w "$state_dir" ]]; then
    echo "ERROR: dentro del contenedor, $state_dir no existe o no se puede escribir." >&2
    id >&2 || true
    ls -ld /opt/andes /opt/andes/terraform-state "$state_dir" >&2 || true
    echo "El directorio del host entra al job solo si el contenedor tiene el volumen" >&2
    echo "  /opt/andes/terraform-state:/opt/andes/terraform-state" >&2
    echo "y se recreó después de crearlo. En la VM del runner:" >&2
    echo "  sudo install -d -o runner-deployer -g redtics -m 2770 /opt/andes/terraform-state" >&2
    echo "  sudo install -d -o runner-deployer -g redtics -m 2770 ${state_dir}" >&2
    exit 1
  fi
fi

# source para que exports del prep (p. ej. KRB5_CONFIG) vivan en este proceso.
if [[ -n "${pre_script}" ]]; then
  # shellcheck disable=SC1090
  source "${root}/${pre_script}"
fi

bin="${RUNNER_TEMP:-/tmp}/tf-bin"
mkdir -p "$bin"

if [[ ! -x "$bin/terraform" ]]; then
  curl -fsSL -o "$bin/terraform.zip" \
    "https://releases.hashicorp.com/terraform/${tf_version}/terraform_${tf_version}_linux_amd64.zip"
  if command -v unzip >/dev/null; then
    unzip -o -d "$bin" "$bin/terraform.zip" >/dev/null
  else
    python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract("terraform", sys.argv[2])' \
      "$bin/terraform.zip" "$bin"
  fi
  chmod +x "$bin/terraform"
fi

if [[ "${install_sops}" == "true" && ! -x "$bin/sops" ]]; then
  curl -fsSL -o "$bin/sops" \
    "https://github.com/getsops/sops/releases/download/v${sops_version}/sops-v${sops_version}.linux.amd64"
  chmod +x "$bin/sops"
fi

export PATH="$bin:$PATH"

if [[ -z "${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:-}" || -z "${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:-}" ]]; then
  if [[ ! -r "$cred" ]]; then
    echo "ERROR: no se puede leer $cred" >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$cred"
  set +a
fi

: "${INFISICAL_UNIVERSAL_AUTH_CLIENT_ID:?falta INFISICAL_UNIVERSAL_AUTH_CLIENT_ID en $cred}"
: "${INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET:?falta INFISICAL_UNIVERSAL_AUTH_CLIENT_SECRET en $cred}"

if [[ "${export_project_id}" == "true" ]]; then
  : "${INFISICAL_PROJECT_ID:?falta INFISICAL_PROJECT_ID en $cred}"
  export TF_VAR_infisical_project_id="$INFISICAL_PROJECT_ID"
fi

if [[ "${install_sops}" == "true" && -z "${SOPS_AGE_SSH_PRIVATE_KEY_FILE:-}" ]]; then
  if [[ -r /opt/andes/secrets-manager/id_ed25519 ]]; then
    export SOPS_AGE_SSH_PRIVATE_KEY_FILE=/opt/andes/secrets-manager/id_ed25519
  elif [[ -r /home/runner-deployer/.ssh/id_ed25519 ]]; then
    export SOPS_AGE_SSH_PRIVATE_KEY_FILE=/home/runner-deployer/.ssh/id_ed25519
  else
    echo "ERROR: no se puede leer la privada de runner-deployer para SOPS." >&2
    exit 1
  fi
fi

export INFISICAL_HOST="${INFISICAL_HOST:-https://secrets.andes.gob.ar}"
export INFISICAL_AUTH_METHOD="${INFISICAL_AUTH_METHOD:-universal}"
export TF_IN_AUTOMATION=1

terraform init -input=false -backend-config="path=${state_dir}/terraform.tfstate"

case "${cmd}" in
  plan) terraform plan -input=false -no-color ;;
  apply)
    terraform apply -input=false -auto-approve -no-color
    if [[ -n "${post_apply_script}" ]]; then
      bash --noprofile --norc -euo pipefail "${root}/${post_apply_script}"
    fi
    ;;
esac
