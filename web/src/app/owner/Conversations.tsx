import { deleteComment, markThreadSeen, replyToComment } from "./actions";

export type OwnerComment = {
  id: string;
  author: "owner" | "reader";
  body: string;
  seen_by_owner: boolean;
  created_at: string;
};

export type OwnerThread = {
  entryId: string;
  inviteId: string;
  inviteName: string;
  inviteRevoked: boolean;
  unseen: number;
  comments: OwnerComment[];
};

const when = new Intl.DateTimeFormat("en-GB", { dateStyle: "medium", timeStyle: "short" });

/**
 * The conversations on one entry, one per invitation. Threads are private to
 * their invitation, so the owner sees several separate conversations here
 * rather than a single comment section.
 */
export function Conversations({ threads }: { threads: OwnerThread[] }) {
  if (threads.length === 0) {
    return (
      <section className="panel">
        <h2>Conversations</h2>
        <p className="empty">Nobody has commented on this entry.</p>
      </section>
    );
  }

  return (
    <section className="panel">
      <h2>Conversations</h2>
      {threads.map((thread) => (
        <article className="owner-thread" key={`${thread.entryId}:${thread.inviteId}`}>
          <header className="owner-thread-heading">
            <h3>
              {thread.inviteName}
              {thread.inviteRevoked && <span className="badge private">revoked</span>}
            </h3>
            {thread.unseen > 0 && (
              <form action={markThreadSeen}>
                <input name="entry" type="hidden" value={thread.entryId} />
                <input name="invite" type="hidden" value={thread.inviteId} />
                <button className="secondary" type="submit">
                  Mark {thread.unseen} as read
                </button>
              </form>
            )}
          </header>

          <ol className="comment-list">
            {thread.comments.map((comment) => (
              <li className={`comment ${comment.author}`} key={comment.id}>
                <p className="comment-meta">
                  <strong>{comment.author === "owner" ? "You" : thread.inviteName}</strong>
                  <span>
                    {when.format(new Date(comment.created_at))}
                    {comment.author === "reader" && !comment.seen_by_owner ? " · new" : ""}
                  </span>
                </p>
                <p className="comment-body">{comment.body}</p>
                <form action={deleteComment}>
                  <input name="id" type="hidden" value={comment.id} />
                  <input name="entry" type="hidden" value={thread.entryId} />
                  <button className="link-button" type="submit">Delete</button>
                </form>
              </li>
            ))}
          </ol>

          <form action={replyToComment} className="comment-form">
            <input name="entry" type="hidden" value={thread.entryId} />
            <input name="invite" type="hidden" value={thread.inviteId} />
            <textarea
              aria-label={`Reply to ${thread.inviteName}`}
              maxLength={2000}
              name="body"
              placeholder={`Reply to ${thread.inviteName}…`}
              required
              rows={2}
            />
            <button type="submit">Reply</button>
          </form>
        </article>
      ))}
    </section>
  );
}
