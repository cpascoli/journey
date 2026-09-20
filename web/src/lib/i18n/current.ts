import { cookies, headers } from "next/headers";

import { LANGUAGE_COOKIE, resolveLanguage, type Language } from "@/lib/domain/language";

/**
 * The language to render in: the reader's saved choice if they have made one,
 * otherwise what their browser asks for.
 */
export async function currentLanguage(): Promise<Language> {
  const [cookieStore, requestHeaders] = await Promise.all([cookies(), headers()]);
  return resolveLanguage(
    cookieStore.get(LANGUAGE_COOKIE)?.value,
    requestHeaders.get("accept-language"),
  );
}
