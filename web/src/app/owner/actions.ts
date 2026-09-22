"use server";

import { cookies } from "next/headers";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";

import { authenticateToken, requireScope } from "@/lib/api/keys";
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
    const protocol = requestHeaders.get("x-forwarded-proto") ?? "https";
    revalidatePath("/owner");
    return { url: inviteUrl(`${protocol}://${host}`, token) };
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
