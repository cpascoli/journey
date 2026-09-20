import { NextResponse } from "next/server";

import { INVITE_COOKIE, secureCookieOptions } from "@/lib/auth/session";
import { hashInviteToken } from "@/lib/owner/invites";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ token: string }> };

export async function GET(request: Request, { params }: Params) {
  const token = (await params).token;
  const destination = new URL("/read", request.url);
  const response = NextResponse.redirect(destination, 303);
  response.headers.set("Cache-Control", "no-store");
  response.headers.set("Referrer-Policy", "no-referrer");
  response.cookies.set(INVITE_COOKIE, "", secureCookieOptions("lax", 0));
  if (!/^[A-Za-z0-9_-]{32}$/.test(token)) return response;

  const db = adminClient();
  const { data, error } = await db
    .from("invites")
    .select("id")
    .eq("token_hash", hashInviteToken(token))
    .is("revoked_at", null)
    .maybeSingle();
  if (error || !data) return response;

  await db.from("invites").update({ last_seen_at: new Date().toISOString() }).eq("id", data.id);
  response.cookies.set(INVITE_COOKIE, token, secureCookieOptions("lax", 60 * 60 * 24 * 90));
  return response;
}

