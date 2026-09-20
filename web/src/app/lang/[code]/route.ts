import { NextResponse } from "next/server";

import { LANGUAGE_COOKIE, parseLanguage } from "@/lib/domain/language";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ code: string }> };

const ONE_YEAR = 60 * 60 * 24 * 365;

/**
 * Only a path on this site, so a crafted link cannot turn the language
 * switch into an open redirect. `//host` and `/\host` are protocol-relative
 * URLs, not paths.
 */
function safeDestination(next: string | null): string {
  if (!next || !next.startsWith("/")) return "/read";
  if (next.startsWith("//") || next.startsWith("/\\")) return "/read";
  return next;
}

/**
 * Remembers the reader's language and sends them back where they were.
 *
 * A plain link rather than a script, so the toggle works before any
 * JavaScript loads, and on a page that is otherwise entirely server-rendered.
 */
export async function GET(request: Request, { params }: Params) {
  const url = new URL(request.url);
  const language = parseLanguage((await params).code);
  const response = NextResponse.redirect(
    new URL(safeDestination(url.searchParams.get("next")), request.url),
    303,
  );
  response.headers.set("Cache-Control", "no-store");
  if (language) {
    response.cookies.set(LANGUAGE_COOKIE, language, {
      httpOnly: true,
      secure: true,
      sameSite: "lax",
      path: "/",
      maxAge: ONE_YEAR,
    });
  }
  return response;
}
