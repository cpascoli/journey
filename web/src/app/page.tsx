import { currentLanguage } from "@/lib/i18n/current";
import { stringsFor } from "@/lib/i18n/strings";

import { LanguageToggle } from "./LanguageToggle";

export const dynamic = "force-dynamic";

export default async function Home() {
  const language = await currentLanguage();
  const strings = stringsFor(language);
  return (
    <main className="page">
      <div className="page-top">
        <p className="eyebrow">{strings.homeEyebrow}</p>
        <LanguageToggle language={language} next="/" />
      </div>
      <h1>{strings.siteName}</h1>
      <p className="lede">{strings.homeLede}</p>
      <p className="note">{strings.homeNote}</p>
    </main>
  );
}
