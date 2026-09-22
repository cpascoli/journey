"use server";

import { cookies } from "next/headers";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

import { authenticateToken, requireScope } from "@/lib/api/keys";
import { publicOrigin } from "@/lib/api/origin";
import { currentOwner, requireHttps, requireSameOrigin } from "@/lib/auth/access";
import { createOwnerSession, OWNER_COOKIE, secureCookieOptions } from "@/lib/auth/session";
import { hashInviteToken, inviteUrl, newInviteToken } from "@/lib/owner/invites";
import { adminClient } from "@/lib/supabase/admin";

export type LoginState = { error?: string };

export async function login(_state: LoginState, formData: FormData): Promise<LoginState> {
  try {
    await requireHttps();
    await requireSameOrigin();
    const key = formData.get("key");
    if (typeof key !== "string") return { error: "Invalid credentials." };
    const principal = authenticateToken(key);
    requireScope(principal, "journey:invites:manage");
    requireScope(principal, "journey:entries:read");
    const store = await cookies();
    store.set(OWNER_COOKIE, createOwnerSession(principal.name, key), secureCookieOptions("strict"));
  } catch {
    return { error: "Invalid credentials." };
  }
  redirect("/owner");
}

export async function logout(): Promise<void> {
  await requireSameOrigin();
  const store = await cookies();
  store.set(OWNER_COOKIE, "", secureCookieOptions("strict", 0));
  redirect("/owner/login");
}

export type CreateInviteState = { error?: string; url?: string };

export async function createInvite(
  _state: CreateInviteState,
  formData: FormData,
): Promise<CreateInviteState> {
  try {
    await requireSameOrigin();
    if (!await currentOwner()) return { error: "Your session is no longer valid." };
    const nameValue = formData.get("name");
    const name = typeof nameValue === "string" ? nameValue.trim() : "";
    if (!name || name.length > 100) return { error: "Enter a name of 100 characters or fewer." };
    const tagIds = formData.getAll("tag_ids").filter((value): value is string =>
      typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
    );
    const token = newInviteToken();
    const { error } = await adminClient().rpc("create_invite", {
      p_name: name,
      p_token_hash: hashInviteToken(token),
      p_tag_ids: tagIds,
    });
    if (error) return { error: "The invitation could not be created." };
    const requestHeaders = await headers();
    const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
    if (!host) return { error: "The invitation was created, but its link could not be displayed." };
    revalidatePath("/owner");
    return { url: inviteUrl(publicOrigin(requestHeaders, `https://${host}`), token) };
  } catch {
    return { error: "The invitation could not be created." };
  }
}

export async function revokeInvite(formData: FormData): Promise<void> {
  await requireSameOrigin();
  if (!await currentOwner()) redirect("/owner/login");
  const id = formData.get("id");
  if (typeof id !== "string" || !/^[0-9a-f-]{36}$/i.test(id)) return;
  await adminClient().from("invites").update({ revoked_at: new Date().toISOString() }).eq("id", id).is("revoked_at", null);
  revalidatePath("/owner");
}


const OWNER_UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Replies in one reader's conversation. The thread must already exist, so the
 * owner cannot open a conversation with someone who never wrote.
 */
export async function replyToComment(formData: FormData): Promise<void> {
  await requireSameOrigin();
  if (!await currentOwner()) redirect("/owner/login");
  const entryId = formData.get("entry");
  const inviteId = formData.get("invite");
  const body = formData.get("body");
  if (typeof entryId !== "string" || !OWNER_UUID.test(entryId)) return;
  if (typeof inviteId !== "string" || !OWNER_UUID.test(inviteId)) return;
  if (typeof body !== "string" || body.trim().length === 0 || body.length > 2000) return;

  await adminClient().rpc("post_owner_comment", {
    p_entry_id: entryId,
    p_invite_id: inviteId,
    p_body: body,
  });
  revalidatePath(`/owner/entries/${entryId}`);
  revalidatePath("/owner");
}

export async function deleteComment(formData: FormData): Promise<void> {
  await requireSameOrigin();
  if (!await currentOwner()) redirect("/owner/login");
  const id = formData.get("id");
  const entryId = formData.get("entry");
  if (typeof id !== "string" || !OWNER_UUID.test(id)) return;
  await adminClient().rpc("delete_comment", { p_id: id });
  if (typeof entryId === "string" && OWNER_UUID.test(entryId)) {
    revalidatePath(`/owner/entries/${entryId}`);
  }
  revalidatePath("/owner");
}

/** Clears the unread badge once the owner has actually read a thread. */
export async function markThreadSeen(formData: FormData): Promise<void> {
  await requireSameOrigin();
  if (!await currentOwner()) redirect("/owner/login");
  const entryId = formData.get("entry");
  const inviteId = formData.get("invite");
  if (typeof entryId !== "string" || !OWNER_UUID.test(entryId)) return;
  if (typeof inviteId !== "string" || !OWNER_UUID.test(inviteId)) return;
  await adminClient().rpc("mark_thread_seen", {
    p_entry_id: entryId,
    p_invite_id: inviteId,
  });
  revalidatePath(`/owner/entries/${entryId}`);
  revalidatePath("/owner");
}

export type EditTextState = { error?: string; saved?: boolean };

/**
 * Corrects an entry's text from the dashboard, in both languages.
 *
 * Only the text columns: tags and visibility decide who may read an entry,
 * and `save_entry_text` cannot reach them. The app stays the source of truth,
 * so a later Update Website from the phone replaces whatever is saved here.
 */
export async function saveEntryText(
  _state: EditTextState,
  formData: FormData,
): Promise<EditTextState> {
  try {
    await requireSameOrigin();
  } catch {
    return { error: "That request did not come from the dashboard." };
  }
  if (!await currentOwner()) redirect("/owner/login");

  const id = formData.get("id");
  if (typeof id !== "string" || !OWNER_UUID.test(id)) {
    return { error: "That entry could not be found." };
  }
  const text = (name: string, max = 20_000) => {
    const value = formData.get(name);
    return typeof value === "string" ? value.slice(0, max) : "";
  };
  const language = text("translation_language", 10);
  if (language !== "" && language !== "en" && language !== "it") {
    return { error: "A translation must be Italian, English, or none." };
  }

  const { data, error } = await adminClient().rpc("save_entry_text", {
    p_id: id,
    p_title: text("title", 300),
    p_notes: text("notes"),
    p_narrative: text("narrative"),
    p_translation_language: language,
    p_translated_title: text("translated_title", 300),
    p_translated_notes: text("translated_notes"),
    p_translated_narrative: text("translated_narrative"),
  });
  if (error) return { error: "The text could not be saved." };
  if (!(data as { saved: boolean }[])[0]?.saved) {
    return { error: "That entry could not be found." };
  }

  revalidatePath(`/owner/entries/${id}`);
  revalidatePath("/read", "layout");
  return { saved: true };
}
