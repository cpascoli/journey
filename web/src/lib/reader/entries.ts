import { cookies } from "next/headers";

import { INVITE_COOKIE } from "@/lib/auth/session";
import {
  filterEntries,
  tagFacets,
  type EntryTag,
  type Filters,
  type TagFacet,
} from "@/lib/domain/filters";
import { entryTextFor, type Language, type TranslatableEntry } from "@/lib/domain/language";
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
  /** Only the tags of entries this invite may read; see `tagFacets`. */
  tags: EntryTag[];
};

type EntryRow = Omit<ReaderEntry, "mediaCount" | "media" | "tags"> & { tags: EntryTag[] };

/**
 * A revoked invite is told apart from a link that was never valid. Both see
 * nothing, but showing the same message for each makes a deliberate
 * revocation look like a broken link to the person who received it.
 */
export type NoReaderAccess = { status: "none" } | { status: "revoked" };

export type ReaderAccess = NoReaderAccess | { status: "ok"; inviteId: string; inviteName: string };

/**
 * Entries per page. Ten rather than twenty because each entry carries a grid
 * of thumbnails: twenty was more than a phone should fetch at once, and with
 * a journal this size the pager never appeared at all.
 */
export const READER_PAGE_SIZE = 10;

export type ReaderPage = {
  inviteName: string;
  entries: ReaderEntry[];
  /** Opaque cursor to pass as `before` for the next page, or null at the end. */
  nextCursor: string | null;
  /** Tags worth offering as filters, drawn only from what this invite sees. */
  facets: TagFacet[];
  /** How many entries the filters matched, and how many there are in total. */
  matching: number;
  total: number;
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
  const db = adminClient();
  const { data, error } = await db.rpc("entries_visible_to_invite", {
    p_invite_id: inviteId,
  });
  if (error) throw new Error("Could not load shared entries.");
  // Newest first, with the id breaking ties so paging is stable within a day.
  const rows = (data as EntryRow[]).sort(
    (left, right) => right.day.localeCompare(left.day) || right.id.localeCompare(left.id),
  );
  if (rows.length === 0) return rows;

  // Tags of entries this invite can already read. Reading them per entry
  // rather than listing the tags table is what stops a tag the reader has no
  // access to appearing in the filters.
  const { data: tagRows, error: tagError } = await db
    .from("entry_tags")
    .select("entry_id, tags(id, name)")
    .in("entry_id", rows.map((row) => row.id));
  if (tagError) throw new Error("Could not load shared entries.");

  const byEntry = new Map<string, EntryTag[]>();
  for (const row of (tagRows ?? []) as { entry_id: string; tags: EntryTag | EntryTag[] | null }[]) {
    if (!row.tags) continue;
    const tag = Array.isArray(row.tags) ? row.tags[0] : row.tags;
    if (!tag) continue;
    byEntry.set(row.entry_id, [...(byEntry.get(row.entry_id) ?? []), tag]);
  }
  for (const row of rows) {
    row.tags = (byEntry.get(row.id) ?? []).sort((left, right) => left.name.localeCompare(right.name));
  }
  return rows;
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
  options: { before?: string; filters?: Filters; language?: Language } = {},
): Promise<ReaderPage | NoReaderAccess> {
  const access = await currentInvite();
  if (access.status !== "ok") return access;
  await noteVisit(access.inviteId);

  const all = await visibleEntries(access.inviteId);
  // Facets come from everything the invite can see, not from the filtered
  // set, so choosing one tag does not make the others disappear.
  const facets = tagFacets(all);

  const filters = options.filters;
  const language = options.language ?? "en";
  const matched = filters
    ? filterEntries(
        all,
        filters,
        // Search what the reader actually sees, in their language.
        (entry) => {
          const { title, text } = entryTextFor(language, entry);
          return [title, text, entry.place_name ?? "", ...entry.tags.map((tag) => tag.name)];
        },
        new Date(),
      )
    : all;

  const from = pageStart(matched, options.before);
  const page = matched.slice(from, from + READER_PAGE_SIZE);
  const last = page[page.length - 1];
  const remaining = matched.length > from + page.length;

  return {
    inviteName: access.inviteName,
    entries: await withMedia(page),
    nextCursor: remaining && last ? `${last.day}_${last.id}` : null,
    facets,
    matching: matched.length,
    total: all.length,
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
