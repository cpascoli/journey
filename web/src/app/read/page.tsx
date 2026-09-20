import type { Metadata } from "next";
import Link from "next/link";

import { entryTextFor } from "@/lib/domain/language";
import { currentLanguage } from "@/lib/i18n/current";
import { formatDay, stringsFor } from "@/lib/i18n/strings";
import { entriesForCurrentInvite } from "@/lib/reader/entries";

import { MediaGrid } from "../MediaGrid";
import { SiteHeader } from "../SiteHeader";
import { NoAccess } from "./NoAccess";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Read · Journey" };

type Props = { searchParams: Promise<{ before?: string }> };

export default async function ReadPage({ searchParams }: Props) {
  const [{ before }, language] = await Promise.all([searchParams, currentLanguage()]);
  const journal = await entriesForCurrentInvite({ before });
  const strings = stringsFor(language);
  if ("status" in journal) return <NoAccess language={language} status={journal.status} />;

  const here = before ? `/read?before=${encodeURIComponent(before)}` : "/read";
  return (
    <main className="reader">
      <SiteHeader
        eyebrow={strings.sharedWith(journal.inviteName)}
        language={language}
        next={here}
        title={strings.siteName}
      />
      {journal.entries.length === 0 ? (
        <p className="empty">{before ? strings.noOlderStories : strings.noStories}</p>
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
        {before && <Link href="/read">← {strings.backToNewest}</Link>}
        {journal.nextCursor && (
          <Link href={`/read?before=${encodeURIComponent(journal.nextCursor)}`}>
            {strings.olderEntries} →
          </Link>
        )}
      </nav>
    </main>
  );
}
