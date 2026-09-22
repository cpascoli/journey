import Link from "next/link";
import { redirect } from "next/navigation";

import { currentOwner } from "@/lib/auth/access";
import { dayOfMonth, groupDaysByMonth } from "@/lib/domain/days";
import { commentThreads } from "@/lib/owner/comments";
import { ownerEntryDays } from "@/lib/owner/reading";
import { adminClient } from "@/lib/supabase/admin";

import { InviteForm } from "./InviteForm";
import { logout, revokeInvite } from "./actions";

export const dynamic = "force-dynamic";

type Invite = {
  id: string;
  name: string;
  created_at: string;
  revoked_at: string | null;
  last_seen_at: string | null;
  invite_tags: { tag_id: string }[];
};

const monthLabel = (month: string) =>
  new Intl.DateTimeFormat("en-GB", { month: "long", year: "numeric", timeZone: "UTC" })
    .format(new Date(`${month}-01T12:00:00Z`));

export default async function OwnerDashboard() {
  const owner = await currentOwner();
  if (!owner) redirect("/owner/login");
  const db = adminClient();
  const [days, threads, { data: invites }, { data: tags }] = await Promise.all([
    ownerEntryDays(db),
    commentThreads(db),
    db.from("invites").select("id, name, created_at, revoked_at, last_seen_at, invite_tags(tag_id)").order("created_at", { ascending: false }),
    db.from("tags").select("id, name").order("name"),
  ]);
  const unseenTotal = threads.reduce((sum: number, thread) => sum + thread.unseen_count, 0);
  const months = groupDaysByMonth(days);
  const entryTotal = days.reduce((sum: number, entry) => sum + entry.count, 0);
  const tagList = (tags ?? []) as { id: string; name: string }[];
  const tagNames = new Map(tagList.map((tag) => [tag.id, tag.name]));

  return (
    <main className="dashboard">
      <header className="dashboard-header">
        <div><p className="eyebrow">Journey owner</p><h1>Dashboard</h1></div>
        <form action={logout}><button className="secondary" type="submit">Sign out</button></form>
      </header>

      <section className="panel">
        <h2>
          Conversations
          {unseenTotal > 0 && <span className="badge shared">{unseenTotal} new</span>}
        </h2>
        {threads.length === 0 ? <p className="empty">No comments yet.</p> : (
          <div className="rows">
            {threads.map((thread) => (
              <div className="row" key={`${thread.entry_id}:${thread.invite_id}`}>
                <div>
                  <Link href={`/owner/entries/${thread.entry_id}`}>
                    {thread.entry_title || "Untitled entry"}
                  </Link>
                  <p>
                    {thread.invite_name} · {thread.comment_count} comment
                    {thread.comment_count === 1 ? "" : "s"} · {thread.entry_day}
                  </p>
                </div>
                {thread.unseen_count > 0 && <span className="badge shared">{thread.unseen_count} new</span>}
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="panel">
        <h2>Published days</h2>
        {months.length === 0 ? <p className="empty">Nothing has been published yet.</p> : (
          <>
            <p className="panel-note">
              {entryTotal} {entryTotal === 1 ? "entry" : "entries"} across{" "}
              {days.length} {days.length === 1 ? "day" : "days"}. Open a day to see it
              — photos and videos load only for the day you pick.
            </p>
            {months.map((month) => (
              <div className="day-month" key={month.month}>
                <h3>{monthLabel(month.month)}</h3>
                <div className="day-chips">
                  {month.days.map((entry) => (
                    <Link
                      className="day-chip"
                      href={`/owner/day/${entry.day}`}
                      key={entry.day}
                      title={`${entry.day} · ${entry.count} ${entry.count === 1 ? "entry" : "entries"}`}
                    >
                      {dayOfMonth(entry.day)}
                      {entry.count > 1 && <span className="count">{entry.count}</span>}
                    </Link>
                  ))}
                </div>
              </div>
            ))}
          </>
        )}
      </section>

      <section className="dashboard-grid">
        <div className="panel">
          <h2>Invitations</h2>
          {(invites ?? []).length === 0 ? <p className="empty">No invitations yet.</p> : (
            <div className="rows">
              {((invites ?? []) as Invite[]).map((invite) => (
                <div className="row invite-row" key={invite.id}>
                  <div>
                    <strong>{invite.name}</strong>
                    <p>{invite.revoked_at ? "Revoked" : invite.last_seen_at ? "Used" : "Not opened"} · {
                      invite.invite_tags.length
                        ? invite.invite_tags.map(({ tag_id }) => tagNames.get(tag_id)).filter(Boolean).join(", ")
                        : "all untagged entries"
                    }</p>
                  </div>
                  {!invite.revoked_at && (
                    <form action={revokeInvite}>
                      <input type="hidden" name="id" value={invite.id} />
                      <button className="danger secondary" type="submit">Revoke</button>
                    </form>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
        <div className="panel">
          <h2>New invitation</h2>
          <InviteForm tags={tagList} />
        </div>
      </section>
    </main>
  );
}

