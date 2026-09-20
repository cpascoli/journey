import type { Language } from "@/lib/domain/language";

import { LanguageToggle } from "./LanguageToggle";

/**
 * The bar across the top of every reader page: what you are looking at on the
 * left, the language flags on the right.
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
  return (
    <header className="site-header">
      <div className="site-header-text">
        {eyebrow && <p className="eyebrow">{eyebrow}</p>}
        {title && <h1>{title}</h1>}
      </div>
      <LanguageToggle language={language} next={next} />
    </header>
  );
}
