#!/usr/bin/env node
// HTTP integration checks for invite exchange, reader authorization, and media.
// This script creates and removes data, and therefore refuses non-local URLs.
import { randomUUID } from "node:crypto";

const env = {
  BASE_URL: process.env.BASE_URL ?? "http://127.0.0.1:3000",
  OWNER_TOKEN: process.env.OWNER_TOKEN,
};
if (!env.OWNER_TOKEN) {
  console.error("OWNER_TOKEN is required.");
  process.exit(2);
}
if (!["localhost", "127.0.0.1", "::1", "[::1]"].includes(new URL(env.BASE_URL).hostname)) {
  console.error("reader-e2e only runs against localhost.");
  process.exit(2);
}

let failures = 0;
const createdEntries = [];
const createdTags = [];
const createdInvites = [];

function check(label, condition, detail) {
  if (condition) console.log(`  ok   ${label}`);
  else {
    failures++;
    console.log(`  FAIL ${label}${detail === undefined ? "" : ` — ${JSON.stringify(detail).slice(0, 400)}`}`);
  }
}

async function request(path, init = {}) {
  const response = await fetch(env.BASE_URL + path, { redirect: "manual", ...init });
  return { response, text: await response.text() };
}

async function owner(method, path, body, contentType = "application/json") {
  const headers = { Authorization: `Bearer ${env.OWNER_TOKEN}` };
  if (body !== undefined) headers["Content-Type"] = contentType;
  const { response, text } = await request(path, {
    method,
    headers,
    body: body === undefined ? undefined : contentType === "application/json" ? JSON.stringify(body) : body,
  });
  let data = text;
  try { data = JSON.parse(text); } catch {}
  return { status: response.status, data };
}

async function createTag(name) {
  const id = randomUUID();
  createdTags.push(id);
  const result = await owner("PUT", `/api/v1/owner/tags/${id}`, { name });
  check(`create ${name} tag`, result.status === 200, result);
  return id;
}

async function createEntry({ title, notes, narrative, visibility, tagIds, mediaKeys = [] }) {
  const id = randomUUID();
  createdEntries.push(id);
  const result = await owner("PUT", `/api/v1/owner/entries/${id}`, {
    occurred_at: "2026-09-17T08:00:00Z",
    day: "2026-09-17",
    title,
    notes,
    narrative,
    narrative_source: "user",
    location: { locality: "Bangkok" },
    location_precision: "city",
    visibility,
    tag_ids: tagIds,
    media_keys: mediaKeys,
  });
  check(`publish ${title}`, result.status === 201, result);
  return id;
}

async function createInvite(name, tagIds) {
  const result = await owner("POST", "/api/v1/owner/invites", { name, tag_ids: tagIds });
  if (result.data?.invite?.id) createdInvites.push(result.data.invite.id);
  check(`create ${name} invite`, result.status === 201 && result.data?.token, result);
  return result.data;
}

async function exchange(token) {
  const { response } = await request(`/i/${token}`);
  const cookie = response.headers.get("set-cookie")?.split(";")[0];
  check("invite token exchanges for a no-store redirect", response.status === 303 &&
    response.headers.get("location")?.endsWith("/read") &&
    response.headers.get("cache-control") === "no-store", {
      status: response.status,
      location: response.headers.get("location"),
    });
  check("exchange sets an HTTP-only invite cookie", cookie?.startsWith("__Host-journey-invite=") &&
    response.headers.get("set-cookie")?.includes("HttpOnly"), response.headers.get("set-cookie"));
  return cookie;
}

async function page(path, cookie) {
  return request(path, { headers: cookie ? { Cookie: cookie } : {} });
}

const cleanPhoto = new Uint8Array([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x07, 0x4a, 0x46, 0x49, 0x46, 0x00,
  0xff, 0xda, 0x00, 0x05, 0x00, 0x00, 0x00, 0x12, 0x34, 0xff, 0xd9,
]);

try {
  console.log("reader policy matrix");
  const sport = await createTag(`Sport ${randomUUID().slice(0, 8)}`);
  const family = await createTag(`Family ${randomUUID().slice(0, 8)}`);
  const fallback = await createEntry({
    title: "Fallback notes entry",
    notes: "Notes shown when narrative is empty",
    narrative: "   ",
    visibility: "shared",
    tagIds: [],
  });
  const sportEntry = await createEntry({
    title: "Sport narrative entry",
    notes: "Notes must stay hidden",
    narrative: "Accepted narrative wins",
    visibility: "shared",
    tagIds: [sport],
    mediaKeys: ["reader-photo"],
  });
  const allTagsEntry = await createEntry({
    title: "Family sport entry",
    notes: "Visible only with every tag",
    narrative: "",
    visibility: "shared",
    tagIds: [sport, family],
    mediaKeys: ["all-tags-photo"],
  });
  const privateEntry = await createEntry({
    title: "Private owner entry",
    notes: "Never shown to readers",
    narrative: "",
    visibility: "private",
    tagIds: [],
    mediaKeys: ["private-photo"],
  });
  const upload = await owner(
    "PUT",
    `/api/v1/owner/entries/${sportEntry}/media/reader-photo?width=2&height=2&sort_order=0`,
    cleanPhoto,
    "image/jpeg",
  );
  check("upload reader media", upload.status === 200, upload);
  for (const [entryId, key] of [
    [allTagsEntry, "all-tags-photo"],
    [privateEntry, "private-photo"],
  ]) {
    const result = await owner(
      "PUT",
      `/api/v1/owner/entries/${entryId}/media/${key}?width=2&height=2&sort_order=0`,
      cleanPhoto,
      "image/jpeg",
    );
    check(`upload ${key}`, result.status === 200, result);
  }

  const noTags = await createInvite("Reader no tags", []);
  const sportOnly = await createInvite("Reader sport", [sport]);
  const allTags = await createInvite("Reader all tags", [sport, family]);

  const noTagsCookie = await exchange(noTags.token);
  const noTagsPage = await page("/read", noTagsCookie);
  check("untagged invite sees fallback notes", noTagsPage.response.status === 200 &&
    noTagsPage.text.includes("Fallback notes entry") &&
    noTagsPage.text.includes("Notes shown when narrative is empty"), noTagsPage.response.status);
  check("untagged invite cannot see tagged or private entries",
    !noTagsPage.text.includes("Sport narrative entry") &&
    !noTagsPage.text.includes("Family sport entry") &&
    !noTagsPage.text.includes("Private owner entry"));

  const sportCookie = await exchange(sportOnly.token);
  const sportPage = await page("/read", sportCookie);
  check("single-tag invite sees untagged and matching-tag entries",
    sportPage.text.includes("Fallback notes entry") && sportPage.text.includes("Sport narrative entry"));
  check("narrative replaces notes for readers",
    sportPage.text.includes("Accepted narrative wins") && !sportPage.text.includes("Notes must stay hidden"));
  check("single-tag invite cannot see an entry requiring both tags or a private entry",
    !sportPage.text.includes("Family sport entry") && !sportPage.text.includes("Private owner entry"));
  const deniedDetail = await page(`/read/${allTagsEntry}`, sportCookie);
  check("direct under-tagged detail access is denied", deniedDetail.text.includes("Entry unavailable"));

  const allTagsCookie = await exchange(allTags.token);
  const allTagsPage = await page("/read", allTagsCookie);
  check("all-tags invite sees every shared matrix entry",
    [fallback, sportEntry, allTagsEntry].every((id) => allTagsPage.text.includes(`/read/${id}`)));
  check("private entry remains absent with every tag", !allTagsPage.text.includes(privateEntry));

  console.log("signed media and revocation");
  const media = await page(`/media/${sportEntry}/reader-photo`, sportCookie);
  check("authorized media returns a short-lived signed redirect", media.response.status === 302 &&
    media.response.headers.get("location")?.includes("/storage/v1/object/sign/media/") &&
    media.response.headers.get("cache-control")?.includes("no-store"), {
      status: media.response.status,
      location: media.response.headers.get("location"),
    });
  const underTaggedMedia = await page(`/media/${allTagsEntry}/all-tags-photo`, sportCookie);
  const privateMedia = await page(`/media/${privateEntry}/private-photo`, allTagsCookie);
  const missingMedia = await page(`/media/${sportEntry}/missing-photo`, sportCookie);
  check("under-tagged media is denied", underTaggedMedia.response.status === 404);
  check("private media is denied even with every tag", privateMedia.response.status === 404);
  check("missing and unauthorized media are indistinguishable", missingMedia.response.status === 404);

  // Narrowing an invite's tags must take effect on the very next read.
  const beforeNarrowing = await page("/read", allTagsCookie);
  check("a fully tagged invite reads the all-tags entry", beforeNarrowing.text.includes(`/read/${allTagsEntry}`));
  const narrow = await owner("PATCH", `/api/v1/owner/invites/${allTags.invite.id}`, { tag_ids: [sport] });
  check("narrow invite tags", narrow.status === 200, narrow);
  const afterNarrowing = await page("/read", allTagsCookie);
  check("narrowing tags hides the entry immediately", !afterNarrowing.text.includes(`/read/${allTagsEntry}`));
  const narrowedDetail = await page(`/read/${allTagsEntry}`, allTagsCookie);
  check("narrowing tags denies the entry page too", narrowedDetail.text.includes("Entry unavailable"));

  // Replacing a link must invalidate the old one at the same moment.
  const replaced = await owner("POST", `/api/v1/owner/invites/${allTags.invite.id}/token`);
  check("replace invite link", replaced.status === 200 && typeof replaced.data?.token === "string", replaced);
  const oldLinkPage = await page("/read", allTagsCookie);
  check("the previous link stops working", !oldLinkPage.text.includes("Shared with"));
  const newCookie = await exchange(replaced.data.token);
  const newLinkPage = await page("/read", newCookie);
  check("the replacement link works", newLinkPage.text.includes("Shared with"));

  const revoke = await owner("DELETE", `/api/v1/owner/invites/${sportOnly.invite.id}`);
  check("revoke invite", revoke.status === 200, revoke);
  const revokedPage = await page("/read", sportCookie);
  const revokedMedia = await page(`/media/${sportEntry}/reader-photo`, sportCookie);
  // A withdrawn invitation reads differently from a link that was never valid.
  check("revoked cookie is denied on the next page request", revokedPage.text.includes("withdrawn"));
  check("revoked cookie is denied on the next media request", revokedMedia.response.status === 404);
  const rotateRevoked = await owner("POST", `/api/v1/owner/invites/${sportOnly.invite.id}/token`);
  check("a revoked invite cannot be given a new link", rotateRevoked.status === 409, rotateRevoked);

  const remove = await owner("DELETE", `/api/v1/owner/entries/${sportEntry}`);
  check("entry and media cleanup reconcile on unpublish", remove.status === 200 && remove.data?.deleted === true, remove);
  createdEntries.splice(createdEntries.indexOf(sportEntry), 1);
  const ownerMediaAfterDelete = await page(`/media/${sportEntry}/reader-photo`);
  check("removed media is no longer addressable", ownerMediaAfterDelete.response.status === 404);
} finally {
  for (const id of createdInvites) await owner("DELETE", `/api/v1/owner/invites/${id}`);
  for (const id of createdEntries) await owner("DELETE", `/api/v1/owner/entries/${id}`);
  for (const id of createdTags.reverse()) await owner("DELETE", `/api/v1/owner/tags/${id}`);
}

console.log(failures === 0 ? "\nall reader HTTP checks passed" : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
