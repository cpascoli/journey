"use client";

import { useActionState, useState } from "react";

import { createInvite, type CreateInviteState } from "./actions";

type Tag = { id: string; name: string };
const initialState: CreateInviteState = {};

export function InviteForm({ tags }: { tags: Tag[] }) {
  const [state, action, pending] = useActionState(createInvite, initialState);
  const [shared, setShared] = useState(false);

  async function share() {
    if (!state.url) return;
    if (navigator.share) {
      await navigator.share({ title: "Journey invitation", url: state.url });
    } else {
      await navigator.clipboard.writeText(state.url);
      setShared(true);
    }
  }

  if (state.url) {
    return (
      <div className="invite-created">
        <p><strong>Invitation created.</strong> This link is shown only now.</p>
        <button type="button" onClick={share}>{shared ? "Copied" : "Share invitation"}</button>
      </div>
    );
  }
  return (
    <form action={action} className="stack">
      <label htmlFor="invite-name">Name</label>
      <input id="invite-name" name="name" maxLength={100} placeholder="Family" required />
      {tags.length > 0 && (
        <fieldset>
          <legend>May read entries with these tags</legend>
          <div className="check-grid">
            {tags.map((tag) => (
              <label key={tag.id}><input type="checkbox" name="tag_ids" value={tag.id} /> {tag.name}</label>
            ))}
          </div>
        </fieldset>
      )}
      <p className="hint">Entries without tags are visible to every active invitation.</p>
      {state.error && <p className="form-error" role="alert">{state.error}</p>}
      <button type="submit" disabled={pending}>{pending ? "Creating…" : "Create invitation"}</button>
    </form>
  );
}

