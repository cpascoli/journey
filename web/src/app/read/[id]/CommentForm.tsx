"use client";

import { useActionState } from "react";

import type { Language } from "@/lib/domain/language";
import { stringsFor } from "@/lib/i18n/strings";
import { MAX_COMMENT_LENGTH, type Refusal } from "@/lib/reader/comment-shape";

import { addComment, type CommentState } from "../actions";

const initialState: CommentState = {};

/**
 * The reader's comment box. A form action rather than fetch, so it still
 * posts if the client script never loads; the refusal comes back from the
 * server, which is the only place that decides whether a comment is allowed.
 */
export function CommentForm({ entryId, language }: { entryId: string; language: Language }) {
  const [state, action, pending] = useActionState(addComment, initialState);
  const strings = stringsFor(language);
  const message: Record<Refusal, string> = {
    bad_body: strings.commentRefusedBody,
    too_many: strings.commentRefusedTooMany,
    not_readable: strings.commentRefusedUnavailable,
  };

  return (
    <form action={action} className="comment-form">
      <input name="entry" type="hidden" value={entryId} />
      <label className="visually-hidden" htmlFor="body">{strings.commentPlaceholder}</label>
      <textarea
        defaultValue={state.body ?? ""}
        id="body"
        maxLength={MAX_COMMENT_LENGTH}
        name="body"
        placeholder={strings.commentPlaceholder}
        required
        rows={3}
      />
      {state.refusal && <p className="form-error" role="alert">{message[state.refusal]}</p>}
      <button disabled={pending} type="submit">
        {pending ? "…" : strings.sendComment}
      </button>
    </form>
  );
}
