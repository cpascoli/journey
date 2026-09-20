import Link from "next/link";

import { LANGUAGES, type Language } from "@/lib/domain/language";
import { stringsFor } from "@/lib/i18n/strings";

/** Three vertical bands. */
function ItalianFlag() {
  return (
    <svg viewBox="0 0 60 30" aria-hidden="true" focusable="false">
      <rect width="20" height="30" fill="#008C45" />
      <rect x="20" width="20" height="30" fill="#F4F5F0" />
      <rect x="40" width="20" height="30" fill="#CD212A" />
    </svg>
  );
}

/**
 * A simplified Union Jack: the saltires are not counterchanged, which keeps
 * it legible at 20 pixels wide where the real offset would just blur.
 */
function BritishFlag() {
  return (
    <svg viewBox="0 0 60 30" aria-hidden="true" focusable="false">
      <rect width="60" height="30" fill="#012169" />
      <path d="M0 0l60 30M60 0L0 30" stroke="#FFF" strokeWidth="6" />
      <path d="M0 0l60 30M60 0L0 30" stroke="#C8102E" strokeWidth="3" />
      <path d="M30 0v30M0 15h60" stroke="#FFF" strokeWidth="10" />
      <path d="M30 0v30M0 15h60" stroke="#C8102E" strokeWidth="6" />
    </svg>
  );
}

const FLAGS: Record<Language, () => React.JSX.Element> = {
  en: BritishFlag,
  it: ItalianFlag,
};

/**
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
        const Flag = FLAGS[code];
        const isCurrent = code === language;
        return (
          <Link
            aria-current={isCurrent ? "true" : undefined}
            aria-label={labels[code]}
            className={`flag${isCurrent ? " current" : ""}`}
            href={`/lang/${code}?next=${encodeURIComponent(next)}`}
            key={code}
            prefetch={false}
            title={labels[code]}
          >
            <Flag />
          </Link>
        );
      })}
    </nav>
  );
}
