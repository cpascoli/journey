import { readerText } from "./reader";

/** The two languages the journal is written and read in. */
export const LANGUAGES = ["en", "it"] as const;

export type Language = (typeof LANGUAGES)[number];

export const DEFAULT_LANGUAGE: Language = "en";

/** Remembers a reader's choice. Not a credential: it carries no access at all. */
export const LANGUAGE_COOKIE = "journey-lang";

export function isLanguage(value: unknown): value is Language {
  return typeof value === "string" && (LANGUAGES as readonly string[]).includes(value);
}

export function parseLanguage(value: string | null | undefined): Language | null {
  return isLanguage(value) ? value : null;
}

type Ranked = { tag: string; quality: number };

/**
 * The language an `Accept-Language` header asks for, when it asks for one we
 * have. Regional tags count for their base language, so `it-CH` is Italian.
 * Anything else falls back to English rather than guessing.
 */
export function preferredLanguage(header: string | null | undefined): Language {
  if (!header) return DEFAULT_LANGUAGE;

  const ranked: Ranked[] = [];
  for (const part of header.split(",")) {
    const [rawTag, ...parameters] = part.trim().split(";");
    const tag = (rawTag ?? "").trim().toLowerCase();
    if (!tag) continue;
    // "q=0.8"; a missing q means 1, and a malformed one means skip.
    const qualityParameter = parameters.map((p) => p.trim()).find((p) => p.startsWith("q="));
    const quality = qualityParameter === undefined ? 1 : Number(qualityParameter.slice(2));
    if (!Number.isFinite(quality) || quality <= 0) continue;
    ranked.push({ tag, quality });
  }

  // A stable sort keeps header order among equal weights, which is what
  // "en,it" means: English first.
  ranked.sort((left, right) => right.quality - left.quality);

  for (const { tag } of ranked) {
    if (tag === "*") return DEFAULT_LANGUAGE;
    const base = tag.split("-")[0];
    if (isLanguage(base)) return base;
  }
  return DEFAULT_LANGUAGE;
}

/**
 * The reader's language: an explicit choice wins over the browser's
 * preference, so toggling the flags sticks on the next visit.
 */
export function resolveLanguage(
  cookie: string | null | undefined,
  acceptLanguage: string | null | undefined,
): Language {
  return parseLanguage(cookie) ?? preferredLanguage(acceptLanguage);
}

export type TranslatableEntry = {
  title: string;
  notes: string;
  narrative: string;
  translation_language: string;
  translated_title: string;
  translated_notes: string;
  translated_narrative: string;
};

/**
 * An entry as the reader should see it in their language.
 *
 * The app stores one translation per entry, tagged with the language it is
 * *into*, so matching that tag against the reader's choice works whichever
 * language the entry was written in. An entry with no matching translation is
 * shown as written rather than hidden: a reader was invited to read the
 * journal, not a subset of it.
 *
 * Each field falls back on its own, because the app can translate a narrative
 * while leaving an untitled entry's title empty.
 */
export function entryTextFor(
  language: Language,
  entry: TranslatableEntry,
): { title: string; text: string; isTranslated: boolean } {
  const translated = entry.translation_language === language;
  const pick = (candidate: string, original: string) =>
    translated && candidate.trim().length > 0 ? candidate : original;

  const title = pick(entry.translated_title, entry.title);
  const text = readerText(
    pick(entry.translated_narrative, entry.narrative),
    pick(entry.translated_notes, entry.notes),
  );
  return {
    title,
    text,
    isTranslated: translated && text.trim().length > 0 && text !== readerText(entry.narrative, entry.notes),
  };
}
