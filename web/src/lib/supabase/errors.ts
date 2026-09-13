import { ApiError } from "@/lib/api/errors";

export const FOREIGN_KEY_VIOLATION = "23503";

export type DbError = { code?: string; message: string };

/** Logs a database error and returns a generic one: raw messages can expose the schema. */
export function dbFailure(error: DbError, context: string): ApiError {
  console.error(`Database error (${context})`, error.code, error.message);
  return new ApiError(500, "DATABASE_ERROR", "The database rejected the request.");
}
