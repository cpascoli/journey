import Link from "next/link";

import {
  DEFAULT_TIMEFRAME,
  hasActiveFilters,
  MAX_QUERY_LENGTH,
  TIMEFRAMES,
  type Filters,
  type TagFacet,
  type Timeframe,
} from "@/lib/domain/filters";
import type { Language } from "@/lib/domain/language";
import { stringsFor } from "@/lib/i18n/strings";

/**
 * Changing a filter always returns to the first page: `before` is a cursor
 * into the filtered list, so carrying it across a change would land the reader
 * somewhere arbitrary.
 */
function href(filters: Filters, change: Partial<Filters>): string {
  const next = { ...filters, ...change };
  const params = new URLSearchParams();
  if (next.tag) params.set("tag", next.tag);
  if (next.timeframe !== DEFAULT_TIMEFRAME) params.set("since", next.timeframe);
  if (next.query) params.set("q", next.query);
  const query = params.toString();
  return query ? `/read?${query}` : "/read";
}

/**
 * Filters for the journal: by tag, by how recent, and by words.
 *
 * Every control is a link or a GET form, so the whole thing works with
 * JavaScript off and each filtered view has its own shareable URL. The tags
 * offered are only those on entries this invite can read — see `tagFacets`.
 */
export function FilterPanel({
  language,
  filters,
  facets,
  matching,
  total,
}: {
  language: Language;
  filters: Filters;
  facets: TagFacet[];
  matching: number;
  total: number;
}) {
  const strings = stringsFor(language);
  const timeframeLabel: Record<Timeframe, string> = {
    week: strings.lastWeek,
    month: strings.lastMonth,
    all: strings.allTime,
  };

  return (
    <aside className="filters" aria-label={strings.filters}>
      <form action="/read" className="filter-search" method="get" role="search">
        {/* Keeps the other filters when a search is submitted. */}
        {filters.tag && <input name="tag" type="hidden" value={filters.tag} />}
        {filters.timeframe !== DEFAULT_TIMEFRAME && (
          <input name="since" type="hidden" value={filters.timeframe} />
        )}
        <label className="visually-hidden" htmlFor="q">{strings.search}</label>
        <input
          autoComplete="off"
          defaultValue={filters.query}
          id="q"
          maxLength={MAX_QUERY_LENGTH}
          name="q"
          placeholder={strings.searchPlaceholder}
          type="search"
        />
        <button type="submit">{strings.searchAction}</button>
      </form>

      <div className="filter-group">
        <h2>{strings.when}</h2>
        <div className="chips">
          {TIMEFRAMES.map((timeframe) => (
            <Link
              aria-current={filters.timeframe === timeframe ? "true" : undefined}
              className={`chip${filters.timeframe === timeframe ? " current" : ""}`}
              href={href(filters, { timeframe })}
              key={timeframe}
            >
              {timeframeLabel[timeframe]}
            </Link>
          ))}
        </div>
      </div>

      {facets.length > 0 && (
        <div className="filter-group">
          <h2>{strings.filters}</h2>
          <div className="chips">
            <Link
              aria-current={filters.tag === null ? "true" : undefined}
              className={`chip${filters.tag === null ? " current" : ""}`}
              href={href(filters, { tag: null })}
            >
              {strings.allTags}
            </Link>
            {facets.map((facet) => (
              <Link
                aria-current={filters.tag === facet.id ? "true" : undefined}
                className={`chip${filters.tag === facet.id ? " current" : ""}`}
                href={href(filters, { tag: facet.id })}
                key={facet.id}
              >
                {facet.name} <span className="count">{facet.count}</span>
              </Link>
            ))}
          </div>
        </div>
      )}

      <p className="filter-count">
        {strings.showingCount(matching, total)}
        {hasActiveFilters(filters) && (
          <>
            {" · "}
            <Link href="/read">{strings.clearFilters}</Link>
          </>
        )}
      </p>
    </aside>
  );
}
