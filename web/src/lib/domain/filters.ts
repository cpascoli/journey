export const TIMEFRAMES = ["week", "month", "all"] as const;

export type Timeframe = (typeof TIMEFRAMES)[number];

export const DEFAULT_TIMEFRAME: Timeframe = "all";

export function parseTimeframe(value: string | null | undefined): Timeframe {
  return (TIMEFRAMES as readonly string[]).includes(value ?? "")
    ? (value as Timeframe)
    : DEFAULT_TIMEFRAME;
}

/** Longest a search box should accept; anything more is not a search. */
export const MAX_QUERY_LENGTH = 100;

export function parseQuery(value: string | null | undefined): string {
  return (value ?? "").trim().slice(0, MAX_QUERY_LENGTH);
}

/**
 * The earliest day a timeframe includes, as YYYY-MM-DD, or null for all time.
 * Entries are filtered on `day` — the calendar day as the writer saw it — so
 * the comparison stays in the same terms the journal is written in.
 */
export function timeframeStart(timeframe: Timeframe, now: Date): string | null {
  if (timeframe === "all") return null;
  const start = new Date(now);
  start.setUTCDate(start.getUTCDate() - (timeframe === "week" ? 7 : 30));
  return start.toISOString().slice(0, 10);
}

/**
 * Case- and accent-insensitive, so searching "citta" finds "città" and a
 * reader typing on an English keyboard can still find Italian entries.
 */
export function normalise(text: string): string {
  return text
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
}

/** Every word must appear somewhere, in any order. */
export function matchesQuery(haystacks: string[], query: string): boolean {
  const words = normalise(query).split(/\s+/).filter(Boolean);
  if (words.length === 0) return true;
  const hay = haystacks.map(normalise).join(" \u0000 ");
  return words.every((word) => hay.includes(word));
}

export type EntryTag = { id: string; name: string };

export type FilterableEntry = {
  day: string;
  tags: EntryTag[];
};

export type TagFacet = EntryTag & { count: number };

/**
 * The tags worth offering as filters: those on entries this reader can
 * actually see, each with how many of those entries carry it.
 *
 * Deriving them from the visible entries rather than from the tags table is
 * what keeps the sidebar from revealing that other tags exist. It also
 * satisfies "at least one post" by construction — a tag with no visible
 * entries cannot appear.
 */
export function tagFacets(entries: FilterableEntry[]): TagFacet[] {
  const counts = new Map<string, TagFacet>();
  for (const entry of entries) {
    for (const tag of entry.tags) {
      const existing = counts.get(tag.id);
      if (existing) existing.count += 1;
      else counts.set(tag.id, { ...tag, count: 1 });
    }
  }
  return [...counts.values()].sort(
    (left, right) => right.count - left.count || left.name.localeCompare(right.name),
  );
}

export type Filters = {
  tag: string | null;
  timeframe: Timeframe;
  query: string;
};

export function hasActiveFilters(filters: Filters): boolean {
  return filters.tag !== null || filters.timeframe !== DEFAULT_TIMEFRAME || filters.query !== "";
}

/**
 * Narrows what is shown. This is presentation, not authorization: the entries
 * passed in have already been decided by `entries_visible_to_invite`, and
 * nothing here can widen that set.
 *
 * `searchableText` yields the words to match, which the caller resolves in the
 * reader's language so a search matches what is actually on the page.
 */
export function filterEntries<T extends FilterableEntry>(
  entries: T[],
  filters: Filters,
  searchableText: (entry: T) => string[],
  now: Date,
): T[] {
  const since = timeframeStart(filters.timeframe, now);
  return entries.filter((entry) => {
    if (filters.tag && !entry.tags.some((tag) => tag.id === filters.tag)) return false;
    if (since && entry.day < since) return false;
    if (filters.query && !matchesQuery(searchableText(entry), filters.query)) return false;
    return true;
  });
}
