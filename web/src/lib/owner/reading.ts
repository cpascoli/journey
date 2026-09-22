import type { SupabaseClient } from "@supabase/supabase-js";

import type { EntryDay } from "@/lib/domain/days";
import { readerText } from "@/lib/domain/reader";
import { groupMediaRows, MEDIA_COLUMNS, type ReaderMedia } from "@/lib/reader/media-rows";

export type OwnerEntry = {
  id: string;
  journal_name: string;
  day: string;
  title: string;
  text: string;
  place_name: string | null;
  visibility: "private" | "shared";
  media: ReaderMedia[];
};

type OwnerEntryRow = Omit<OwnerEntry, "text" | "media"> & {
  narrative: string;
  notes: string;
};

const ENTRY_COLUMNS = "id, day, title, journal_name, visibility, place_name, narrative, notes";

/**
 * Which days have something published, with how many entries each.
 *
 * The dashboard used to load every entry and every photo at once, which grows
 * without bound as the journal does. This reads one small row per day and no
 * media at all; the entries and their pictures are fetched only for the day
 * actually opened.
 */
export async function ownerEntryDays(db: SupabaseClient): Promise<EntryDay[]> {
  const { data, error } = await db
    .from("entries")
    .select("day")
    .order("day", { ascending: false });
  if (error) throw new Error("Could not load published days.");

  const counts = new Map<string, number>();
  for (const row of (data ?? []) as { day: string }[]) {
    counts.set(row.day, (counts.get(row.day) ?? 0) + 1);
  }
  return [...counts.entries()].map(([day, count]) => ({ day, count }));
}

async function withMedia(db: SupabaseClient, rows: OwnerEntryRow[]): Promise<OwnerEntry[]> {
  const mediaByEntry = new Map<string, ReaderMedia[]>();
  if (rows.length > 0) {
    const { data, error } = await db
      .from("entry_media")
      .select(MEDIA_COLUMNS)
      .in("entry_id", rows.map((row) => row.id))
      .order("sort_order");
    if (error) throw new Error("Could not load published entries.");
    for (const [entryId, items] of groupMediaRows(data ?? [])) {
      mediaByEntry.set(entryId, items);
    }
  }
  return rows.map(({ narrative, notes, ...entry }) => ({
    ...entry,
    text: readerText(narrative, notes),
    media: mediaByEntry.get(entry.id) ?? [],
  }));
}

/** One day's entries, with their media. */
export async function ownerEntriesForDay(
  db: SupabaseClient,
  day: string,
): Promise<OwnerEntry[]> {
  const { data, error } = await db
    .from("entries")
    .select(ENTRY_COLUMNS)
    .eq("day", day)
    .order("occurred_at");
  if (error) throw new Error("Could not load published entries.");
  return withMedia(db, (data ?? []) as OwnerEntryRow[]);
}

/** One entry, fetched by id rather than by filtering everything published. */
export async function ownerEntry(db: SupabaseClient, id: string): Promise<OwnerEntry | null> {
  const { data, error } = await db
    .from("entries")
    .select(ENTRY_COLUMNS)
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error("Could not load the entry.");
  if (!data) return null;
  const [entry] = await withMedia(db, [data as OwnerEntryRow]);
  return entry ?? null;
}
