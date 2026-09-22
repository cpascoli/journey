import type { Language } from "@/lib/domain/language";
import { stringsFor } from "@/lib/i18n/strings";
import type { Comment } from "@/lib/reader/comment-shape";

import { CommentForm } from "./CommentForm";

/**
 * One flat conversation under an entry, private to this invitation: the
 * reader sees only their own comments and the owner's replies, never another
 * invitation's. Nothing here filters — the thread arrives already scoped by
 * `comment_thread_for_invite`.
 */
export function CommentThread({
  entryId,
  comments,
  language,
}: {
  entryId: string;
  comments: Comment[];
  language: Language;
}) {
  const strings = stringsFor(language);
  const time = new Intl.DateTimeFormat(strings.localeTag, {
    dateStyle: "medium",
    timeStyle: "short",
  });

  return (
    <section className="comments" aria-label={strings.conversation}>
      <h2>{strings.conversation}</h2>
      {comments.length === 0 ? (
        <p className="empty">{strings.noComments}</p>
      ) : (
        <ol className="comment-list">
          {comments.map((comment) => (
            <li className={`comment ${comment.author}`} key={comment.id}>
              <p className="comment-meta">
                <strong>{comment.author === "owner" ? strings.fromOwner : strings.you}</strong>
                <time dateTime={comment.created_at}>{time.format(new Date(comment.created_at))}</time>
              </p>
              {/* React escapes this; a comment is never treated as markup. */}
              <p className="comment-body">{comment.body}</p>
            </li>
          ))}
        </ol>
      )}
      <CommentForm entryId={entryId} language={language} />
    </section>
  );
}
