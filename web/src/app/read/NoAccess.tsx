import Link from "next/link";

import type { Language } from "@/lib/domain/language";
import { stringsFor } from "@/lib/i18n/strings";

import { LanguageToggle } from "../LanguageToggle";
import { SiteFooter } from "../SiteFooter";

/**
 * A revoked invitation is not the same as a broken link, and saying so saves
 * the reader from chasing a problem that isn't theirs. Neither message reveals
 * whether any particular entry or journal exists.
 */
export function NoAccess({
  language,
  status,
  entry = false,
}: {
  language: Language;
  status: "none" | "revoked";
  entry?: boolean;
}) {
  const strings = stringsFor(language);
  const [heading, lede] = status === "revoked"
    ? [strings.invitationWithdrawn, strings.invitationWithdrawnLede]
    : entry
      ? [strings.entryUnavailable, strings.entryUnavailableLede]
      : [strings.invitationUnavailable, strings.invitationUnavailableLede];

  return (
    <main className="page compact">
      <div className="page-top">
        <p className="eyebrow">{strings.siteName}</p>
        <LanguageToggle language={language} next={entry ? "/read" : "/read"} />
      </div>
      <h1>{heading}</h1>
      <p className="lede">{lede}</p>
      {entry && status !== "revoked" && <Link href="/read">{strings.returnToJournal}</Link>}
      <SiteFooter language={language} />
    </main>
  );
}
