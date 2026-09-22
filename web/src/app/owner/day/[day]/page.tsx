import Link from "next/link";
import { notFound, redirect } from "next/navigation";

import { MediaGrid } from "@/app/MediaGrid";
import { currentOwner } from "@/lib/auth/access";
import { currentLanguage } from "@/lib/i18n/current";
import { ownerEntriesForDay } from "@/lib/owner/reading";
import { adminClient } from "@/lib/supabase/admin";

export const dynamic = "force-dynamic";

type Params = { params: Promise<{ day: string }> };

const DAY = /^\d{4}-\d{2}-\d{2}$/;

function dayLabel(day: string): string {
  return new Intl.DateTimeFormat("en-GB", { dateStyle: "full", timeZone: "UTC" })
    .format(new Date(`${day}T12:00:00Z`));
}

/**
 * One day's entries. The dashboard lists only the days that have something on
 * them, so media is fetched here — for a handful of entries — rather than for
 * the whole journal at once.
 */
export default async function OwnerDayPage({ params }: Params) {
  const [{ day }, language] = await Promise.all([params, currentLanguage()]);
  if (!await currentOwner()) redirect("/owner/login");
  if (!DAY.test(day)) notFound();

  const entries = await ownerEntriesForDay(adminClient(), day);
  if (entries.length === 0) notFound();

  return (
    <main className="dashboard">
      <Link className="back-link" href="/owner">← Dashboard</Link>
      <header className="dashboard-header">
        <div>
          <p className="eyebrow">Owner view</p>
          <h1>{dayLabel(day)}</h1>
        </div>
      </header>

      <div className="owner-entries">
        {entries.map((entry) => (
          <article className="owner-entry" key={entry.id}>
            <div className="owner-entry-heading">
              <div>
                <h3><Link href={`/owner/entries/${entry.id}`}>{entry.title || "Untitled entry"}</Link></h3>
                <p>{entry.journal_name}{entry.place_name ? ` · ${entry.place_name}` : ""}</p>
              </div>
              <span className={`badge ${entry.visibility}`}>{entry.visibility}</span>
            </div>
            <MediaGrid compact entryId={entry.id} language={language} media={entry.media} />
            {entry.text && <div className="entry-text excerpt">{entry.text}</div>}
          </article>
        ))}
      </div>
    </main>
  );
}
