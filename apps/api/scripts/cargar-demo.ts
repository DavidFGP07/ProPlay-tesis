// Carga las cuentas y los datos de demostración en una base que NO es la local
// (producción), con una contraseña propia en lugar de la pública del seed.
//
//   DATABASE_URL=… DEMO_CONTRASENA=… npm run demo:cargar -w api
//
// En Azure lo lanza `bash apps/api/scripts/azure.sh demo`, que abre el firewall
// de Postgres a tu IP sólo mientras dura la carga. Procedimiento en
// docs/operacion.md, «Datos de demostración en producción».
//
// Ejecuta el mismo seed que `npm run db:seed` (idempotente: se puede repetir, y
// repetirlo con otra DEMO_CONTRASENA la cambia en todas las cuentas). No borra
// nada de lo que hayan creado los usuarios reales.
import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { esBaseDePruebas, esServidorLocal } from "./base-pruebas";

const RAIZ_API = join(__dirname, "..");

/** Contraseña pública de las cuentas del seed (README): sólo para una base local. */
export const CONTRASENA_SEED_LOCAL = "ProPlay123";
export const LONGITUD_MINIMA_CONTRASENA_DEMO = 12;

export type EleccionContrasena =
  | { contrasena: string; publica: boolean }
  | { error: string };

/**
 * Contraseña de las cuentas de demostración para la base de `url`: la de
 * DEMO_CONTRASENA si viene (larga y distinta de la pública), la pública del
 * seed si la base es local, o el motivo para no cargar nada.
 */
export function contrasenaDeLaDemo(
  url: string | undefined,
  propia: string | undefined,
): EleccionContrasena {
  if (!url) return { error: "falta DATABASE_URL" };
  if (propia) {
    if (propia === CONTRASENA_SEED_LOCAL) {
      return { error: "DEMO_CONTRASENA no puede ser la contraseña pública del seed" };
    }
    if (propia.length < LONGITUD_MINIMA_CONTRASENA_DEMO) {
      return {
        error: `DEMO_CONTRASENA debe tener al menos ${LONGITUD_MINIMA_CONTRASENA_DEMO} caracteres`,
      };
    }
    return { contrasena: propia, publica: false };
  }
  if (esServidorLocal(url)) return { contrasena: CONTRASENA_SEED_LOCAL, publica: true };
  return {
    error:
      "la base no es local: define DEMO_CONTRASENA para no publicar las cuentas con la contraseña del seed (npm run demo:cargar)",
  };
}

/** Por qué no se cargan los datos con `demo:cargar`, o `null` si se puede. */
export function motivoParaNoCargar(
  url: string | undefined,
  propia: string | undefined,
): string | null {
  if (!propia) return "falta DEMO_CONTRASENA: demo:cargar nunca usa la contraseña pública del seed";
  const eleccion = contrasenaDeLaDemo(url, propia);
  if ("error" in eleccion) return eleccion.error;
  if (esBaseDePruebas(url!)) return "es la base de las pruebas; npm test la gestiona sola";
  return null;
}

function main(): number {
  // DATABASE_URL tiene que venir del entorno: no se toma la de apps/api/.env
  // para no cargar por error la base local creyendo que es la de producción.
  const motivo = motivoParaNoCargar(process.env.DATABASE_URL, process.env.DEMO_CONTRASENA);
  if (motivo) {
    console.error(`No se cargaron los datos de demostración: ${motivo}.`);
    return 1;
  }
  // El resto de la configuración (la que exige src/config/env.ts al importar el
  // motor de matching) sale de apps/api/.env si existe; no pisa lo ya definido.
  const archivoEnv = join(RAIZ_API, ".env");
  if (existsSync(archivoEnv)) process.loadEnvFile(archivoEnv);

  console.log("Cargando los datos de demostración con la contraseña de DEMO_CONTRASENA…");
  execSync("npx tsx prisma/seed.ts", { cwd: RAIZ_API, stdio: "inherit", env: process.env });
  return 0;
}

if (typeof require !== "undefined" && require.main === module) {
  process.exitCode = main();
}
