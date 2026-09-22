/**
 * The parts of a comment that both the server and the browser need.
 *
 * Kept apart from `comments.ts` because that reaches for `next/headers`, and
 * a client component importing a runtime value from it would drag server-only
 * code into the browser bundle.
 */
export const MAX_COMMENT_LENGTH = 2000;

export type Comment = {
  id: string;
  author: "owner" | "reader";
  body: string;
  created_at: string;
};

/** Why a comment was not accepted. The reader sees a message, not the reason. */
export type Refusal = "not_readable" | "bad_body" | "too_many";
