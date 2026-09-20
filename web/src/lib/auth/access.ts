import { cookies, headers } from "next/headers";

import { readOwnerSession, OWNER_COOKIE } from "./session";

export async function currentOwner(): Promise<{ name: string } | null> {
  const store = await cookies();
  return readOwnerSession(store.get(OWNER_COOKIE)?.value);
}

export async function requireSameOrigin(): Promise<void> {
  const requestHeaders = await headers();
  const origin = requestHeaders.get("origin");
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const protocol = requestHeaders.get("x-forwarded-proto") ?? "https";
  if (!origin || !host || new URL(origin).origin !== `${protocol}://${host}`) {
    throw new Error("Invalid request origin.");
  }
}

export async function requireHttps(): Promise<void> {
  const requestHeaders = await headers();
  if ((requestHeaders.get("x-forwarded-proto") ?? "https") !== "https") {
    throw new Error("A secure connection is required.");
  }
}

