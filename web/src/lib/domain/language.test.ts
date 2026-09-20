import { describe, expect, it } from "vitest";

import {
  entryTextFor,
  parseLanguage,
  preferredLanguage,
  resolveLanguage,
  type TranslatableEntry,
} from "./language";

function entry(overrides: Partial<TranslatableEntry> = {}): TranslatableEntry {
  return {
    title: "Temple of Dawn",
    notes: "Notes in English",
    narrative: "The story in English",
    translation_language: "",
    translated_title: "",
    translated_notes: "",
    translated_narrative: "",
    ...overrides,
  };
}

describe("parseLanguage", () => {
  it("accepts only the languages the site has", () => {
    expect(parseLanguage("it")).toBe("it");
    expect(parseLanguage("en")).toBe("en");
    expect(parseLanguage("fr")).toBeNull();
    expect(parseLanguage(undefined)).toBeNull();
    // A cookie is reader-supplied, so anything unexpected must not pass through.
    expect(parseLanguage("<script>")).toBeNull();
  });
});

describe("preferredLanguage", () => {
  it("prefers Italian when the browser asks for it", () => {
    expect(preferredLanguage("it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7")).toBe("it");
  });

  it("reads a regional tag as its base language", () => {
    expect(preferredLanguage("it-CH")).toBe("it");
  });

  it("uses English for a browser that prefers it", () => {
    expect(preferredLanguage("en-GB,en;q=0.9,it;q=0.8")).toBe("en");
  });

  it("obeys quality values rather than header order", () => {
    expect(preferredLanguage("en;q=0.5,it;q=0.9")).toBe("it");
  });

  it("keeps header order when weights tie", () => {
    expect(preferredLanguage("en,it")).toBe("en");
    expect(preferredLanguage("it,en")).toBe("it");
  });

  it("ignores a language it cannot show", () => {
    expect(preferredLanguage("fr-FR,fr;q=0.9,it;q=0.4")).toBe("it");
    expect(preferredLanguage("fr-FR,de;q=0.9")).toBe("en");
  });

  it("ignores an explicitly refused language", () => {
    expect(preferredLanguage("it;q=0,en;q=0.5")).toBe("en");
  });

  it("falls back to English for a missing or odd header", () => {
    expect(preferredLanguage(null)).toBe("en");
    expect(preferredLanguage("")).toBe("en");
    expect(preferredLanguage("*")).toBe("en");
    expect(preferredLanguage("it;q=bogus")).toBe("en");
  });
});

describe("resolveLanguage", () => {
  it("lets an explicit choice beat the browser preference", () => {
    expect(resolveLanguage("en", "it-IT,it;q=0.9")).toBe("en");
    expect(resolveLanguage("it", "en-GB,en;q=0.9")).toBe("it");
  });

  it("falls back to the browser when no choice was made", () => {
    expect(resolveLanguage(undefined, "it-IT")).toBe("it");
    expect(resolveLanguage(null, "en-GB")).toBe("en");
  });

  it("ignores a cookie that is not a language it has", () => {
    expect(resolveLanguage("de", "it-IT")).toBe("it");
  });
});

describe("entryTextFor", () => {
  it("shows the translation when it is in the reader's language", () => {
    const result = entryTextFor("it", entry({
      translation_language: "it",
      translated_title: "Tempio dell'Alba",
      translated_narrative: "La storia in italiano",
    }));
    expect(result.title).toBe("Tempio dell'Alba");
    expect(result.text).toBe("La storia in italiano");
    expect(result.isTranslated).toBe(true);
  });

  /**
   * The app tags a translation with the language it is *into*, so the same
   * rule works for an entry written in Italian and translated to English.
   */
  it("works whichever language the entry was written in", () => {
    const italianOriginal = entry({
      title: "Tempio dell'Alba",
      narrative: "La storia in italiano",
      notes: "",
      translation_language: "en",
      translated_title: "Temple of Dawn",
      translated_narrative: "The story in English",
    });
    expect(entryTextFor("en", italianOriginal).text).toBe("The story in English");
    expect(entryTextFor("it", italianOriginal).text).toBe("La storia in italiano");
  });

  it("shows the original when there is no translation, rather than hiding it", () => {
    const result = entryTextFor("it", entry());
    expect(result.title).toBe("Temple of Dawn");
    expect(result.text).toBe("The story in English");
    expect(result.isTranslated).toBe(false);
  });

  it("shows the original when the translation is into another language", () => {
    const result = entryTextFor("it", entry({
      translation_language: "fr",
      translated_narrative: "L'histoire en francais",
    }));
    expect(result.text).toBe("The story in English");
  });

  it("falls back per field, since a title may be untranslated on its own", () => {
    const result = entryTextFor("it", entry({
      translation_language: "it",
      translated_title: "   ",
      translated_narrative: "La storia in italiano",
    }));
    expect(result.title).toBe("Temple of Dawn");
    expect(result.text).toBe("La storia in italiano");
  });

  it("still keeps notes out of sight when a narrative exists", () => {
    const result = entryTextFor("it", entry({
      translation_language: "it",
      translated_notes: "Appunti privati",
      translated_narrative: "La storia in italiano",
    }));
    expect(result.text).toBe("La storia in italiano");
    expect(result.text).not.toContain("Appunti");
  });

  it("uses translated notes when there is no narrative at all", () => {
    const result = entryTextFor("it", entry({
      narrative: "",
      translation_language: "it",
      translated_notes: "Appunti di viaggio",
    }));
    expect(result.text).toBe("Appunti di viaggio");
  });
});
