import Link from "next/link";

import { MediaGrid } from "@/app/MediaGrid";
import { SiteHeader } from "@/app/SiteHeader";
import { entryTextFor } from "@/lib/domain/language";
import { currentLanguage } from "@/lib/i18n/current";
import { formatDay, stringsFor } from "@/lib/i18n/strings";
import { entryForCurrentInvite } from "@/lib/reader/entries";

import { NoAccess } from "../NoAccess";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

export default async function ReaderEntryPage({ params }: Params) {
  const [{ id }, language] = await Promise.all([params, currentLanguage()]);
  const strings = stringsFor(language);
  const result = /^[0-9a-f-]{36}$/i.test(id)
    ? await entryForCurrentInvite(id)
    : ({ status: "none" } as const);
  if ("status" in result) return <NoAccess entry language={language} status={result.status} />;

  const { entry } = result;
  const { title, text } = entryTextFor(language, entry);
  return (
    <main className="reader">
      <SiteHeader
        eyebrow={strings.sharedWith(result.inviteName)}
        language={language}
        next={`/read/${entry.id}`}
      />
      <Link className="back-link" href="/read">← {strings.allEntries}</Link>
      <article className="entry-detail">
        <p className="entry-meta">
          {formatDay(entry.day, language)}
          {entry.place_name ? ` · ${entry.place_name}` : ""}
        </p>
        <h1>{title || strings.untitledEntry}</h1>
        <MediaGrid entryId={entry.id} language={language} media={entry.media} />
        {text && <div className="entry-text">{text}</div>}
      </article>
    </main>
  );
}
