import { cookies } from "next/headers";

import { INVITE_COOKIE } from "@/lib/auth/session";
import type { TranslatableEntry } from "@/lib/domain/language";
import { hashInviteToken } from "@/lib/owner/invites";
import { adminClient } from "@/lib/supabase/admin";

import { groupMediaRows, MEDIA_COLUMNS, type ReaderMedia } from "./media-rows";

export type { ReaderMedia };

/**
 * Entries keep their original and translated text rather than one resolved
 * string: which one a reader sees depends on the language they chose, and
 * that is decided at render time by `entryTextFor`.
 */
export type ReaderEntry = TranslatableEntry & {
  id: string;
  journal_name: string;
  day: string;
  place_name: string | null;
  mediaCount: number;
  media: ReaderMedia[];
};

type EntryRow = Omit<ReaderEntry, "mediaCount" | "media">;

/**
 * A revoked invite is told apart from a link that was never valid. Both see
 * nothing, but showing the same message for each makes a deliberate
 * revocation look like a broken link to the person who received it.
 */
export type NoReaderAccess = { status: "none" } | { status: "revoked" };

export type ReaderAccess = NoReaderAccess | { status: "ok"; inviteId: string; inviteName: string };

/** Entries per page. The reader is a phone-first page of photos and clips. */
export const READER_PAGE_SIZE = 20;

export type ReaderPage = {
  inviteName: string;
  entries: ReaderEntry[];
  /** Opaque cursor to pass as `before` for the next page, or null at the end. */
  nextCursor: string | null;
};

export async function currentInvite(): Promise<ReaderAccess> {
  const token = (await cookies()).get(INVITE_COOKIE)?.value;
  if (!token || !/^[A-Za-z0-9_-]{32}$/.test(token)) return { status: "none" };

  const { data: invite, error } = await adminClient()
    .from("invites")
    .select("id, name, revoked_at")
    .eq("token_hash", hashInviteToken(token))
    .maybeSingle();
  if (error || !invite) return { status: "none" };
  if (invite.revoked_at) return { status: "revoked" };
  return { status: "ok", inviteId: invite.id as string, inviteName: invite.name as string };
}

async function visibleEntries(inviteId: string): Promise<EntryRow[]> {
  const { data, error } = await adminClient().rpc("entries_visible_to_invite", {
    p_invite_id: inviteId,
  });
  if (error) throw new Error("Could not load shared entries.");
  // Newest first, with the id breaking ties so paging is stable within a day.
  return (data as EntryRow[]).sort(
    (left, right) => right.day.localeCompare(left.day) || right.id.localeCompare(left.id),
  );
}

async function withMedia(rows: EntryRow[]): Promise<ReaderEntry[]> {
  const mediaByEntry = new Map<string, ReaderMedia[]>();
  if (rows.length > 0) {
    const { data: media, error } = await adminClient()
      .from("entry_media")
      .select(MEDIA_COLUMNS)
      .in("entry_id", rows.map((row) => row.id))
      .order("sort_order");
    if (error) throw new Error("Could not load shared entries.");
    for (const [entryId, items] of groupMediaRows(media ?? [])) {
      mediaByEntry.set(entryId, items);
    }
  }
  return rows.map((row) => ({
    ...row,
    mediaCount: mediaByEntry.get(row.id)?.length ?? 0,
    media: mediaByEntry.get(row.id) ?? [],
  }));
}

/** Records that the invite was used, at most once an hour rather than per request. */
async function noteVisit(inviteId: string): Promise<void> {
  const { error } = await adminClient().rpc("touch_invite_seen", { p_invite_id: inviteId });
  // A missed visit timestamp must never stop someone reading.
  if (error) console.error("Could not record an invite visit", error.code);
}

/**
 * The cursor names an exact entry, not just a day. A day-only cursor would
 * skip entries when several share a day and the page boundary falls between
 * them. If that entry has since gone, fall back to the first older day.
 */
export function pageStart(rows: { id: string; day: string }[], cursor?: string): number {
  if (!cursor) return 0;
  const separator = cursor.indexOf("_");
  if (separator < 0) return 0;
  const day = cursor.slice(0, separator);
  const id = cursor.slice(separator + 1);

  const exact = rows.findIndex((row) => row.id === id && row.day === day);
  if (exact >= 0) return exact + 1;
  const older = rows.findIndex((row) => row.day.localeCompare(day) < 0);
  return older < 0 ? rows.length : older;
}

export async function entriesForCurrentInvite(
  options: { before?: string } = {},
): Promise<ReaderPage | NoReaderAccess> {
  const access = await currentInvite();
  if (access.status !== "ok") return access;
  await noteVisit(access.inviteId);

  const all = await visibleEntries(access.inviteId);
  const from = pageStart(all, options.before);
  const page = all.slice(from, from + READER_PAGE_SIZE);
  const last = page[page.length - 1];
  const remaining = all.length > from + page.length;

  return {
    inviteName: access.inviteName,
    entries: await withMedia(page),
    nextCursor: remaining && last ? `${last.day}_${last.id}` : null,
  };
}

export async function entryForCurrentInvite(
  id: string,
): Promise<{ inviteName: string; entry: ReaderEntry } | NoReaderAccess> {
  const access = await currentInvite();
  if (access.status !== "ok") return access;
  await noteVisit(access.inviteId);

  // Authorization stays in entries_visible_to_invite: an entry is readable
  // only if it comes back from that function for this invite.
  const row = (await visibleEntries(access.inviteId)).find((candidate) => candidate.id === id);
  if (!row) return { status: "none" };
  const [entry] = await withMedia([row]);
  return entry ? { inviteName: access.inviteName, entry } : { status: "none" };
}
