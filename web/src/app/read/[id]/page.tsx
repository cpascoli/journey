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
  // The first photo opens the entry at full width. It loads the original, not
  // the 480px thumbnail, which would blur at this size; it is also still in
  // the contact sheet below, where tapping it opens the viewer.
  const cover = entry.media.find((item) => item.kind === "photo");
  return (
    <main className="reader entry-page">
      <SiteHeader
        eyebrow={strings.sharedWith(result.inviteName)}
        language={language}
        next={`/read/${entry.id}`}
      />
      <Link className="back-link" href="/read">← {strings.allEntries}</Link>
      <article className="entry-detail">
        {cover && (
          <img
            alt={strings.photoAlt(entry.media.indexOf(cover) + 1)}
            className="entry-cover"
            fetchPriority="high"
            height={cover.height ?? undefined}
            src={`/media/${entry.id}/${encodeURIComponent(cover.key)}`}
            width={cover.width ?? undefined}
          />
        )}
        <h1>{title || strings.untitledEntry}</h1>
        <dl className="entry-facts">
          <div>
            <dt>{strings.metaDate}</dt>
            <dd>{formatDay(entry.day, language)}</dd>
          </div>
          {entry.place_name && (
            <div>
              <dt>{strings.metaPlace}</dt>
              <dd>{entry.place_name}</dd>
            </div>
          )}
          {entry.tags.length > 0 && (
            <div>
              <dt>{strings.metaTags}</dt>
              <dd>{entry.tags.map((tag) => tag.name).join(" · ")}</dd>
            </div>
          )}
          {entry.media.length > 0 && (
            <div>
              <dt>{strings.metaMedia}</dt>
              <dd>{entry.media.length}</dd>
            </div>
          )}
        </dl>
        {/* The story before the photos: on a full entry the writing is the
            point, and a grid above it pushed it off the screen. */}
        {text && <div className="entry-text">{text}</div>}
        {/* A thumbnail grid, not a gallery of full images: the small copy is
            480px, so cells have to stay small enough for it to look sharp.
            Tapping one opens the original. */}
        {entry.media.length > 0 && (
          <section className="contact-sheet" aria-labelledby="contact-sheet">
            <h2 id="contact-sheet">{strings.contactSheet}</h2>
            <MediaGrid compact entryId={entry.id} language={language} media={entry.media} />
          </section>
        )}
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
