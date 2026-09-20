#!/usr/bin/env node
import { readdir } from "node:fs/promises";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const databaseUrl = process.env.LOCAL_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const parsed = new URL(databaseUrl);
if (parsed.protocol !== "postgresql:" && parsed.protocol !== "postgres:") {
  console.error("LOCAL_DB_URL must be a PostgreSQL URL.");
  process.exit(2);
}
if (!["localhost", "127.0.0.1", "::1", "[::1]"].includes(parsed.hostname)) {
  console.error("SQL integration tests only run against a localhost database.");
  process.exit(2);
}

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const testsDirectory = path.resolve(scriptDirectory, "../supabase/tests");
const files = (await readdir(testsDirectory))
  .filter((file) => file.endsWith(".sql"))
  .sort();
if (files.length === 0) {
  console.error(`No SQL tests found in ${testsDirectory}.`);
  process.exit(2);
}

const database = decodeURIComponent(parsed.pathname.slice(1)) || "postgres";
const pgEnvironment = {
  ...process.env,
  PGHOST: parsed.hostname.replace(/^\[|\]$/g, ""),
  PGPORT: parsed.port || "5432",
  PGUSER: decodeURIComponent(parsed.username),
  PGPASSWORD: decodeURIComponent(parsed.password),
  PGDATABASE: database,
};

for (const file of files) {
  console.log(`\n==> ${file}`);
  const status = await new Promise((resolve, reject) => {
    const child = spawn(
      "psql",
      ["-X", "-v", "ON_ERROR_STOP=1", "-f", path.join(testsDirectory, file)],
      { env: pgEnvironment, stdio: "inherit" },
    );
    child.on("error", reject);
    child.on("exit", (code, signal) => resolve(signal ? 1 : (code ?? 1)));
  }).catch((error) => {
    console.error(`Could not run psql: ${error.message}`);
    return 127;
  });
  if (status !== 0) process.exit(status);
}

console.log(`\nAll ${files.length} SQL test files passed.`);
