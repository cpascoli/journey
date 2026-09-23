import { API_VERSION } from "./version";

const errorResponse = {
  description: "Error",
  content: {
    "application/json": {
      schema: {
        type: "object",
        properties: {
          error: {
            type: "object",
            properties: { code: { type: "string" }, message: { type: "string" } },
          },
        },
      },
    },
  },
};

const ok = (description = "OK") => ({ description, content: { "application/json": { schema: { type: "object", properties: {} } } } });

const uuidPath = (name: string, description: string) => ({
  name,
  in: "path",
  required: true,
  schema: { type: "string", format: "uuid" },
  description,
});

const jsonBody = (schema: Record<string, unknown>) => ({
  required: true,
  content: { "application/json": { schema } },
});

function op(args: {
  operationId: string;
  summary: string;
  scope: string;
  parameters?: unknown[];
  requestBody?: unknown;
  responses?: Record<string, unknown>;
}) {
  return {
    operationId: args.operationId,
    summary: args.summary,
    security: [{ bearerAuth: [] }],
    "x-journey-scope": args.scope,
    parameters: args.parameters,
    requestBody: args.requestBody,
    responses: { "200": ok(), "401": errorResponse, "403": errorResponse, "422": errorResponse, ...args.responses },
  };
}

const entryBody = {
  type: "object",
  required: ["occurred_at", "day"],
  properties: {
    journal_name: { type: "string", maxLength: 100 },
    occurred_at: { type: "string", format: "date-time" },
    day: { type: "string", format: "date", description: "The calendar day as the writer saw it." },
    title: { type: "string", maxLength: 300 },
    notes: { type: "string", maxLength: 20000 },
    narrative: { type: "string", maxLength: 20000 },
    narrative_source: { type: "string", enum: ["user", "on_device", "chatgpt"] },
    location: {
      type: "object",
      properties: {
        place_name: { type: "string" },
        locality: { type: "string" },
        latitude: { type: "number" },
        longitude: { type: "number" },
      },
    },
    location_precision: {
      type: "string",
      enum: ["exact", "neighborhood", "city", "hidden"],
      description: "Default city. The server reduces the location to this before storing it.",
    },
    translation: {
      type: "object",
      properties: {
        language: { type: "string" },
        title: { type: "string" },
        notes: { type: "string" },
        narrative: { type: "string" },
      },
    },
    visibility: { type: "string", enum: ["private", "shared"], description: "Default private." },
    tag_ids: { type: "array", items: { type: "string", format: "uuid" } },
    client_content_hash: {
      type: ["string", "null"],
      pattern: "^[0-9a-f]{64}$",
      description: "SHA-256 of the canonical entry payload, excluding this field.",
    },
    media_keys: {
      type: "array",
      items: { type: "string", pattern: "^[A-Za-z0-9_-]{1,128}$" },
      description: "The entry's full ordered media set. Media not listed is deleted.",
    },
  },
};

const entryReadResponse = {
  description: "Published entry state",
  content: {
    "application/json": {
      schema: {
        type: "object",
        properties: {
          entry: {
            type: "object",
            properties: {
              client_content_hash: { type: ["string", "null"], pattern: "^[0-9a-f]{64}$" },
              media: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                  asset_key: { type: "string" },
                  thumb: {
                    type: "boolean",
                    description: "Whether a small copy exists for this photo.",
                  },
                },
                },
              },
            },
          },
        },
      },
    },
  },
};

/** The API the iPhone app publishes through. Owner key only. */
export function ownerOpenApiDocument(origin: string) {
  return {
    openapi: "3.1.0",
    info: {
      title: "Journey owner API",
      version: API_VERSION,
      description: "Publishing from the iPhone app: tags, entries, photos, invites and story proposals. Bearer owner key.",
    },
    servers: [{ url: origin }],
    components: {
      securitySchemes: { bearerAuth: { type: "http", scheme: "bearer", bearerFormat: "API key" } },
    },
    security: [{ bearerAuth: [] }],
    paths: {
      "/api/v1/owner/tags": {
        get: op({ operationId: "listTags", summary: "List tags", scope: "journey:entries:read" }),
      },
      "/api/v1/owner/tags/{id}": {
        put: op({
          operationId: "putTag",
          summary: "Create or update a tag",
          scope: "journey:entries:write",
          parameters: [uuidPath("id", "The app's tag id.")],
          requestBody: jsonBody({
            type: "object",
            required: ["name"],
            properties: { name: { type: "string", maxLength: 60 }, color: { type: "string" } },
          }),
        }),
        delete: op({
          operationId: "deleteTag",
          summary: "Delete a tag no entry uses",
          scope: "journey:entries:write",
          parameters: [uuidPath("id", "The app's tag id.")],
          responses: { "409": errorResponse },
        }),
      },
      "/api/v1/owner/entries/{id}": {
        get: op({
          operationId: "getEntry",
          summary: "Read a published entry",
          scope: "journey:entries:read",
          parameters: [uuidPath("id", "The app's entry id.")],
          responses: { "200": entryReadResponse, "404": errorResponse },
        }),
        put: op({
          operationId: "putEntry",
          summary: "Publish or update an entry",
          scope: "journey:entries:write",
          parameters: [uuidPath("id", "The app's entry id.")],
          requestBody: jsonBody(entryBody),
          responses: { "201": ok("Created") },
        }),
        delete: op({
          operationId: "deleteEntry",
          summary: "Unpublish an entry and its photos",
          scope: "journey:entries:write",
          parameters: [uuidPath("id", "The app's entry id.")],
        }),
      },
      "/api/v1/owner/entries/{id}/media/{key}": {
        put: op({
          operationId: "putPhoto",
          summary: "Upload a photo, metadata stripped",
          scope: "journey:entries:write",
          parameters: [
            uuidPath("id", "The app's entry id."),
            { name: "key", in: "path", required: true, schema: { type: "string", pattern: "^[A-Za-z0-9_-]{1,128}$" } },
            { name: "width", in: "query", schema: { type: "integer" } },
            { name: "height", in: "query", schema: { type: "integer" } },
            { name: "taken_at", in: "query", schema: { type: "string", format: "date-time" } },
            { name: "sort_order", in: "query", schema: { type: "integer" } },
          ],
          requestBody: {
            required: true,
            content: { "image/jpeg": { schema: { type: "string", format: "binary" } } },
          },
          responses: { "404": errorResponse, "413": errorResponse, "415": errorResponse },
        }),
        delete: op({
          operationId: "deletePhoto",
          summary: "Remove a photo",
          scope: "journey:entries:write",
          parameters: [
            uuidPath("id", "The app's entry id."),
            { name: "key", in: "path", required: true, schema: { type: "string" } },
          ],
        }),
      },
      "/api/v1/owner/entries/{id}/media/{key}/thumb": {
        put: op({
          operationId: "putThumbnail",
          summary: "Upload a photo's small copy",
          scope: "journey:entries:write",
          parameters: [
            uuidPath("id", "The app's entry id."),
            { name: "key", in: "path", required: true, schema: { type: "string", pattern: "^[A-Za-z0-9_-]{1,128}$" } },
          ],
          requestBody: {
            required: true,
            content: { "image/jpeg": { schema: { type: "string", format: "binary" } } },
          },
          responses: { "404": errorResponse, "413": errorResponse, "415": errorResponse },
        }),
      },
      "/api/v1/owner/entries/{id}/media/{key}/upload-url": {
        post: op({
          operationId: "startVideoUpload",
          summary: "Start a video upload",
          scope: "journey:entries:write",
          parameters: [
            uuidPath("id", "The app's entry id."),
            { name: "key", in: "path", required: true, schema: { type: "string", pattern: "^[A-Za-z0-9_-]{1,128}$" } },
          ],
          responses: {
            "200": {
              description: "A short-lived URL to PUT the video to, and the path to commit",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      upload: {
                        type: "object",
                        properties: {
                          url: { type: "string" },
                          storage_path: { type: "string" },
                          content_type: { type: "string" },
                          expires_in: { type: "integer" },
                          max_bytes: { type: "integer" },
                        },
                      },
                    },
                  },
                },
              },
            },
            "404": errorResponse,
          },
        }),
      },
      "/api/v1/owner/entries/{id}/media/{key}/commit": {
        put: op({
          operationId: "commitVideo",
          summary: "Record an uploaded video",
          scope: "journey:entries:write",
          parameters: [
            uuidPath("id", "The app's entry id."),
            { name: "key", in: "path", required: true, schema: { type: "string", pattern: "^[A-Za-z0-9_-]{1,128}$" } },
            { name: "taken_at", in: "query", schema: { type: "string", format: "date-time" } },
            { name: "sort_order", in: "query", schema: { type: "integer" } },
          ],
          requestBody: jsonBody({
            type: "object",
            required: ["storage_path"],
            properties: {
              storage_path: {
                type: "string",
                description: "The storage_path returned by upload-url for this key.",
              },
            },
          }),
          responses: { "404": errorResponse, "415": errorResponse },
        }),
      },
      "/api/v1/owner/invites": {
        get: op({ operationId: "listInvites", summary: "List invites", scope: "journey:invites:manage" }),
        post: op({
          operationId: "createInvite",
          summary: "Create an invite limited to tags",
          scope: "journey:invites:manage",
          requestBody: jsonBody({
            type: "object",
            required: ["name"],
            properties: {
              name: { type: "string", maxLength: 100 },
              tag_ids: { type: "array", items: { type: "string", format: "uuid" } },
            },
          }),
          responses: { "201": ok("Created; the token is returned only this once") },
        }),
      },
      "/api/v1/owner/invites/{id}": {
        delete: op({
          operationId: "revokeInvite",
          summary: "Revoke an invite",
          scope: "journey:invites:manage",
          parameters: [uuidPath("id", "Invite id.")],
          responses: { "404": errorResponse },
        }),
        patch: op({
          operationId: "setInviteTags",
          summary: "Replace which tags an invite may read",
          scope: "journey:invites:manage",
          parameters: [uuidPath("id", "Invite id.")],
          requestBody: jsonBody({
            type: "object",
            required: ["tag_ids"],
            properties: {
              tag_ids: {
                type: "array",
                items: { type: "string", format: "uuid" },
                description: "The invite's complete tag set. Tags not listed are removed.",
              },
            },
          }),
          responses: { "404": errorResponse },
        }),
      },
      "/api/v1/owner/invites/{id}/token": {
        post: op({
          operationId: "rotateInviteToken",
          summary: "Replace an invite's link",
          scope: "journey:invites:manage",
          parameters: [uuidPath("id", "Invite id.")],
          responses: {
            "200": ok("A new link; the old one stops working immediately"),
            "404": errorResponse,
            "409": errorResponse,
          },
        }),
      },
      "/api/v1/owner/comments": {
        get: op({
          operationId: "listCommentThreads",
          summary: "List reader conversations",
          scope: "journey:comments:manage",
          responses: { "200": ok("One thread per invitation per entry, newest first") },
        }),
      },
      "/api/v1/owner/comments/{id}": {
        delete: op({
          operationId: "deleteComment",
          summary: "Delete a comment",
          scope: "journey:comments:manage",
          parameters: [uuidPath("id", "Comment id.")],
          responses: { "404": errorResponse },
        }),
      },
      "/api/v1/owner/entries/{id}/comments": {
        get: op({
          operationId: "readCommentThread",
          summary: "Read one conversation",
          scope: "journey:comments:manage",
          parameters: [
            uuidPath("id", "The app's entry id."),
            {
              name: "invite",
              in: "query",
              required: true,
              schema: { type: "string", format: "uuid" },
              description: "Which invitation's thread to read.",
            },
          ],
        }),
        post: op({
          operationId: "replyToComment",
          summary: "Reply in a conversation",
          scope: "journey:comments:manage",
          parameters: [uuidPath("id", "The app's entry id.")],
          requestBody: jsonBody({
            type: "object",
            required: ["invite_id", "body"],
            properties: {
              invite_id: { type: "string", format: "uuid" },
              body: { type: "string", maxLength: 2000 },
            },
          }),
          responses: { "201": ok("Replied"), "409": errorResponse },
        }),
        patch: op({
          operationId: "markCommentsSeen",
          summary: "Mark a conversation as seen",
          scope: "journey:comments:manage",
          parameters: [uuidPath("id", "The app's entry id.")],
          requestBody: jsonBody({
            type: "object",
            required: ["invite_id"],
            properties: { invite_id: { type: "string", format: "uuid" } },
          }),
        }),
      },
      "/api/v1/owner/proposals": {
        get: op({
          operationId: "listProposals",
          summary: "List story proposals",
          scope: "journey:proposals:decide",
          parameters: [
            {
              name: "status",
              in: "query",
              schema: { type: "string", enum: ["pending", "accepted", "rejected", "superseded", "all"] },
            },
          ],
        }),
      },
      "/api/v1/owner/proposals/{id}/decision": {
        post: op({
          operationId: "decideProposal",
          summary: "Accept or reject a proposal",
          scope: "journey:proposals:decide",
          parameters: [uuidPath("id", "Proposal id.")],
          requestBody: jsonBody({
            type: "object",
            required: ["decision"],
            properties: { decision: { type: "string", enum: ["accepted", "rejected"] } },
          }),
          responses: { "404": errorResponse, "409": errorResponse },
        }),
      },
    },
  };
}
