/**
 * Who may read an entry. The same rule is enforced in SQL by
 * public.entries_visible_to_invite; keep the two in step.
 */

/** `private`: only the owner and their agents. `shared`: invites, subject to tags. */
export type Visibility = "private" | "shared";

export type EntryAccess = {
  visibility: Visibility;
  tagIds: readonly string[];
};

export type InviteAccess = {
  tagIds: readonly string[];
  revokedAt?: string | null;
};

/**
 * An invite sees an entry only if the entry is shared and the invite includes
 * every one of the entry's tags. Untagged shared entries are visible to every
 * invite. "Any tag matches" would be looser: an entry tagged dating and sport
 * would reach everyone invited for sport.
 */
export function isVisibleToInvite(entry: EntryAccess, invite: InviteAccess): boolean {
  if (invite.revokedAt) return false;
  if (entry.visibility !== "shared") return false;
  const allowed = new Set(invite.tagIds);
  return entry.tagIds.every((id) => allowed.has(id));
}
