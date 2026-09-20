import type { SupabaseClient } from "@supabase/supabase-js";

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

export async function ownerEntries(db: SupabaseClient): Promise<OwnerEntry[]> {
  const { data, error } = await db
    .from("entries")
    .select("id, day, title, journal_name, visibility, place_name, narrative, notes")
    .order("day", { ascending: false });
  if (error) throw new Error("Could not load owner entries.");
  const rows = (data ?? []) as OwnerEntryRow[];
  const mediaByEntry = new Map<string, ReaderMedia[]>();
  if (rows.length > 0) {
    const { data: media, error: mediaError } = await db
      .from("entry_media")
      .select(MEDIA_COLUMNS)
      .in("entry_id", rows.map((row) => row.id))
      .order("sort_order");
    if (mediaError) throw new Error("Could not load owner entries.");
    for (const [entryId, items] of groupMediaRows(media ?? [])) {
      mediaByEntry.set(entryId, items);
    }
  }
  return rows.map(({ narrative, notes, ...entry }) => ({
    ...entry,
    text: readerText(narrative, notes),
    media: mediaByEntry.get(entry.id) ?? [],
  }));
}

export async function ownerEntry(db: SupabaseClient, id: string): Promise<OwnerEntry | null> {
  return (await ownerEntries(db)).find((entry) => entry.id === id) ?? null;
}
