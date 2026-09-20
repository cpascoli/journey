import type { Metadata } from "next";
import type { ReactNode } from "react";

import { currentLanguage } from "@/lib/i18n/current";

import "./globals.css";

export const metadata: Metadata = {
  title: "Journey",
  description: "A private travel journal, shared with the people invited to read it.",
};

export default async function RootLayout({ children }: { children: ReactNode }) {
  // Screen readers and translation tools key off this, so it has to follow
  // the language the page actually renders in.
  const language = await currentLanguage();
  return (
    <html lang={language}>
      <body>{children}</body>
    </html>
  );
}
