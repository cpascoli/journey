/** A day that has at least one published entry. */
export type EntryDay = { day: string; count: number };

export type DayMonth = {
  /** "2026-09" — the key, not for display. */
  month: string;
  days: EntryDay[];
  count: number;
};

/**
 * Days grouped by the month they fall in, newest month first and newest day
 * first within it.
 *
 * The dashboard shows only days that have something on them, so a journal
 * with a year of gaps stays short rather than rendering empty cells.
 */
export function groupDaysByMonth(days: EntryDay[]): DayMonth[] {
  const byMonth = new Map<string, EntryDay[]>();
  for (const entry of days) {
    const month = entry.day.slice(0, 7);
    byMonth.set(month, [...(byMonth.get(month) ?? []), entry]);
  }
  return [...byMonth.entries()]
    .map(([month, entries]) => ({
      month,
      days: [...entries].sort((left, right) => right.day.localeCompare(left.day)),
      count: entries.reduce((sum, entry) => sum + entry.count, 0),
    }))
    .sort((left, right) => right.month.localeCompare(left.month));
}

/** The day number, for a compact chip: "2026-09-12" → "12". */
export function dayOfMonth(day: string): string {
  return String(Number(day.slice(8, 10)));
}
