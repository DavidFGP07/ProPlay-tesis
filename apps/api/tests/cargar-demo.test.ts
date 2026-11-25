import { describe, expect, it } from "vitest";
import {
  CONTRASENA_SEED_LOCAL,
  contrasenaDeLaDemo,
  motivoParaNoCargar,
} from "../scripts/cargar-demo";

/**
 * Las cuentas de demostración nunca llegan a una base que no es local con la
 * contraseña pública del seed (npm run demo:cargar, db:seed).
 */
const LOCAL = "postgresql://u:p@localhost:5432/proplay";
const AZURE = "postgresql://u:p@proplay-db.postgres.database.azure.com:5432/proplay?sslmode=require";
const PROPIA = "una-contrasena-larga-de-prueba";

describe("contraseña de la demostración", () => {
  it("en local, sin DEMO_CONTRASENA, usa la pública del seed", () => {
    expect(contrasenaDeLaDemo(LOCAL, undefined)).toEqual({
      contrasena: CONTRASENA_SEED_LOCAL,
      publica: true,
    });
  });

  it("fuera de local exige DEMO_CONTRASENA", () => {
    expect(contrasenaDeLaDemo(AZURE, undefined)).toMatchObject({ error: expect.stringMatching(/no es local/) });
    expect(contrasenaDeLaDemo(AZURE, "")).toMatchObject({ error: expect.stringMatching(/no es local/) });
    expect(contrasenaDeLaDemo(AZURE, PROPIA)).toEqual({ contrasena: PROPIA, publica: false });
  });

  it("rechaza la contraseña pública y las cortas aunque se pidan", () => {
    expect(contrasenaDeLaDemo(AZURE, CONTRASENA_SEED_LOCAL)).toMatchObject({
      error: expect.stringMatching(/pública/),
    });
    expect(contrasenaDeLaDemo(LOCAL, "corta")).toMatchObject({ error: expect.stringMatching(/12/) });
  });

  it("sin URL no carga nada", () => {
    expect(contrasenaDeLaDemo(undefined, PROPIA)).toMatchObject({ error: expect.stringMatching(/DATABASE_URL/) });
  });
});

describe("guarda de demo:cargar", () => {
  it("exige DEMO_CONTRASENA incluso en local", () => {
    expect(motivoParaNoCargar(LOCAL, undefined)).toMatch(/DEMO_CONTRASENA/);
    expect(motivoParaNoCargar(LOCAL, PROPIA)).toBeNull();
    expect(motivoParaNoCargar(AZURE, PROPIA)).toBeNull();
  });

  it("se niega contra la base de las pruebas", () => {
    expect(motivoParaNoCargar("postgresql://u:p@localhost:5432/proplay_test", PROPIA)).toMatch(
      /base de las pruebas/,
    );
  });
});
