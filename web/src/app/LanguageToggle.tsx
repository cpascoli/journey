import Link from "next/link";

import { LANGUAGES, type Language } from "@/lib/domain/language";
import { stringsFor } from "@/lib/i18n/strings";

/**
 * The two language codes, the current one underlined. Text rather than flags:
 * a flag names a country, not a language, and the codes sit in the same
 * monospace as the rest of the bar.
 *
 * Switching language is a link, not a script: it works with JavaScript off,
 * and the route it points at records the choice in a cookie so the next visit
 * opens in the same language.
 *
 * `next` is where to come back to, and the route only accepts a path on this
 * site.
 */
export function LanguageToggle({ language, next }: { language: Language; next: string }) {
  const strings = stringsFor(language);
  const labels: Record<Language, string> = {
    en: strings.switchToEnglish,
    it: strings.switchToItalian,
  };

  return (
    <nav className="language-toggle" aria-label={language === "it" ? "Lingua" : "Language"}>
      {LANGUAGES.map((code) => {
        const isCurrent = code === language;
        return (
          <Link
            aria-current={isCurrent ? "true" : undefined}
            aria-label={labels[code]}
            className={`language${isCurrent ? " current" : ""}`}
            href={`/lang/${code}?next=${encodeURIComponent(next)}`}
            key={code}
            prefetch={false}
            title={labels[code]}
          >
            {code.toUpperCase()}
          </Link>
        );
      })}
    </nav>
  );
}
