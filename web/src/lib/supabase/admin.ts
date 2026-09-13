import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { ApiError } from "@/lib/api/errors";

let cached: SupabaseClient | null = null;

/**
 * Server-only client with the service-role key. It bypasses row-level
 * security, so it must never be imported into client components.
 */
export function adminClient(): SupabaseClient {
  if (cached) return cached;
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new ApiError(500, "CONFIG", "Supabase is not configured on the server.");
  }
  cached = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return cached;
}

export const MEDIA_BUCKET = "media";
