import type { Metadata } from "next";
import Link from "next/link";

import { entriesForCurrentInvite } from "@/lib/reader/entries";

import { MediaGrid } from "../MediaGrid";
import { NoAccess } from "./NoAccess";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Read · Journey" };

function dayLabel(day: string): string {
  return new Intl.DateTimeFormat("en", {
    dateStyle: "long",
    timeZone: "UTC",
  }).format(new Date(`${day}T12:00:00Z`));
}

type Props = { searchParams: Promise<{ before?: string }> };

export default async function ReadPage({ searchParams }: Props) {
  const before = (await searchParams).before;
  const journal = await entriesForCurrentInvite({ before });
  if ("status" in journal) return <NoAccess status={journal.status} />;

  return (
    <main className="reader">
      <header className="reader-header">
        <p className="eyebrow">Shared with {journal.inviteName}</p>
        <h1>Journey</h1>
      </header>
      {journal.entries.length === 0 ? (
        <p className="empty">
          {before ? "There are no older stories." : "There are no shared stories yet."}
        </p>
      ) : journal.entries.map((entry) => (
        <article className="entry-card" key={entry.id}>
          <p className="entry-meta">
            {dayLabel(entry.day)}
            {entry.place_name ? ` · ${entry.place_name}` : ""}
          </p>
          <h2><Link href={`/read/${entry.id}`}>{entry.title || "Untitled entry"}</Link></h2>
          <MediaGrid entryId={entry.id} media={entry.media} compact />
          {entry.text && <div className="entry-text excerpt">{entry.text}</div>}
        </article>
      ))}
      <nav className="reader-paging">
        {before && <Link href="/read">← Back to the newest</Link>}
        {journal.nextCursor && (
          <Link href={`/read?before=${encodeURIComponent(journal.nextCursor)}`}>
            Older entries →
          </Link>
        )}
      </nav>
    </main>
  );
}
