import type { Metadata } from "next";
import { Geist, Geist_Mono, Newsreader } from "next/font/google";
import type { ReactNode } from "react";

import { currentLanguage } from "@/lib/i18n/current";

import "./globals.css";

// Three faces with one job each: Geist for structure, Geist Mono for facts
// (dates, places, counts), Newsreader for the writing. next/font serves them
// from this site, so a reader's browser never asks Google for anything.
const sans = Geist({ subsets: ["latin"], variable: "--font-sans", display: "swap" });
const mono = Geist_Mono({ subsets: ["latin"], variable: "--font-mono", display: "swap" });
const serif = Newsreader({
  subsets: ["latin"],
  style: ["normal", "italic"],
  variable: "--font-serif",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Journey",
  description: "A private travel journal, shared with the people invited to read it.",
};

export default async function RootLayout({ children }: { children: ReactNode }) {
  // Screen readers and translation tools key off this, so it has to follow
  // the language the page actually renders in.
  const language = await currentLanguage();
  return (
    <html className={`${sans.variable} ${mono.variable} ${serif.variable}`} lang={language}>
      <body>{children}</body>
    </html>
  );
}
