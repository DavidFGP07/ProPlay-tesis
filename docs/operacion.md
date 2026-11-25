# Operación

Procedimientos que se ejecutan a mano sobre un entorno, fuera de la aplicación.

Los pasos «en el servidor» se refieren al despliegue de Azure descrito en la primera
sección: la consola del contenedor se abre con `bash apps/api/scripts/azure.sh consola`.

---

## Despliegue en Azure

Tarea 2.13. La API, con su Redis, va en Azure Container Apps; la base, en Azure Database for
PostgreSQL; la web, en Vercel, que reenvía `/api/*` a la API. El porqué, en
`docs/decisiones.md`, «Despliegue en Azure y Vercel».

### Lo que cuesta

Con la suscripción **Azure for Students** (100 USD de crédito, sin tarjeta: al agotarse, los
recursos se detienen y no se cobra nada):

| Recurso | Tamaño | Coste aproximado |
| --- | --- | --- |
| PostgreSQL flexible | B1ms, 32 GB, copias de 7 días | 0 USD si la oferta incluye las 750 h/mes gratis de B1ms; si no, unos 15 USD/mes |
| Container App | 0,75 vCPU y 1,5 GiB en total, una réplica siempre encendida | 10-25 USD/mes según el tráfico (la réplica inactiva se cobra a tarifa reducida) |
| Log Analytics | Registros de la API | 0 USD dentro de los 5 GB/mes gratis |
| Imagen | `ghcr.io` (GitHub) | 0 USD |
| Web | Vercel Hobby | 0 USD |

Unos **15-40 USD al mes**: el crédito alcanza para el piloto y la sustentación. Lo consumido se
ve en el portal, **Cost Management**. Al terminar, `az group delete -n proplay-rg` lo borra todo
(antes, exporta las métricas del piloto).

### Primera vez

1. **Imagen.** Fusiona en `main`: cuando el CI termina en verde, el flujo «Imagen de la API»
   publica `ghcr.io/davidfgp07/proplay-api`. La primera vez el paquete nace **privado**: en
   GitHub, tu perfil → **Packages** → `proplay-api` → **Package settings** → **Change
   visibility** → **Public**. Azure lo descarga sin credenciales; el código ya es público.
2. **Sesión de Azure.** Entra en <https://portal.azure.com> con la cuenta de estudiante y abre
   **Cloud Shell** (Bash), que ya trae `az`; o instala la CLI en tu equipo y ejecuta `az login`.
3. **Crear.** Desde la raíz del repositorio (en Cloud Shell, clónalo antes):

   ```bash
   CORS_ORIGIN=https://<tu-proyecto>.vercel.app bash apps/api/scripts/azure.sh crear
   ```

   Pide sin eco la clave de Anthropic y la de Riot (Enter deja una vacía; se añaden luego con
   `secreto`). Genera `JWT_SECRET`, `JWT_REFRESH_SECRET`, `ENCRYPTION_KEY` y la contraseña de
   Postgres, y las guarda sólo como secretos de la Container App. Tarda unos 15 minutos y
   termina imprimiendo el dominio `*.azurecontainerapps.io`. Si la suscripción no permite
   `eastus2`, repite con `REGION=<otra>`.
4. **Comprobar.** `bash apps/api/scripts/azure.sh estado` debe mostrar `/health` con
   `"status": "ok"` (Postgres y Redis `"up"`). Si no arranca, los registros están en el portal →
   Container App `proplay-api` → **Log stream**.
5. **Web.** Pon el dominio en el primer rewrite de `vercel.json`
   (`https://<dominio>/api/:ruta*`) con un PR. Luego, en <https://vercel.com>, **Add New →
   Project**, importa el repositorio y despliega sin cambiar ningún ajuste.
6. **CORS.** Si el dominio final de Vercel no es el que pusiste en `CORS_ORIGIN`:

   ```bash
   bash apps/api/scripts/azure.sh variable CORS_ORIGIN https://<dominio-final>.vercel.app
   ```

7. **Datos de demostración.** Ver «Datos de demostración en producción», más abajo.
8. **Administrador.** Regístrate en la web y promueve tu cuenta (sección «Alta del primer
   administrador», «En el servidor desplegado»), o usa `admin@proplay.gg` de la demostración.

### Datos de demostración en producción

La evaluación necesita datos: equipos, jugadores verificados, ofertas y postulaciones. El
seed los crea, pero sus cuentas tienen una contraseña **publicada** en el repositorio, así que
contra una base que no es local **se niega** a cargarlos sin una contraseña propia:

```bash
DEMO_CONTRASENA='<12 caracteres o más>' bash apps/api/scripts/azure.sh demo
```

Abre el firewall de Postgres a tu IP pública, ejecuta `npm run demo:cargar` con la
`DATABASE_URL` de la app (leída del secreto, sin imprimirla) y borra la regla al terminar,
aunque falle. Crea las mismas cuentas que en local (`admin@proplay.gg`, `scout@proplay.gg`,
`equipo@caribeesports.gg`, `jugador1@proplay.gg`…) con la contraseña de `DEMO_CONTRASENA`,
que no se guarda en ningún archivo: apúntala en tu gestor de contraseñas.

- Es idempotente: repetirlo no duplica nada, y repetirlo con otra contraseña la cambia en
  todas las cuentas de demostración.
- No toca las cuentas reales. Las métricas del piloto excluyen las del seed por defecto.
- Las cuentas de Riot de la demostración son ficticias: la ingesta no las sincroniza y
  sincronizarlas a mano responde `CUENTA_DE_DEMOSTRACION`.

### Después de la sustentación: apagar para no gastar crédito

**Pausa** (para volver a usarlo, p. ej. si el jurado pide verlo otra vez):

```bash
bash apps/api/scripts/azure.sh pausar     # detiene la app y Postgres
bash apps/api/scripts/azure.sh reanudar   # los vuelve a arrancar
```

Detenidos, se deja de pagar el cómputo; el almacenamiento de Postgres y sus copias se siguen
cobrando (unos 4 USD/mes). **Azure arranca solo un Postgres detenido a los 7 días**: si la
pausa es larga, repite `pausar` cada semana o bórralo todo.

**Borrado definitivo** (cuando la tesis esté entregada):

1. Exporta antes lo que necesites: las métricas del piloto (`docs/operacion.md`, «Métricas
   del piloto») y, si quieres conservar la base, un `pg_dump` (sección anterior).
2. Borra el grupo de recursos; se lleva la app, el entorno, los registros y Postgres con
   sus copias. **No se puede deshacer:**

   ```bash
   az group delete -n proplay-rg
   ```

3. Comprueba en el portal, **Cost Management**, que el gasto diario baja a 0 al día
   siguiente.
4. En Vercel, el proyecto no cuesta nada; si quieres retirarlo, **Settings → Delete
   Project**. La imagen de `ghcr.io` tampoco cuesta.

### Desplegar una versión nueva

Fusiona en `main`, espera a que el flujo «Imagen de la API» termine y:

```bash
bash apps/api/scripts/azure.sh actualizar
```

La web se redespliega sola en Vercel con cada push a `main`. Las migraciones se aplican al
arrancar el contenedor. Para volver atrás, `actualizar <sha>` con el SHA de un commit
anterior de `main`.

### Copias de seguridad y restauración

Azure hace copias automáticas del servidor de Postgres y permite restaurarlo a cualquier
momento de los **últimos 7 días**. La restauración crea un servidor nuevo:

```bash
az postgres flexible-server restore -g proplay-rg --name proplay-db-restaurado \
  --source-server <servidor-original> --restore-time "2026-12-01T12:00:00Z"
```

Después, apunta la API al servidor nuevo con
`bash apps/api/scripts/azure.sh secreto DATABASE_URL` (la misma URL cambiando el nombre del
servidor). Redis no tiene copia: sólo guarda cachés y la cola, que se reconstruyen.

Antes de una operación arriesgada, un volcado a mano desde tu equipo (abre antes tu IP en el
portal: servidor de Postgres → **Networking** → **Add current client IP address**):

```bash
pg_dump "<DATABASE_URL>" --format=custom --file proplay-$(date +%F).dump
```

## Alta del primer administrador

`ADMIN` no es un rol registrable (`ROLES_REGISTRABLES`) y todavía no hay endpoint
para cambiar roles: llega con el módulo `admin` en el S4. Mientras tanto, un
administrador se da de alta con un script que **promueve a `ADMIN` una cuenta ya
registrada**. Es la tarea 1.4 del plan (RF-01).

### Antes de ejecutarlo

1. **La persona se registra en la aplicación como scout**, con su propio correo y su
   contraseña. Así la contraseña la define ella y nunca pasa por la terminal ni por
   su historial.
2. Tiene que ser una cuenta propia para administrar. El script **se niega** con:
   - una cuenta de jugador o de equipo: su perfil público quedaría huérfano y la
     persona desaparecería de las búsquedas;
   - una cuenta desactivada;
   - un correo que no corresponde a ninguna cuenta.

### En local

Desde la raíz del monorepo, con la base de `apps/api/.env` levantada:

```bash
npm run admin:promover -w api -- persona@dominio.com
```

### En el servidor desplegado

La imagen de producción no trae `tsx` ni el código fuente, sólo el compilado. Abre
una consola en el contenedor de la API (`bash apps/api/scripts/azure.sh consola`), que ya tiene `DATABASE_URL` y el resto de variables, y ejecuta
desde `/app`:

```bash
node apps/api/dist/cli/promoverAdministrador.js persona@dominio.com
```

El script carga la misma configuración que la API, así que falla al arrancar si
falta alguna variable obligatoria.

### Qué hace y qué responde

| Situación | Salida | Código |
| --- | --- | --- |
| Cuenta de scout activa | Pasa a `ADMIN` y se registra en `AuditLog` | `0` |
| Ya era administrador | No cambia nada ni duplica la traza | `0` |
| Cuenta de jugador o de equipo, desactivada o inexistente, o correo mal formado | No cambia nada; explica el motivo | `1` |
| Sin correo o con más de un argumento | Muestra el uso | `2` |

- El cambio de rol y su traza se guardan en la **misma transacción**. La traza es
  una fila de `AuditLog` con `accion: "ROL_CAMBIADO"`, `entidad: "Usuario"`, el id
  de la cuenta y `metadata: { rolAnterior, rolNuevo: "ADMIN", origen: "cli" }`.
- El correo se recorta y se pasa a minúsculas, igual que en el registro.
- **No cierra las sesiones abiertas.** El access token ya emitido conserva el rol
  anterior hasta que caduca (15 minutos como máximo); el siguiente refresco lee el
  rol de la base y entrega uno con `ADMIN`. Si la persona tenía la sesión abierta,
  basta con esperar ese refresco o volver a entrar.

### Comprobar el resultado

```sql
SELECT email, rol, activo FROM "Usuario" WHERE email = 'persona@dominio.com';

SELECT "creadoEn", accion, metadata
FROM "AuditLog"
WHERE accion = 'ROL_CAMBIADO'
ORDER BY "creadoEn" DESC
LIMIT 5;
```

### Lo que no hace

- No crea cuentas ni recibe contraseñas.
- No quita el rol de administrador. Mientras no exista el módulo `admin`, revertirlo
  exige un `UPDATE` manual que también debe dejarse en `AuditLog`.
- No sustituye al seed: `npm run db:seed` crea `admin@proplay.gg` con la contraseña
  de demostración y **nunca debe ejecutarse en producción**.

## Ingesta de Riot

La API sincroniza sola, cada `INGESTA_INTERVALO_HORAS` horas (6 por defecto), las
estadísticas de los jugadores con cuenta de Riot verificada, y atiende las sincronizaciones que piden los jugadores. Todo pasa por una cola en
Redis (BullMQ) y por la cuota de Riot, que es de toda la aplicación. El porqué está en
`docs/decisiones.md`, «Cuota de Riot e ingesta».

Las cuentas del seed (`puuid` `seed-…`) quedan fuera: ni el planificador ni el botón
«Sincronizar» las encolan, y no se pide nada a Riot por ellas. Muestran la fecha de
sincronización que les puso el seed (la de su última captura). Una cuenta real vinculada
durante la demostración se sincroniza con normalidad.

### Dónde corre

- **En local**: `npm run dev` levanta la API y, dentro de ella, el worker y el planificador.
  No hay que arrancar nada más. Sin `RIOT_API_KEY` la cola queda en pausa y el resto funciona.
- **En el servidor**: igual, dentro del contenedor de la API (`INGESTA_ACTIVA=true`, el valor
  por defecto). Por eso la API tiene que estar siempre encendida: en un plan que suspenda el
  servicio por inactividad, la sincronización periódica se detiene mientras duerme. Si algún
  día se separa, se arranca otro servicio con la misma imagen y
  `node apps/api/dist/ingesta/main.js`, y se pone `INGESTA_ACTIVA=false` en la API.

### Ver el estado

```bash
npm run ingesta:estado -w api
```

En el servidor: `node apps/api/dist/cli/estadoIngesta.js` desde `/app`. Dice si la clave es
válida, si la cola está en pausa, cuántos trabajos hay en espera, en curso, reprogramados y
fallidos, y el uso de cada ventana de la cuota. `GET /api/v1/health` sólo dice
`riot: "ok"` o `"no disponible"`, sin el motivo, porque es público.

### Renovar la clave de desarrollo (cada día)

La clave de desarrollo de Riot **caduca a las 24 horas**. Cuando caduca, Riot responde 403:
la API la marca como caducada, **pausa la cola** (no gasta reintentos), deja en el registro
`Riot rechazó RIOT_API_KEY…`, y vincular o sincronizar responde «inténtalo más tarde».

1. Entra en <https://developer.riotgames.com> con la cuenta del proyecto y pulsa
   **Regenerate API Key**.
2. Pon la clave nueva en `RIOT_API_KEY`:
   - en local, en `apps/api/.env`;
   - en Azure, con `bash apps/api/scripts/azure.sh secreto RIOT_API_KEY`.
3. **Reinicia la API** (en local, para y vuelve a lanzar `npm run dev`; en Azure, `secreto`
   ya redespliega).
4. Comprueba con `npm run ingesta:estado -w api` que dice «Clave de Riot: válida» y
   «Cola de ingesta: activa». Al arrancar con una clave distinta de la caducada, la cola se
   reanuda sola y procesa lo que quedó pendiente.

Reiniciar con la **misma** clave caducada no reanuda nada: la API la reconoce por su huella.

### Piloto: vinculaciones en tandas

Con la clave de desarrollo, la cuota es de **100 peticiones cada 2 minutos para toda la
aplicación** (`RIOT_LIMITES`, por defecto `20:1,100:120`, con el `RIOT_RESERVA_ALTA` % de cada
ventana reservado a vincular y comprobar el icono). Vincular gasta 2 peticiones, cada comprobación del icono 1 (la vista comprueba
sola cada 45 s) y cada sincronización hasta 24. En la sesión de arranque del piloto,
**organiza las vinculaciones en tandas de unos 10 jugadores**: que una tanda termine de
vincular (unos minutos, lo que tarda Riot en reflejar el icono) antes de que empiece la
siguiente. Con más a la vez nadie ve un error, pero las comprobaciones dirán «Mucha demanda,
reintentando» y las sincronizaciones esperarán en la cola.

Las sincronizaciones de los recién vinculados pueden esperar: la periódica los recoge en las
siguientes horas, o pueden pedirla desde «Cuentas vinculadas» cuando acabe la sesión.

## Explicador con modelo de lenguaje

El detalle del candidato muestra, sobre la tabla de aportes, el bloque «Por qué encaja
(generado con IA)»: un texto que redacta Claude Haiku 5.5 a partir del desglose (RF-11). Si
el explicador está desactivado o falla, el bloque se sustituye por una nota y queda la
explicación determinista: el ranking y el puesto nunca dependen de él. El porqué, en
`docs/decisiones.md`, «Explicador con modelo de lenguaje».

### Activarlo

1. Crea una clave en la consola de Anthropic (<https://platform.claude.com>, **API Keys**).
2. Ponla en `ANTHROPIC_API_KEY`:
   - en local, en `apps/api/.env`;
   - en Azure, con `bash apps/api/scripts/azure.sh secreto ANTHROPIC_API_KEY`.

   **Nunca** en `apps/web/.env` ni en ninguna variable `VITE_*`: se empaquetaría en el
   cliente y sería pública. El registro de la API la oculta.
3. Deja `EXPLICADOR_ACTIVO=true` (el valor por defecto) y reinicia la API.

### Desactivarlo

Pon `EXPLICADOR_ACTIVO=false` (o quita la clave) y reinicia la API. Las peticiones responden
`NO_DISPONIBLE` con el motivo `DESACTIVADO`, sin llamar a nadie, y la vista enseña la nota.

### Ajustes

| Variable | Por defecto | Qué cambia |
| --- | --- | --- |
| `EXPLICADOR_MODELO` | `claude-haiku-5-5` | Modelo que redacta |
| `EXPLICADOR_TIMEOUT_MS` | `4000` | Espera máxima de una generación; pasada, se degrada |
| `EXPLICADOR_LIMITE_USUARIO_HORA` | `30` | Generaciones nuevas por usuario y hora |
| `EXPLICADOR_LIMITE_DIARIO` | `300` | Generaciones nuevas al día en toda la aplicación |

Los textos se guardan en Redis 30 días por contenido: abrir otra vez el mismo candidato, sin
cambios en su desglose, no vuelve a llamar al modelo ni gasta los límites.

### Registros

Con el explicador activo, cada petición deja una línea `Explicación del candidato` (módulo
`explicador`) con el
modelo, la versión del prompt, los milisegundos y, si llamó al modelo, `tokensEntrada`,
`tokensSalida` y `costeUsd` (estimado). Si se degradó, lleva `motivo` y, para la fidelidad,
`causa` y el elemento que falló. **Nunca** lleva la entrada ni el texto generado.

### Prueba manual con la clave real

Es la comprobación que no hace el CI (que nunca llama al proveedor real). Con el seed y la
oferta «ADC para la liga en línea»:

1. Pon la clave en `apps/api/.env` como en «Activarlo».
2. Desde la raíz del monorepo:

   ```bash
   docker compose up -d
   npm run db:deploy
   npm run db:seed
   npm run dev
   ```

3. Entra en <http://localhost:5173> con `equipo@caribeesports.gg` y la contraseña de
   demostración del seed.
4. Ve a **Vacantes** → «ADC para la liga en línea» → **Ver ranking de candidatos**.
5. Abre el **puesto 1**. En unos segundos aparece «Por qué encaja (generado con IA)» sobre
   la tabla de aportes. Copia el texto.
6. Repite con los **puestos 2 y 3** (con «Candidato siguiente», al pie del detalle).
7. En la terminal de `npm run dev`, comprueba que hay tres líneas `Explicación del
   candidato` con `tokensEntrada`, `tokensSalida` y `costeUsd`, y ninguna con `motivo`.
8. Vuelve a abrir el puesto 1 recargando la página: la línea nueva dice `deCache: true` y no
   lleva tokens.

Qué revisar en cada texto: 2 o 3 frases (4 si hay requisitos sin cumplir); primero lo que más
suma y después lo que más resta, sin repetirlo; en el puesto 1, que la técnica sume por la
posición y el rango y reste por el rendimiento (`mismaDimension`), sin contradecirse; una
última frase que empiece por «No cumple» con cada requisito que falte (en el puesto 1, las
horas: 15 frente a 20); ninguna cifra que no esté en la tabla, ni la escala de las métricas, ni
nombres de campo como «winRate»; ningún juicio sobre la persona.

**Si sale la nota en vez del texto**, la línea del registro dice el motivo (o la respuesta de
la API, en la pestaña Red del navegador):

| `motivo` | Qué hacer |
| --- | --- |
| Ninguna línea (`DESACTIVADO`) | La API no leyó la clave o `EXPLICADOR_ACTIVO` es `false`: revisa `apps/api/.env` y reinicia `npm run dev` |
| `ERROR` | Clave inválida o sin saldo (la línea no trae el mensaje de Anthropic: pruébala en la consola), o Redis caído (`docker compose ps`) |
| `TIEMPO_AGOTADO` | Sube `EXPLICADOR_TIMEOUT_MS` (por ejemplo, a `8000`) y reinicia |
| `FIDELIDAD` | El modelo escribió algo que no estaba en la entrada, usó un nombre de campo del JSON o «win rate» (`causa` `NOMBRE_DE_CAMPO`), dijo que las horas están verificadas (`causa` `HORAS_VERIFICADAS`; las declara el jugador), o calló un requisito que el candidato no cumple (`causa` `REQUISITOS_OMITIDOS`); `causa` y `detalle` dicen qué. No se guarda: recarga la página para pedir otro |
| `LIMITE` | Se agotó un límite; espera a la hora siguiente o súbelo |

Para volver a generar los textos desde cero (por ejemplo, tras cambiar el prompt sin subir
su versión), borra la caché:

```bash
docker exec proplay-redis sh -c "redis-cli --scan --pattern 'explicador:texto:*' | xargs -r redis-cli del"
```

## Vectores del motor de matching

El motor de matching (RF-09) guarda un vector de 64 dimensiones por jugador en `PerfilVector`.
Se recalcula solo: tras cada ingesta con estadísticas nuevas y, antes de cada ranking, el de
todo jugador cuyo vector esté obsoleto. El motor no llama a Riot: con la clave caducada, los
rankings siguen funcionando con los datos guardados.

Hay que recalcularlos todos a mano sólo **al subir `PERFIL_VECTOR_VERSION`** (cambio del
vectorizador), para que la primera consulta de ranking no pague el recálculo de todos:

- **Local**: `npm run matching:revectorizar -w api`
- **Servidor**: `node apps/api/dist/cli/revectorizar.js`

Escribe cuántos vectores recalculó y en cuánto tiempo. Se puede repetir sin riesgo.

## Métricas del piloto (informe de la tesis)

Las métricas de todo el piloto no tienen vista: el panel de administración quedó fuera
del alcance (decisión 0.10). Salen de un script que escribe seis CSV con **las mismas
definiciones que la analítica de la aplicación** (`docs/arquitectura.md`, «Analítica»).
Es RF-13 y las tareas 4.14 y 4.16 del plan.

### En local

```bash
npm run metricas:piloto -w api -- --desde 2026-11-20 --hasta 2026-12-20 --salida ./metricas
```

### En el servidor desplegado

Desde una consola del servicio de la API, que ya tiene `DATABASE_URL`:

```bash
node apps/api/dist/cli/metricasPiloto.js --desde 2026-11-20 --hasta 2026-12-20 --salida /tmp/metricas
```

### Opciones

| Opción | Qué hace |
| --- | --- |
| `--desde AAAA-MM-DD` | Primer día de publicación de las ofertas, incluido, en la fecha de Colombia |
| `--hasta AAAA-MM-DD` | Último día de publicación, incluido |
| `--salida <carpeta>` | Dónde escribir los CSV. Por defecto, `./metricas-piloto` |
| `--excluir-prueba` | **Activa por defecto.** Deja fuera las cuentas del seed: sus correos fijos, los `jugadorN@proplay.gg` y las cuentas de Riot con `puuid` `seed-…` (`apps/api/src/utils/datosDePrueba.ts`). Quita sus ofertas, sus postulaciones, sus filas de los rankings y sus registros |
| `--no-excluir-prueba` | Las incluye (o `--excluir-prueba=false`) |

La ventana de fechas filtra las **ofertas**. El mapa del talento y los registros por rol
son de toda la base, porque no dependen de cuándo se publicó una oferta.

### Qué escribe

| Archivo | Contenido |
| --- | --- |
| `resumen_h1.csv` | Tiempo hasta cubrir y hasta el primer tryout (mediana, media y n) frente a la línea base, que sale como `pendiente` mientras no exista. También: coincidencias exitosas, conversión, cobertura, registros por rol, proporción de verificados y los parámetros con que se generó |
| `tiempo_hasta_cubrir.csv` | Una fila por oferta: equipo, estado, fechas en Colombia, postulaciones y sus tiempos |
| `embudo_por_oferta.csv` | Por etapa: alcanzaron, conversión, siguen, rechazadas y rechazadas al cerrar. Una fila `TOTAL` por etapa y luego las de cada oferta |
| `tiempos_por_etapa.csv` | Días transcurridos en cada etapa (n, mediana y media), en total y por oferta |
| `dimension_decisiva.csv` | Por oferta: candidatos, dimensión decisiva y ventaja de cada dimensión. Pone al día el ranking de las ofertas abiertas; las cubiertas o cerradas conservan su instantánea |
| `talento_verificado.csv` | El mapa del talento con el umbral de privacidad aplicado: una celda oculta dice `oculto` |

Formato: CSV según RFC 4180, con coma como separador, punto decimal, UTF-8 y hasta 4
decimales. Un dato que no existe (una oferta sin tiempo hasta cubrir, por ejemplo) es una
celda vacía, no un 0.

Las cifras son **evidencia descriptiva con su n**, no un contraste estadístico: con el
tamaño del piloto no hay potencia para una prueba de hipótesis (`docs/decisiones.md`,
«Analítica»).

---

## Demostración en local

### Reiniciar la base de la demostración

```bash
npm run demo:reiniciar
```

Deja la base de `DATABASE_URL` exactamente como la crea el seed: borra la base entera, le
aplica todas las migraciones (el índice HNSW incluido) y ejecuta `prisma/seed.ts`. No queda
nada de los ensayos: ni postulaciones, ni ofertas, ni cambios de etapa, ni notificaciones,
ni cuentas creadas a mano. Volver a sembrar con `npm run db:seed` **no** basta para eso: el
seed pone al día sus propias filas, pero no borra las que se crearon después.

Sólo se ejecuta contra una base local de desarrollo. Se niega con `NODE_ENV=production`,
contra un servidor de base de datos que no sea `localhost`, `127.0.0.1` o `::1` y contra la
base de las pruebas (`*_test`), que gestiona `npm test`.

Después, reinicia la API si estaba en marcha: el contador del límite de peticiones vive en
su memoria. Los navegadores que tuvieran una sesión abierta la pierden al recargar, porque
su cuenta se creó de nuevo.

### Antes de la demostración

1. `npm run demo:reiniciar`.
2. En `apps/api/.env`, `LIMITE_GLOBAL_PETICIONES=100000`: en local todas las peticiones
   salen de la misma IP y un recorrido por los tres roles agota las 300 por defecto en
   unos 20 minutos. `/auth/logout` no cuenta nunca para ese límite.
3. Renueva `RIOT_API_KEY` («Renovar la clave de desarrollo») si vas a vincular una cuenta
   real; las cuentas del seed no la necesitan.
4. Comprueba el explicador con la clave real («Prueba manual con la clave real»). Sin
   ella, el detalle del candidato muestra sólo la explicación determinista.
5. Arranca con `npm run dev`.
