import { cookies } from "next/headers";

import { currentOwner } from "@/lib/auth/access";
import { INVITE_COOKIE } from "@/lib/auth/session";
import { serveMedia, supabaseMediaReadServices } from "@/lib/reader/media";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ entryId: string; key: string }> };

export async function GET(_request: Request, { params }: Params): Promise<Response> {
  const [{ entryId, key }, owner, cookieStore] = await Promise.all([
    params,
    currentOwner(),
    cookies(),
  ]);
  return serveMedia(
    {
      owner: owner !== null,
      inviteToken: cookieStore.get(INVITE_COOKIE)?.value,
      entryId,
      key,
    },
    supabaseMediaReadServices(adminClient()),
  );
}
