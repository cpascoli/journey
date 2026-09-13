import { validationError } from "./errors";

export type JsonObject = Record<string, unknown>;

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE = /^\d{4}-\d{2}-\d{2}$/;
const DATE_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;

function fail(field: string, message: string): never {
  throw validationError(`${field} ${message}`, { field });
}

export function asObject(value: unknown, field = "body"): JsonObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    fail(field, "must be a JSON object.");
  }
  return value as JsonObject;
}

export function parseUuid(value: unknown, field: string): string {
  if (typeof value !== "string" || !UUID.test(value)) fail(field, "must be a UUID.");
  return value.toLowerCase();
}

export function stringField(
  obj: JsonObject,
  key: string,
  opts: { max: number; required?: boolean; fallback?: string },
): string {
  const value = obj[key];
  if (value === undefined || value === null) {
    if (opts.required) fail(key, "is required.");
    return opts.fallback ?? "";
  }
  if (typeof value !== "string") fail(key, "must be a string.");
  if (value.length > opts.max) fail(key, `must be at most ${opts.max} characters.`);
  if (opts.required && value.trim().length === 0) fail(key, "must not be empty.");
  return value;
}

/** A trimmed string, or null when missing or blank. */
export function nullableString(obj: JsonObject, key: string, opts: { max: number }): string | null {
  const value = obj[key];
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") fail(key, "must be a string.");
  const trimmed = value.trim();
  if (trimmed.length > opts.max) fail(key, `must be at most ${opts.max} characters.`);
  return trimmed.length > 0 ? trimmed : null;
}

export function enumField<T extends string>(
  obj: JsonObject,
  key: string,
  allowed: readonly T[],
  fallback?: T,
): T {
  const value = obj[key];
  if ((value === undefined || value === null) && fallback !== undefined) return fallback;
  if (typeof value !== "string" || !(allowed as readonly string[]).includes(value)) {
    fail(key, `must be one of: ${allowed.join(", ")}.`);
  }
  return value as T;
}

export function dateTimeField(obj: JsonObject, key: string): string {
  const value = obj[key];
  if (typeof value !== "string" || !DATE_TIME.test(value) || Number.isNaN(Date.parse(value))) {
    fail(key, "must be an ISO 8601 date-time, e.g. 2026-09-11T09:00:00Z.");
  }
  return new Date(value).toISOString();
}

export function dateField(obj: JsonObject, key: string): string {
  const value = obj[key];
  if (typeof value !== "string" || !DATE.test(value)) fail(key, "must be a date as YYYY-MM-DD.");
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    fail(key, "must be a real calendar date.");
  }
  return value;
}

export function uuidArrayField(obj: JsonObject, key: string, opts: { max: number }): string[] {
  const value = obj[key];
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) fail(key, "must be an array of UUIDs.");
  if (value.length > opts.max) fail(key, `must have at most ${opts.max} items.`);
  return [...new Set(value.map((item, index) => parseUuid(item, `${key}[${index}]`)))];
}

export function numberField(
  obj: JsonObject,
  key: string,
  opts: { min: number; max: number },
): number | null {
  const value = obj[key];
  if (value === undefined || value === null) return null;
  if (typeof value !== "number" || !Number.isFinite(value) || value < opts.min || value > opts.max) {
    fail(key, `must be a number between ${opts.min} and ${opts.max}.`);
  }
  return value;
}

/** An optional whole number from a query string. */
export function queryInteger(
  params: URLSearchParams,
  key: string,
  opts: { min: number; max: number },
): number | null {
  const raw = params.get(key);
  if (raw === null || raw === "") return null;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < opts.min || value > opts.max) {
    fail(key, `must be a whole number between ${opts.min} and ${opts.max}.`);
  }
  return value;
}
