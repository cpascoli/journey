import Link from "next/link";

import { MediaGrid } from "@/app/MediaGrid";
import { SiteFooter } from "@/app/SiteFooter";
import { SiteHeader } from "@/app/SiteHeader";
import { entryTextFor } from "@/lib/domain/language";
import { currentLanguage } from "@/lib/i18n/current";
import { formatDay, stringsFor } from "@/lib/i18n/strings";
import { threadForCurrentInvite } from "@/lib/reader/comments";
import { entryForCurrentInvite } from "@/lib/reader/entries";

import { NoAccess } from "../NoAccess";
import { CommentThread } from "./CommentThread";

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
  const comments = await threadForCurrentInvite(entry.id);
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
        {/* The story first: on a full entry the writing is the point, and a
            grid of photos above it pushed it off the screen. */}
        {text && <div className="entry-text">{text}</div>}
        {/* A thumbnail grid, not a gallery of full images: the small copy is
            480px, so cells have to stay small enough for it to look sharp.
            Tapping one opens the original. */}
        <MediaGrid compact entryId={entry.id} language={language} media={entry.media} />
      </article>
      <CommentThread
        comments={comments}
        entryId={entry.id}
        inviteName={result.inviteName}
        language={language}
      />
      <SiteFooter language={language} />
    </main>
  );
}
