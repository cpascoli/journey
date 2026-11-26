import { Archivo, IBM_Plex_Mono } from "next/font/google";

// The personal pages have their own two faces, apart from the journal's:
// Archivo for everything said, IBM Plex Mono for facts (track numbers, years,
// addresses). next/font serves both from this site.
export const display = Archivo({ subsets: ["latin"], variable: "--font-display", display: "swap" });
export const facts = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-facts",
  display: "swap",
});

export const personalFonts = `${display.variable} ${facts.variable}`;
