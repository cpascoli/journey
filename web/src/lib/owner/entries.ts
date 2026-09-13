import { validationError } from "@/lib/api/errors";
import {
  asObject,
  dateField,
  dateTimeField,
  enumField,
  nullableString,
  numberField,
  stringField,
  uuidArrayField,
  type JsonObject,
} from "@/lib/api/validate";
import { shareLocation, type LocationPrecision } from "@/lib/domain/location";
import type { Visibility } from "@/lib/domain/visibility";

import { MEDIA_KEY_PATTERN } from "./media";

export const NARRATIVE_SOURCES = ["user", "on_device", "chatgpt"] as const;
export const PRECISIONS = ["exact", "neighborhood", "city", "hidden"] as const satisfies readonly LocationPrecision[];
export const VISIBILITIES = ["private", "shared"] as const satisfies readonly Visibility[];

const MAX_TEXT = 20_000;
const MAX_TAGS = 50;
const MAX_MEDIA = 100;

/** Columns handed to public.save_entry; location already reduced to its precision. */
export type EntryFields = {
  journal_name: string;
  occurred_at: string;
  day: string;
  title: string;
  notes: string;
  narrative: string;
  narrative_source: (typeof NARRATIVE_SOURCES)[number];
  place_name: string | null;
  latitude: number | null;
  longitude: number | null;
  location_precision: LocationPrecision;
  translation_language: string;
  translated_title: string;
  translated_notes: string;
  translated_narrative: string;
  visibility: Visibility;
};

export type EntryWrite = {
  fields: EntryFields;
  tagIds: string[];
  /** The entry's full, ordered set of media keys, or null to leave media alone. */
  mediaKeys: string[] | null;
};

export function parseEntryWrite(body: unknown): EntryWrite {
  const obj = asObject(body);
  const precision = enumField(obj, "location_precision", PRECISIONS, "city");
  const location = obj.location == null ? {} : asObject(obj.location, "location");
  const shared = shareLocation(
    {
      placeName: nullableString(location, "place_name", { max: 200 }),
      locality: nullableString(location, "locality", { max: 200 }),
      latitude: numberField(location, "latitude", { min: -90, max: 90 }),
      longitude: numberField(location, "longitude", { min: -180, max: 180 }),
    },
    precision,
  );
  const translation = obj.translation == null ? null : asObject(obj.translation, "translation");

  return {
    fields: {
      journal_name: stringField(obj, "journal_name", { max: 100 }).trim() || "Main",
      occurred_at: dateTimeField(obj, "occurred_at"),
      day: dateField(obj, "day"),
      title: stringField(obj, "title", { max: 300 }),
      notes: stringField(obj, "notes", { max: MAX_TEXT }),
      narrative: stringField(obj, "narrative", { max: MAX_TEXT }),
      narrative_source: enumField(obj, "narrative_source", NARRATIVE_SOURCES, "user"),
      place_name: shared.placeName,
      latitude: shared.latitude,
      longitude: shared.longitude,
      location_precision: precision,
      translation_language: translation
        ? stringField(translation, "language", { max: 10, required: true })
        : "",
      translated_title: translation ? stringField(translation, "title", { max: 300 }) : "",
      translated_notes: translation ? stringField(translation, "notes", { max: MAX_TEXT }) : "",
      translated_narrative: translation ? stringField(translation, "narrative", { max: MAX_TEXT }) : "",
      // Private unless the app says otherwise: a missing field never shares.
      visibility: enumField(obj, "visibility", VISIBILITIES, "private"),
    },
    tagIds: uuidArrayField(obj, "tag_ids", { max: MAX_TAGS }),
    mediaKeys: parseMediaKeys(obj),
  };
}

function parseMediaKeys(obj: JsonObject): string[] | null {
  const value = obj.media_keys;
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value) || value.length > MAX_MEDIA) {
    throw validationError(`media_keys must be an array of at most ${MAX_MEDIA} keys.`, {
      field: "media_keys",
    });
  }
  const keys = value.map((key, index) => {
    if (typeof key !== "string" || !MEDIA_KEY_PATTERN.test(key)) {
      throw validationError(`media_keys[${index}] must match ${MEDIA_KEY_PATTERN.source}.`, {
        field: `media_keys[${index}]`,
      });
    }
    return key;
  });
  return [...new Set(keys)];
}
