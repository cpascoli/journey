import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { Conversations } from "@/app/owner/Conversations";
import { EditTextForm } from "./EditTextForm";
import { MediaGrid } from "@/app/MediaGrid";
import { currentLanguage } from "@/lib/i18n/current";
import { currentOwner } from "@/lib/auth/access";
import { conversationsForEntry } from "@/lib/owner/comments";
import { editableEntryText } from "@/lib/owner/reading";
import { ownerEntry } from "@/lib/owner/reading";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ id: string }> };

function dayLabel(day: string): string {
  return new Intl.DateTimeFormat("en", { dateStyle: "long", timeZone: "UTC" })
    .format(new Date(`${day}T12:00:00Z`));
}

export default async function OwnerEntryPage({ params }: Params) {
  const language = await currentLanguage();
  if (!await currentOwner()) redirect("/owner/login");
  const id = (await params).id;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  const db = adminClient();
  const entry = await ownerEntry(db, id);
  if (!entry) notFound();
  const [threads, editable] = await Promise.all([
    conversationsForEntry(db, id),
    editableEntryText(db, id),
  ]);

  return (
    <main className="reader">
      <Link className="back-link" href="/owner">← Dashboard</Link>
      <article className="entry-detail">
        <p className="eyebrow">Owner view · {entry.visibility}</p>
        <p className="entry-meta">
          {dayLabel(entry.day)} · {entry.journal_name}
          {entry.place_name ? ` · ${entry.place_name}` : ""}
        </p>
        <h1>{entry.title || "Untitled entry"}</h1>
        <MediaGrid entryId={entry.id} language={language} media={entry.media} />
        {entry.text && <div className="entry-text">{entry.text}</div>}
      </article>
      {editable && (
        <section className="panel">
          <h2>Edit text</h2>
          <EditTextForm entry={editable} />
        </section>
      )}
      <Conversations threads={threads} />
    </main>
  );
}
