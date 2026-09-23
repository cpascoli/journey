import type { Language } from "@/lib/domain/language";
import { stringsFor } from "@/lib/i18n/strings";

/** Where the journal's source lives. Public, so the link is worth having. */
const REPOSITORY = "https://github.com/cpascoli/journey";

/**
 * A quiet line at the end of every page a reader sees.
 *
 * The year is read at render time rather than written into the source, so it
 * cannot silently go stale.
 */
export function SiteFooter({ language }: { language: Language }) {
  const strings = stringsFor(language);
  return (
    <footer className="site-footer">
      <p>{strings.builtBy(new Date().getFullYear())}</p>
      <p>
        <a href={REPOSITORY} rel="noopener noreferrer" target="_blank">
          {strings.sourceOnGitHub}
        </a>
      </p>
    </footer>
  );
}
