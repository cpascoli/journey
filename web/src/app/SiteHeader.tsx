import Link from "next/link";

import type { Language } from "@/lib/domain/language";
import { stringsFor } from "@/lib/i18n/strings";

import { LanguageToggle } from "./LanguageToggle";

/**
 * The bar across the top of every reader page: the wordmark, which leads back
 * to the journal, who it is shared with, and the language switch. A `title`
 * becomes the page's masthead underneath.
 */
export function SiteHeader({
  language,
  next,
  eyebrow,
  title,
}: {
  language: Language;
  next: string;
  eyebrow?: string;
  title?: string;
}) {
  const strings = stringsFor(language);
  return (
    <>
      <header className="site-header">
        <Link className="wordmark" href="/read">{strings.siteName}</Link>
        {eyebrow && <p className="site-header-eyebrow">{eyebrow}</p>}
        <LanguageToggle language={language} next={next} />
      </header>
      {title && <h1 className="masthead">{title}</h1>}
    </>
  );
}
