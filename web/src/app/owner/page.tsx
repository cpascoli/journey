import Link from "next/link";
import { redirect } from "next/navigation";

import { MediaGrid } from "@/app/MediaGrid";
import { currentLanguage } from "@/lib/i18n/current";
import { currentOwner } from "@/lib/auth/access";
import { ownerEntries } from "@/lib/owner/reading";
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

export default async function OwnerDashboard() {
  const language = await currentLanguage();
  const owner = await currentOwner();
  if (!owner) redirect("/owner/login");
  const db = adminClient();
  const [entries, { data: invites }, { data: tags }] = await Promise.all([
    ownerEntries(db),
    db.from("invites").select("id, name, created_at, revoked_at, last_seen_at, invite_tags(tag_id)").order("created_at", { ascending: false }),
    db.from("tags").select("id, name").order("name"),
  ]);
  const tagList = (tags ?? []) as { id: string; name: string }[];
  const tagNames = new Map(tagList.map((tag) => [tag.id, tag.name]));

  return (
    <main className="dashboard">
      <header className="dashboard-header">
        <div><p className="eyebrow">Journey owner</p><h1>Dashboard</h1></div>
        <form action={logout}><button className="secondary" type="submit">Sign out</button></form>
      </header>

      <section className="panel">
        <h2>Published entries</h2>
        {entries.length === 0 ? <p className="empty">Nothing has been published yet.</p> : (
          <div className="owner-entries">
            {entries.map((entry) => (
              <article className="owner-entry" key={entry.id}>
                <div className="owner-entry-heading">
                  <div>
                    <h3><Link href={`/owner/entries/${entry.id}`}>{entry.title || "Untitled entry"}</Link></h3>
                    <p>{entry.day} · {entry.journal_name}{entry.place_name ? ` · ${entry.place_name}` : ""}</p>
                  </div>
                  <span className={`badge ${entry.visibility}`}>{entry.visibility}</span>
                </div>
                <MediaGrid entryId={entry.id} language={language} media={entry.media} compact />
                {entry.text && <div className="entry-text excerpt">{entry.text}</div>}
              </article>
            ))}
          </div>
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

