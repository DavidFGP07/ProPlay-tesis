#!/usr/bin/env bash
# Despliegue de la API de ProPlay en Azure (tarea 2.13). Procedimiento completo en
# docs/operacion.md, «Despliegue en Azure»; el porqué, en docs/decisiones.md,
# «Despliegue en Azure y Vercel».
#
#   bash apps/api/scripts/azure.sh crear            # una vez: grupo, Postgres, entorno y la app
#   bash apps/api/scripts/azure.sh actualizar [sha] # despliega la imagen de main (o la de ese commit)
#   bash apps/api/scripts/azure.sh secreto NOMBRE   # pide un secreto sin eco y redespliega (RIOT_API_KEY…)
#   bash apps/api/scripts/azure.sh variable NOMBRE VALOR   # variable sin secreto (CORS_ORIGIN…)
#   bash apps/api/scripts/azure.sh estado           # URL, revisión activa y salud
#   bash apps/api/scripts/azure.sh consola          # shell dentro del contenedor de la API
#   DEMO_CONTRASENA=… bash apps/api/scripts/azure.sh demo   # carga las cuentas de demostración
#   bash apps/api/scripts/azure.sh pausar | reanudar        # detiene o arranca la app y Postgres
#
# Necesita la CLI de Azure con la sesión iniciada (`az login`) o Azure Cloud Shell, y
# openssl. Nunca imprime los secretos: los genera o los pide sin eco y los guarda sólo como
# secretos de la Container App.
#
# Lo que crea (todo en el grupo $GRUPO, borrable de una vez con `az group delete`):
#   - Azure Database for PostgreSQL, servidor flexible B1ms (PostgreSQL 16, 32 GB, copias
#     de seguridad automáticas de 7 días) con la extensión pgvector permitida.
#   - Un entorno de Container Apps (plan de consumo) con su Log Analytics.
#   - La Container App de la API: una réplica fija (el worker de la ingesta vive en el
#     proceso) con dos contenedores, la API y un Redis de acompañamiento en localhost.
set -euo pipefail

GRUPO="${GRUPO:-proplay-rg}"
REGION="${REGION:-eastus2}"
ENTORNO="${ENTORNO:-proplay-env}"
APP="${APP:-proplay-api}"
IMAGEN="${IMAGEN:-ghcr.io/davidfgp07/proplay-api}"
CORS_ORIGIN="${CORS_ORIGIN:-https://proplay-tesis.vercel.app}"
USUARIO_PG="proplay"
BASE_PG="proplay"

falla() {
  echo "Error: $*" >&2
  exit 1
}

requisitos() {
  command -v az >/dev/null || falla "falta la CLI de Azure (az). Usa Azure Cloud Shell o instálala."
  command -v openssl >/dev/null || falla "falta openssl."
  az account show >/dev/null 2>&1 || falla "no hay sesión de Azure: ejecuta az login."
  az extension add --name containerapp --upgrade --only-show-errors >/dev/null
}

# El nombre del servidor de Postgres es global en Azure: se le añade un sufijo
# estable sacado de la suscripción.
nombre_postgres() {
  if [[ -n "${POSTGRES:-}" ]]; then
    echo "$POSTGRES"
    return
  fi
  local suscripcion
  suscripcion="$(az account show --query id -o tsv)"
  echo "proplay-db-${suscripcion:0:8}"
}

app_existe() {
  az containerapp show -n "$APP" -g "$GRUPO" >/dev/null 2>&1
}

# NOMBRE_DE_VARIABLE → nombre de secreto de Container Apps (minúsculas y guiones).
nombre_secreto() {
  echo "$1" | tr '[:upper:]_' '[:lower:]-'
}

# Pide un valor sin eco si no viene ya en el entorno. Puede quedar vacío.
pedir() {
  local variable="$1" descripcion="$2" valor="${!1:-}"
  if [[ -z "$valor" && -t 0 ]]; then
    read -rsp "$descripcion (Enter para dejarla vacía): " valor
    echo >&2
  fi
  printf '%s' "$valor"
}

crear() {
  requisitos
  local postgres
  postgres="$(nombre_postgres)"

  if app_existe; then
    falla "la app $APP ya existe. Para una imagen nueva usa «actualizar»; para empezar de cero, az group delete -n $GRUPO."
  fi

  echo "Registrando los proveedores de recursos (sólo tarda la primera vez)…"
  for proveedor in Microsoft.App Microsoft.OperationalInsights Microsoft.DBforPostgreSQL; do
    az provider register -n "$proveedor" --wait -o none
  done

  echo "Grupo de recursos $GRUPO en $REGION…"
  az group create -n "$GRUPO" -l "$REGION" -o none

  # Contraseña nueva en cada creación de la app: sólo se guarda dentro de su DATABASE_URL.
  # Prefijo para cumplir la política de Azure (mayúscula, minúscula y número).
  local clave_pg
  clave_pg="Pp1$(openssl rand -hex 20)"

  if az postgres flexible-server show -g "$GRUPO" -n "$postgres" >/dev/null 2>&1; then
    echo "El servidor $postgres ya existe: se le pone una contraseña nueva."
    az postgres flexible-server update -g "$GRUPO" -n "$postgres" --admin-password "$clave_pg" -o none
  else
    echo "Creando PostgreSQL $postgres (B1ms). Tarda unos 5-10 minutos…"
    az postgres flexible-server create \
      -g "$GRUPO" -n "$postgres" -l "$REGION" \
      --tier Burstable --sku-name Standard_B1ms \
      --storage-size 32 --version 16 \
      --admin-user "$USUARIO_PG" --admin-password "$clave_pg" \
      --public-access 0.0.0.0 \
      --backup-retention 7 \
      --yes -o none
  fi

  # pgvector: la migración hace CREATE EXTENSION vector, que Azure sólo admite si
  # la extensión está en la lista permitida del servidor.
  az postgres flexible-server parameter set -g "$GRUPO" --server-name "$postgres" \
    --name azure.extensions --value VECTOR -o none
  if ! az postgres flexible-server db show -g "$GRUPO" -s "$postgres" -d "$BASE_PG" >/dev/null 2>&1; then
    az postgres flexible-server db create -g "$GRUPO" -s "$postgres" -d "$BASE_PG" -o none
  fi

  if ! az containerapp env show -n "$ENTORNO" -g "$GRUPO" >/dev/null 2>&1; then
    echo "Creando el entorno de Container Apps $ENTORNO…"
    az containerapp env create -n "$ENTORNO" -g "$GRUPO" -l "$REGION" -o none
  fi
  local entorno_id
  entorno_id="$(az containerapp env show -n "$ENTORNO" -g "$GRUPO" --query id -o tsv)"

  local anthropic riot
  anthropic="$(pedir ANTHROPIC_API_KEY "Clave de Anthropic para el explicador")"
  riot="$(pedir RIOT_API_KEY "Clave de Riot")"

  local database_url jwt jwt_refresh cifrado
  database_url="postgresql://${USUARIO_PG}:${clave_pg}@${postgres}.postgres.database.azure.com:5432/${BASE_PG}?sslmode=require&connection_limit=10"
  jwt="$(openssl rand -hex 48)"
  jwt_refresh="$(openssl rand -hex 48)"
  cifrado="$(openssl rand -hex 32)"

  # El YAML lleva secretos: vive en un archivo temporal sólo legible por ti y se
  # borra al salir, pase lo que pase.
  # Global (no local): el trap de salida tiene que verla después de la función.
  ARCHIVO_YAML="$(umask 077 && mktemp)"
  trap 'rm -f "$ARCHIVO_YAML"' EXIT

  {
    cat <<YAML
location: ${REGION}
name: ${APP}
resourceGroup: ${GRUPO}
type: Microsoft.App/containerApps
properties:
  managedEnvironmentId: ${entorno_id}
  configuration:
    activeRevisionsMode: Single
    ingress:
      external: true
      targetPort: 3000
      transport: auto
      allowInsecure: false
    secrets:
      - name: database-url
        value: '${database_url}'
      - name: jwt-secret
        value: '${jwt}'
      - name: jwt-refresh-secret
        value: '${jwt_refresh}'
      - name: encryption-key
        value: '${cifrado}'
YAML
    [[ -n "$anthropic" ]] && printf "      - name: anthropic-api-key\n        value: '%s'\n" "$anthropic"
    [[ -n "$riot" ]] && printf "      - name: riot-api-key\n        value: '%s'\n" "$riot"
    cat <<YAML
  template:
    scale:
      minReplicas: 1
      maxReplicas: 1
    containers:
      - name: api
        image: ${IMAGEN}:latest
        resources:
          cpu: 0.5
          memory: 1Gi
        env:
          - name: NODE_ENV
            value: production
          - name: PORT
            value: "3000"
          - name: TRUST_PROXY
            value: "2"
          - name: CORS_ORIGIN
            value: '${CORS_ORIGIN}'
          - name: REDIS_URL
            value: redis://localhost:6379
          - name: DATABASE_URL
            secretRef: database-url
          - name: JWT_SECRET
            secretRef: jwt-secret
          - name: JWT_REFRESH_SECRET
            secretRef: jwt-refresh-secret
          - name: ENCRYPTION_KEY
            secretRef: encryption-key
YAML
    [[ -n "$anthropic" ]] && printf "          - name: ANTHROPIC_API_KEY\n            secretRef: anthropic-api-key\n"
    [[ -n "$riot" ]] && printf "          - name: RIOT_API_KEY\n            secretRef: riot-api-key\n"
    cat <<YAML
      - name: redis
        image: docker.io/library/redis:7-alpine
        args: ["redis-server", "--save", "", "--appendonly", "no", "--maxmemory", "300mb", "--maxmemory-policy", "noeviction"]
        resources:
          cpu: 0.25
          memory: 0.5Gi
YAML
  } >"$ARCHIVO_YAML"

  echo "Creando la Container App $APP con ${IMAGEN}:latest…"
  az containerapp create -n "$APP" -g "$GRUPO" --yaml "$ARCHIVO_YAML" -o none

  local fqdn
  fqdn="$(az containerapp show -n "$APP" -g "$GRUPO" --query properties.configuration.ingress.fqdn -o tsv)"
  echo
  echo "Listo. La API queda en https://${fqdn}/api/v1"
  echo "Salud: https://${fqdn}/api/v1/health (la primera vez tarda en aplicar las migraciones)"
  echo "Pon ese dominio en el rewrite /api de vercel.json: https://${fqdn}/api/:ruta*"
}

actualizar() {
  requisitos
  local etiqueta="${1:-latest}"
  echo "Desplegando ${IMAGEN}:${etiqueta}…"
  # Un sufijo de revisión nuevo obliga a crear una revisión aunque la etiqueta sea la misma
  # (latest), así Container Apps vuelve a descargar la imagen.
  az containerapp update -n "$APP" -g "$GRUPO" \
    --container-name api --image "${IMAGEN}:${etiqueta}" \
    --revision-suffix "r$(date +%Y%m%d%H%M%S)" -o none
  estado
}

secreto() {
  requisitos
  local variable="${1:-}"
  [[ "$variable" =~ ^[A-Z][A-Z0-9_]*$ ]] || falla "uso: azure.sh secreto NOMBRE_DE_VARIABLE (p. ej. RIOT_API_KEY)"
  local valor
  read -rsp "Valor de $variable: " valor
  echo
  [[ -n "$valor" ]] || falla "valor vacío: no se cambió nada."
  local nombre
  nombre="$(nombre_secreto "$variable")"
  az containerapp secret set -n "$APP" -g "$GRUPO" --secrets "${nombre}=${valor}" -o none
  # Actualizar la variable crea una revisión nueva, que lee el secreto ya cambiado.
  az containerapp update -n "$APP" -g "$GRUPO" --container-name api \
    --set-env-vars "${variable}=secretref:${nombre}" \
    --revision-suffix "r$(date +%Y%m%d%H%M%S)" -o none
  echo "$variable actualizada y API redesplegada."
}

variable() {
  requisitos
  local nombre="${1:-}" valor="${2:-}"
  [[ "$nombre" =~ ^[A-Z][A-Z0-9_]*$ && -n "$valor" ]] || falla "uso: azure.sh variable NOMBRE VALOR"
  az containerapp update -n "$APP" -g "$GRUPO" --container-name api \
    --set-env-vars "${nombre}=${valor}" -o none
  echo "$nombre actualizada y API redesplegada."
}

estado() {
  requisitos
  local fqdn
  fqdn="$(az containerapp show -n "$APP" -g "$GRUPO" --query properties.configuration.ingress.fqdn -o tsv)"
  echo "URL: https://${fqdn}/api/v1"
  az containerapp revision list -n "$APP" -g "$GRUPO" \
    --query "[?properties.active].{revision:name, imagen:properties.template.containers[0].image, estado:properties.runningState}" -o table
  if command -v curl >/dev/null; then
    echo "Salud:"
    curl -s --max-time 20 "https://${fqdn}/api/v1/health" || echo "(no responde todavía)"
    echo
  fi
}

# Carga las cuentas de demostración (npm run demo:cargar) desde este equipo. Abre
# el firewall de Postgres a tu IP pública sólo mientras dura la carga y lo cierra
# al salir, pase lo que pase. La DATABASE_URL se lee del secreto de la app y no
# se imprime.
demo() {
  requisitos
  [[ -n "${DEMO_CONTRASENA:-}" ]] || falla "define DEMO_CONTRASENA (12 caracteres o más) en el entorno."
  command -v npm >/dev/null || falla "falta npm."
  command -v curl >/dev/null || falla "falta curl."

  POSTGRES_DEMO="$(nombre_postgres)"
  REGLA_DEMO="demo-cargar-temporal"
  local ip url
  ip="$(curl -fsS --max-time 10 https://api.ipify.org)" || falla "no pude averiguar tu IP pública."
  url="$(az containerapp secret show -n "$APP" -g "$GRUPO" --secret-name database-url --query value -o tsv)"
  [[ -n "$url" ]] || falla "la app no tiene el secreto database-url."

  echo "Abriendo Postgres a tu IP mientras dura la carga…"
  trap 'az postgres flexible-server firewall-rule delete -g "$GRUPO" -n "$POSTGRES_DEMO" --rule-name "$REGLA_DEMO" --yes -o none && echo "Regla temporal del firewall borrada."' EXIT
  az postgres flexible-server firewall-rule create -g "$GRUPO" -n "$POSTGRES_DEMO" \
    --rule-name "$REGLA_DEMO" --start-ip-address "$ip" --end-ip-address "$ip" -o none

  (cd "$(dirname "$0")/.." && DATABASE_URL="$url" npm run demo:cargar)
}

# Detiene la app y el servidor de Postgres: deja de cobrarse el cómputo (el
# almacenamiento de Postgres y sus copias, unos 4 USD/mes, se siguen cobrando).
# Azure vuelve a arrancar solo un Postgres detenido a los 7 días.
pausar() {
  requisitos
  local postgres
  postgres="$(nombre_postgres)"
  az containerapp stop -n "$APP" -g "$GRUPO" -o none
  az postgres flexible-server stop -g "$GRUPO" -n "$postgres" -o none
  echo "App y Postgres detenidos. Para volver: azure.sh reanudar."
}

reanudar() {
  requisitos
  local postgres
  postgres="$(nombre_postgres)"
  az postgres flexible-server start -g "$GRUPO" -n "$postgres" -o none
  az containerapp start -n "$APP" -g "$GRUPO" -o none
  estado
}

consola() {
  requisitos
  az containerapp exec -n "$APP" -g "$GRUPO" --container api --command sh
}

case "${1:-}" in
  crear) crear ;;
  actualizar) actualizar "${2:-}" ;;
  secreto) secreto "${2:-}" ;;
  variable) variable "${2:-}" "${3:-}" ;;
  estado) estado ;;
  consola) consola ;;
  demo) demo ;;
  pausar) pausar ;;
  reanudar) reanudar ;;
  *)
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
