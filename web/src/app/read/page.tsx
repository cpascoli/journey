import type { Metadata } from "next";
import Link from "next/link";

import { parseQuery, parseTimeframe, type Filters } from "@/lib/domain/filters";
import { entryTextFor } from "@/lib/domain/language";
import { currentLanguage } from "@/lib/i18n/current";
import { formatDay, stringsFor } from "@/lib/i18n/strings";
import { entriesForCurrentInvite } from "@/lib/reader/entries";

import { MediaGrid } from "../MediaGrid";
import { SiteHeader } from "../SiteHeader";
import { FilterPanel } from "./FilterPanel";
import { NoAccess } from "./NoAccess";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Read · Journey" };

type Props = {
  searchParams: Promise<{ before?: string; tag?: string; since?: string; q?: string }>;
};

/** Keeps the reader's filters when they page to older entries. */
function pagingHref(filters: Filters, cursor: string | null): string {
  const params = new URLSearchParams();
  if (filters.tag) params.set("tag", filters.tag);
  if (filters.timeframe !== "all") params.set("since", filters.timeframe);
  if (filters.query) params.set("q", filters.query);
  if (cursor) params.set("before", cursor);
  const query = params.toString();
  return query ? `/read?${query}` : "/read";
}

export default async function ReadPage({ searchParams }: Props) {
  const [params, language] = await Promise.all([searchParams, currentLanguage()]);
  const filters: Filters = {
    // A tag id from the URL is only ever compared against the tags of entries
    // this invite can read, so an unknown or invented id simply matches none.
    tag: params.tag?.trim() || null,
    timeframe: parseTimeframe(params.since),
    query: parseQuery(params.q),
  };
  const journal = await entriesForCurrentInvite({ before: params.before, filters, language });
  const strings = stringsFor(language);
  if ("status" in journal) return <NoAccess language={language} status={journal.status} />;

  const empty = journal.total === 0
    ? strings.noStories
    : journal.matching === 0
      ? strings.noMatches
      : strings.noOlderStories;

  return (
    <main className="reader wide">
      <SiteHeader
        eyebrow={strings.sharedWith(journal.inviteName)}
        language={language}
        next={pagingHref(filters, params.before ?? null)}
        title={strings.siteName}
      />
      <div className="reader-layout">
        <FilterPanel
          facets={journal.facets}
          filters={filters}
          language={language}
          matching={journal.matching}
          total={journal.total}
        />
        <div className="reader-entries">
          {journal.entries.length === 0 ? (
            <p className="empty">{empty}</p>
          ) : journal.entries.map((entry) => {
            const { title, text } = entryTextFor(language, entry);
            return (
              <article className="entry-card" key={entry.id}>
                <p className="entry-meta">
                  {formatDay(entry.day, language)}
                  {entry.place_name ? ` · ${entry.place_name}` : ""}
                </p>
                <h2><Link href={`/read/${entry.id}`}>{title || strings.untitledEntry}</Link></h2>
                <MediaGrid compact entryId={entry.id} language={language} media={entry.media} />
                {text && <div className="entry-text excerpt">{text}</div>}
              </article>
            );
          })}
          <nav className="reader-paging">
            {params.before && <Link href={pagingHref(filters, null)}>← {strings.backToNewest}</Link>}
            {journal.nextCursor && (
              <Link href={pagingHref(filters, journal.nextCursor)}>{strings.olderEntries} →</Link>
            )}
          </nav>
        </div>
      </div>
    </main>
  );
}
