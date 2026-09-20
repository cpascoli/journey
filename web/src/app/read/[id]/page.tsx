import Link from "next/link";

import { MediaGrid } from "@/app/MediaGrid";
import { entryForCurrentInvite } from "@/lib/reader/entries";

import { NoAccess } from "../NoAccess";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

function dayLabel(day: string): string {
  return new Intl.DateTimeFormat("en", { dateStyle: "long", timeZone: "UTC" })
    .format(new Date(`${day}T12:00:00Z`));
}

export default async function ReaderEntryPage({ params }: Params) {
  const id = (await params).id;
  const result = /^[0-9a-f-]{36}$/i.test(id)
    ? await entryForCurrentInvite(id)
    : ({ status: "none" } as const);
  if ("status" in result) return <NoAccess status={result.status} entry />;

  const { entry } = result;
  return (
    <main className="reader">
      <Link className="back-link" href="/read">← All entries</Link>
      <article className="entry-detail">
        <p className="eyebrow">Shared with {result.inviteName}</p>
        <p className="entry-meta">{dayLabel(entry.day)}{entry.place_name ? ` · ${entry.place_name}` : ""}</p>
        <h1>{entry.title || "Untitled entry"}</h1>
        <MediaGrid entryId={entry.id} media={entry.media} />
        {entry.text && <div className="entry-text">{entry.text}</div>}
      </article>
    </main>
  );
}
