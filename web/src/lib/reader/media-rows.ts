export type ReaderMedia = {
  key: string;
  kind: "photo" | "video";
  width: number | null;
  height: number | null;
  durationSeconds: number | null;
};

/** Selected by both the reader and the owner dashboard, which render the same grid. */
export const MEDIA_COLUMNS = "entry_id, asset_key, kind, width, height, duration_seconds, sort_order";

type MediaRow = {
  entry_id: string;
  asset_key: string;
  kind: "photo" | "video";
  width: number | null;
  height: number | null;
  duration_seconds: number | string | null;
};

/** Rows must already be ordered by `sort_order`: that ordering is the entry's. */
export function groupMediaRows(rows: unknown[]): Map<string, ReaderMedia[]> {
  const byEntry = new Map<string, ReaderMedia[]>();
  for (const row of rows as MediaRow[]) {
    const items = byEntry.get(row.entry_id) ?? [];
    items.push({
      key: row.asset_key,
      kind: row.kind,
      width: row.width,
      height: row.height,
      // A numeric column arrives from PostgREST as a string.
      durationSeconds: row.duration_seconds === null ? null : Number(row.duration_seconds),
    });
    byEntry.set(row.entry_id, items);
  }
  return byEntry;
}
