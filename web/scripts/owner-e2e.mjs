#!/usr/bin/env node
// End-to-end check of the owner API against a LOCAL Supabase stack and a
// local server, exercising every endpoint and the rules behind them. Refuses
// to run against anything but localhost.
//
//   pnpm dlx supabase start && pnpm dlx supabase db reset
//   pnpm build && SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… JOURNEY_API_KEYS=… pnpm start
//   BASE_URL=http://localhost:3000 OWNER_TOKEN=… AGENT_TOKEN=… \
//     SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_SERVICE_ROLE_KEY=… node scripts/owner-e2e.mjs
import { randomUUID } from "node:crypto";

const env = {
  BASE_URL: process.env.BASE_URL,
  OWNER_TOKEN: process.env.OWNER_TOKEN,
  AGENT_TOKEN: process.env.AGENT_TOKEN,
  SUPABASE_URL: process.env.SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
};
for (const [name, value] of Object.entries(env)) {
  if (!value) {
    console.error(`${name} is required.`);
    process.exit(2);
  }
}
const isLocal = (url) => ["localhost", "127.0.0.1", "::1", "[::1]"].includes(new URL(url).hostname);
if (!isLocal(env.BASE_URL) || !isLocal(env.SUPABASE_URL)) {
  console.error("owner-e2e only runs against localhost: it writes and deletes data.");
  process.exit(2);
}

let failures = 0;
function check(label, condition, detail) {
  if (condition) {
    console.log(`  ok   ${label}`);
  } else {
    failures++;
    console.log(`  FAIL ${label}${detail === undefined ? "" : ` — ${JSON.stringify(detail).slice(0, 400)}`}`);
  }
}

async function parse(res) {
  const text = await res.text();
  try {
    return { status: res.status, data: JSON.parse(text) };
  } catch {
    return { status: res.status, data: text };
  }
}

async function api(method, path, { token = env.OWNER_TOKEN, json, bytes, contentType } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  let body;
  if (json !== undefined) {
    headers["Content-Type"] = "application/json";
    body = JSON.stringify(json);
  }
  if (bytes !== undefined) {
    headers["Content-Type"] = contentType ?? "image/jpeg";
    body = bytes;
  }
  return parse(await fetch(env.BASE_URL + path, { method, headers, body }));
}

function decodeHtml(value) {
  return value
    .replaceAll("&quot;", '"')
    .replaceAll("&#x27;", "'")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");
}

async function ownerLogin(originOverride) {
  const loginPage = await fetch(env.BASE_URL + "/owner/login", { redirect: "manual" });
  const html = await loginPage.text();
  const form = new FormData();
  for (const input of html.matchAll(/<input\b[^>]*type="hidden"[^>]*>/g)) {
    const name = input[0].match(/\bname="([^"]*)"/)?.[1];
    const value = input[0].match(/\bvalue="([^"]*)"/)?.[1] ?? "";
    if (name) form.append(decodeHtml(name), decodeHtml(value));
  }
  form.set("key", env.OWNER_TOKEN);
  const origin = new URL(env.BASE_URL).origin;
  const response = await fetch(env.BASE_URL + "/owner/login", {
    method: "POST",
    headers: {
      Origin: originOverride ?? origin.replace("http:", "https:"),
      "X-Forwarded-Proto": "https",
    },
    body: form,
    redirect: "manual",
  });
  return {
    response,
    cookie: response.headers.get("set-cookie")?.split(";")[0],
    setCookie: response.headers.get("set-cookie"),
    body: await response.text(),
  };
}

const key = env.SUPABASE_SERVICE_ROLE_KEY;
const serviceHeaders = key.startsWith("sb_") ? { apikey: key } : { apikey: key, Authorization: `Bearer ${key}` };

async function supabase(method, path, json) {
  return parse(
    await fetch(env.SUPABASE_URL + path, {
      method,
      headers: { ...serviceHeaders, "Content-Type": "application/json", Prefer: "return=representation" },
      body: json === undefined ? undefined : JSON.stringify(json),
    }),
  );
}

function segment(marker, text) {
  const bytes = [...text].map((c) => c.charCodeAt(0));
  const length = bytes.length + 2;
  return [0xff, marker, length >> 8, length & 0xff, ...bytes];
}
function jpeg(...segments) {
  return new Uint8Array([0xff, 0xd8, ...segments.flat(), ...segment(0xda, "\0\0\0"), 0x12, 0x34, 0xff, 0xd9]);
}
const cleanPhoto = jpeg(segment(0xe0, "JFIF\0"));
const gpsPhoto = jpeg(segment(0xe0, "JFIF\0"), segment(0xe1, "Exif\0\0MM\0*"));

const sport = randomUUID();
const family = randomUUID();
const entry = randomUUID();
const privateEntry = randomUUID();
const files = (prefix = `entries/${entry}`) =>
  supabase("POST", "/storage/v1/object/list/media", { prefix, limit: 10 });

console.log("contract and keys");
{
  const r = await api("GET", "/api/v1/owner/openapi.json", { token: null });
  check("openapi.json is public", r.status === 200 && r.data.openapi === "3.1.0", r.status);
}
{
  const r = await api("GET", "/api/v1/owner/tags", { token: null });
  check("no token → 401", r.status === 401 && r.data.error?.code === "UNAUTHENTICATED", r);
}
{
  const r = await api("PUT", `/api/v1/owner/tags/${sport}`, { token: env.AGENT_TOKEN, json: { name: "Sport" } });
  check("the agent key can't publish → 403", r.status === 403, r);
}

console.log("tags");
{
  const r = await api("PUT", `/api/v1/owner/tags/${sport}`, { json: { name: "Sport", color: "green" } });
  check("create a tag", r.status === 200 && r.data.tag?.name === "Sport", r);
}
{
  const r = await api("PUT", `/api/v1/owner/tags/${family}`, { json: { name: "Family", color: "pink" } });
  check("create a second tag", r.status === 200, r);
}
{
  const r = await api("PUT", `/api/v1/owner/tags/${sport}`, { json: { name: "Sport", color: "chartreuse" } });
  check("unknown colour → 422 on color", r.status === 422 && r.data.error?.field === "color", r);
}

console.log("entries");
const entryBody = {
  occurred_at: "2026-09-11T09:00:00+07:00",
  day: "2026-09-11",
  title: "Temple of Dawn",
  notes: "Climbed the central prang before the crowds.",
  location: { place_name: "Wat Arun", locality: "Bangkok", latitude: 13.743712, longitude: 100.488921 },
  visibility: "shared",
  tag_ids: [sport],
  media_keys: ["k1", "k2"],
};
{
  const r = await api("PUT", `/api/v1/owner/entries/${entry}`, { json: entryBody });
  check(
    "publish → 201 at revision 1, both photos still to upload",
    r.status === 201 && r.data.created === true && r.data.entry?.revision === 1 &&
      JSON.stringify(r.data.missing_media) === '["k1","k2"]',
    r,
  );
}
{
  const e = (await api("GET", `/api/v1/owner/entries/${entry}`)).data.entry ?? {};
  check(
    "stored at city precision: Bangkok, 13.7, 100.5, and no Wat Arun",
    e.place_name === "Bangkok" && e.latitude === 13.7 && e.longitude === 100.5 && !JSON.stringify(e).includes("Wat Arun"),
    e,
  );
  check("stored with its tag", JSON.stringify(e.tag_ids) === JSON.stringify([sport]), e.tag_ids);
}
{
  const r = await api("PUT", `/api/v1/owner/entries/${entry}`, {
    json: { ...entryBody, title: "Changed", tag_ids: [randomUUID()] },
  });
  check("unknown tag → 422 on tag_ids", r.status === 422 && r.data.error?.field === "tag_ids", r);
  const e = (await api("GET", `/api/v1/owner/entries/${entry}`)).data.entry ?? {};
  check("…and the failed save left the entry untouched", e.title === "Temple of Dawn" && e.tag_ids?.[0] === sport, e);
}
{
  const r = await api("PUT", `/api/v1/owner/entries/${entry}`, { json: { ...entryBody, day: "2026-02-30" } });
  check("impossible date → 422 on day", r.status === 422 && r.data.error?.field === "day", r);
}

console.log("photos");
{
  const r = await api(
    "PUT",
    `/api/v1/owner/entries/${entry}/media/k1?width=2048&height=1536&sort_order=0&taken_at=2026-09-11T02:20:00Z`,
    { bytes: cleanPhoto },
  );
  check("a stripped JPEG uploads", r.status === 200 && r.data.media?.asset_key === "k1", r);
}
{
  const r = await api("PUT", `/api/v1/owner/entries/${entry}/media/k2`, { bytes: gpsPhoto });
  check("a photo with EXIF → 422", r.status === 422 && JSON.stringify(r.data.error?.metadata) === '["exif"]', r);
}
{
  const r = await api("PUT", `/api/v1/owner/entries/${entry}/media/k2`, { bytes: cleanPhoto, contentType: "image/png" });
  check("a non-JPEG content type → 415", r.status === 415, r);
}
{
  const r = await api("PUT", `/api/v1/owner/entries/${randomUUID()}/media/k1`, { bytes: cleanPhoto });
  check("a photo for an unknown entry → 404", r.status === 404, r);
}
{
  const r = await files(`entries/${entry}/k1`);
  const names = Array.isArray(r.data) ? r.data.map((object) => object.name) : [];
  const versionName = names.find((name) =>
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jpg$/i.test(name)
  );
  const listedPath = versionName ? `entries/${entry}/k1/${versionName}` : null;
  check("the immutable upload is nested under its key in the private bucket",
    r.status === 200 && listedPath?.startsWith(`entries/${entry}/k1/`) === true,
    { status: r.status, listedPath, data: r.data });
}
{
  const r = await api("PUT", `/api/v1/owner/entries/${entry}`, { json: { ...entryBody, media_keys: ["k1"] } });
  check(
    "same text, media set trimmed → revision still 1, nothing missing",
    r.status === 200 && r.data.entry?.revision === 1 && r.data.missing_media?.length === 0,
    r,
  );
}
{
  const r = await api("PUT", `/api/v1/owner/entries/${entry}`, {
    json: { ...entryBody, title: "Temple of Dawn at sunrise", media_keys: ["k1"] },
  });
  check("a new title → revision 2", r.data.entry?.revision === 2, r);
}
{
  const r = await api("PUT", `/api/v1/owner/entries/${privateEntry}`, {
    json: {
      ...entryBody,
      title: "Private dashboard entry",
      visibility: "private",
      tag_ids: [],
      media_keys: [],
    },
  });
  check("publish a private owner-only entry", r.status === 201, r);
}

console.log("owner dashboard");
{
  const anonymous = await fetch(env.BASE_URL + "/owner", { redirect: "manual" });
  check("anonymous owner request redirects to login", anonymous.status === 307 &&
    anonymous.headers.get("location")?.endsWith("/owner/login"), anonymous.status);
}
{
  const login = await ownerLogin();
  check("owner key login creates a hardened secure session",
    Boolean(login.cookie?.startsWith("__Host-journey-owner=")) &&
    login.setCookie?.includes("HttpOnly") &&
    login.setCookie?.includes("Secure") &&
    login.setCookie?.includes("SameSite=strict") &&
    login.setCookie?.includes("Path=/"), {
      status: login.response.status,
      location: login.response.headers.get("location"),
      setCookie: login.setCookie,
      body: login.body.slice(0, 200),
    });
  const headers = login.cookie ? { Cookie: login.cookie } : {};
  const dashboard = await fetch(env.BASE_URL + "/owner", { headers, redirect: "manual" });
  const dashboardHtml = await dashboard.text();
  check("session opens dashboard with public and private owner data",
    dashboard.status === 200 && dashboardHtml.includes("Dashboard") &&
    dashboardHtml.includes("Temple of Dawn at sunrise") &&
    dashboardHtml.includes("Private dashboard entry"), dashboard.status);
  const detail = await fetch(env.BASE_URL + `/owner/entries/${entry}`, { headers, redirect: "manual" });
  const detailHtml = await detail.text();
  check("owner session opens entry detail and media",
    detail.status === 200 && detailHtml.includes("Temple of Dawn at sunrise") &&
    detailHtml.includes(`/media/${entry}/k1`), detail.status);
  const ownerMedia = await fetch(env.BASE_URL + `/media/${entry}/k1`, { headers, redirect: "manual" });
  check("owner media request returns a signed redirect", ownerMedia.status === 302 &&
    ownerMedia.headers.get("location")?.includes("/storage/v1/object/sign/media/"), ownerMedia.status);
  const privateDetail = await fetch(env.BASE_URL + `/owner/entries/${privateEntry}`, { headers, redirect: "manual" });
  check("owner session opens private entry detail", privateDetail.status === 200 &&
    (await privateDetail.text()).includes("Private dashboard entry"), privateDetail.status);
}
{
  const login = await ownerLogin("https://attacker.example");
  check("cross-origin owner action is rejected without creating a session",
    !login.setCookie?.includes("__Host-journey-owner=") &&
    !login.response.headers.get("location")?.endsWith("/owner"),
    {
      status: login.response.status,
      location: login.response.headers.get("location"),
      setCookie: login.setCookie,
    });
}
{
  const r = await api("DELETE", `/api/v1/owner/entries/${privateEntry}`);
  check("clean up private dashboard entry", r.status === 200 && r.data.deleted === true, r);
}

console.log("tag deletion");
{
  const r = await api("DELETE", `/api/v1/owner/tags/${sport}`);
  check("deleting a tag in use → 409 TAG_IN_USE", r.status === 409 && r.data.error?.code === "TAG_IN_USE", r);
}
{
  const r = await api("DELETE", `/api/v1/owner/tags/${family}`);
  check("deleting an unused tag works", r.status === 200 && r.data.deleted === true, r);
}

console.log("invites");
let invite;
let token;
{
  const r = await api("POST", "/api/v1/owner/invites", { json: { name: "Sport friends", tag_ids: [sport] } });
  invite = r.data.invite?.id;
  token = r.data.token;
  check(
    "create → 201 with a one-time token and a reading link",
    r.status === 201 && /^[A-Za-z0-9_-]{32}$/.test(token ?? "") && r.data.url?.endsWith(`/i/${token}`),
    r,
  );
}
{
  const r = await supabase("POST", "/rest/v1/rpc/entries_visible_to_invite", { p_invite_id: invite });
  check("the shared sport entry is visible to the sport invite", r.status === 200 && Array.isArray(r.data) && r.data.some((e) => e.id === entry), r);
}
{
  const r = await api("GET", "/api/v1/owner/invites");
  check(
    "the list never includes the token",
    r.status === 200 && !JSON.stringify(r.data).includes(token) && r.data.invites?.some((i) => i.id === invite && i.tag_ids[0] === sport),
    r,
  );
}
{
  const r = await api("DELETE", `/api/v1/owner/invites/${invite}`);
  check("revoke", r.status === 200 && r.data.revoked === true, r);
}
{
  const r = await supabase("POST", "/rest/v1/rpc/entries_visible_to_invite", { p_invite_id: invite });
  check("a revoked invite sees nothing", r.status === 200 && Array.isArray(r.data) && r.data.length === 0, r);
}
{
  const r = await api("DELETE", `/api/v1/owner/invites/${invite}`);
  check("revoking again is harmless", r.status === 200, r);
}
{
  const r = await api("DELETE", `/api/v1/owner/invites/${randomUUID()}`);
  check("unknown invite → 404", r.status === 404, r);
}

console.log("proposals");
let proposal;
{
  const r = await supabase("POST", "/rest/v1/narrative_proposals", {
    entry_id: entry,
    base_revision: 1,
    text: "The prang glowed orange at dawn.",
    agent_name: "chatgpt",
  });
  proposal = r.data?.[0]?.id;
  check("seed a proposal written against revision 1", r.status === 201 && Boolean(proposal), r);
}
{
  const r = await api("GET", "/api/v1/owner/proposals");
  const p = r.data.proposals?.find((x) => x.id === proposal);
  check("it is listed as stale, since the entry is at revision 2", p?.stale === true && p.entry_revision === 2, p ?? r);
}
{
  const r = await api("POST", `/api/v1/owner/proposals/${proposal}/decision`, {
    token: env.AGENT_TOKEN,
    json: { decision: "accepted" },
  });
  check("the agent can't decide its own proposal → 403", r.status === 403, r);
}
{
  const r = await api("POST", `/api/v1/owner/proposals/${proposal}/decision`, { json: { decision: "accepted" } });
  check("the owner accepts it", r.status === 200 && r.data.proposal?.status === "accepted", r);
}
{
  const r = await api("POST", `/api/v1/owner/proposals/${proposal}/decision`, { json: { decision: "rejected" } });
  check("deciding twice → 409", r.status === 409 && r.data.error?.code === "PROPOSAL_ALREADY_DECIDED", r);
}

console.log("unpublish");
{
  const r = await api("DELETE", `/api/v1/owner/entries/${entry}`);
  check("unpublish the entry", r.status === 200 && r.data.deleted === true, r);
}
{
  const r = await api("GET", `/api/v1/owner/entries/${entry}`);
  check("it is gone → 404", r.status === 404, r);
}
{
  const r = await files();
  check("its photo file is gone too", r.status === 200 && Array.isArray(r.data) && r.data.length === 0, r);
}
{
  const r = await api("DELETE", `/api/v1/owner/tags/${sport}`);
  check("with no entries left, the tag can go", r.status === 200 && r.data.deleted === true, r);
}

console.log(failures === 0 ? "\nall owner API checks passed" : `\n${failures} check(s) failed`);
process.exit(failures === 0 ? 0 : 1);
