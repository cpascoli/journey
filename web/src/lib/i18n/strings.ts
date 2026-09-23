import type { Language } from "@/lib/domain/language";

/**
 * The site's own words. Journal text is not here: entries carry their own
 * translations from the app (see `entryTextFor`).
 *
 * Kept as one record per language rather than a lookup with fallbacks, so a
 * missing Italian string is a type error rather than an English word
 * appearing mid-sentence in production.
 */
export type Strings = {
  localeTag: string;
  siteName: string;
  sharedWith: (name: string) => string;
  untitledEntry: string;
  noStories: string;
  noOlderStories: string;
  olderEntries: string;
  backToNewest: string;
  allEntries: string;
  returnToJournal: string;
  invitationUnavailable: string;
  invitationUnavailableLede: string;
  invitationWithdrawn: string;
  invitationWithdrawnLede: string;
  entryUnavailable: string;
  entryUnavailableLede: string;
  homeEyebrow: string;
  homeLede: string;
  homeNote: string;
  openMedia: string;
  closeMedia: string;
  photoAlt: (index: number) => string;
  videoAlt: (index: number) => string;
  videoUnsupported: string;
  switchToEnglish: string;
  switchToItalian: string;
  filters: string;
  search: string;
  searchPlaceholder: string;
  searchAction: string;
  allTags: string;
  when: string;
  lastWeek: string;
  lastMonth: string;
  allTime: string;
  clearFilters: string;
  showingCount: (matching: number, total: number) => string;
  noMatches: string;
  sourceOnGitHub: string;
  moreMedia: (count: number) => string;
  readEntry: string;
  seeAllMedia: (count: number) => string;
  builtBy: (year: number) => string;
  conversation: string;
  noComments: (inviteName: string) => string;
  commentPlaceholder: string;
  sendComment: string;
  you: string;
  fromOwner: string;
  commentRefusedBody: string;
  commentRefusedTooMany: string;
  commentRefusedUnavailable: string;
};

const en: Strings = {
  localeTag: "en-GB",
  siteName: "Journey",
  sharedWith: (name) => `Shared with ${name}`,
  untitledEntry: "Untitled entry",
  noStories: "There are no shared stories yet.",
  noOlderStories: "There are no older stories.",
  olderEntries: "Older entries",
  backToNewest: "Back to the newest",
  allEntries: "All entries",
  returnToJournal: "Return to the journal",
  invitationUnavailable: "Invitation unavailable",
  invitationUnavailableLede:
    "This invitation is invalid or is no longer active. Open your invitation link again to start reading.",
  invitationWithdrawn: "This invitation was withdrawn",
  invitationWithdrawnLede:
    "It no longer opens the journal. If you think that's a mistake, ask whoever shared it with you for a new link.",
  entryUnavailable: "Entry unavailable",
  entryUnavailableLede: "This entry is not available with the current invitation.",
  homeEyebrow: "A travel journal",
  homeLede:
    "Places, photos and the stories around them — written on the road, and shared only with the people invited to read along.",
  homeNote: "If you were sent an invitation link, open it to start reading.",
  openMedia: "Open full screen",
  closeMedia: "Close",
  photoAlt: (index) => `Journey photo ${index}`,
  videoAlt: (index) => `Journey video ${index}`,
  videoUnsupported: "Your browser cannot play this video.",
  switchToEnglish: "Read in English",
  switchToItalian: "Leggi in italiano",
  filters: "Filter",
  search: "Search",
  searchPlaceholder: "Words, a place, a tag…",
  searchAction: "Search",
  allTags: "Everything",
  when: "When",
  lastWeek: "Last week",
  lastMonth: "Last month",
  allTime: "All time",
  clearFilters: "Clear filters",
  showingCount: (matching, total) =>
    matching === total ? `${total} entries` : `${matching} of ${total} entries`,
  noMatches: "No entries match these filters.",
  sourceOnGitHub: "Source on GitHub",
  moreMedia: (count) => `+${count}`,
  seeAllMedia: (count) => `See all ${count} photos and videos`,
  readEntry: "Read this entry",
  builtBy: (year) => `© ${year} Carlo Pascoli`,
  conversation: "Comments",
  noComments: (inviteName) => `${inviteName}, add a comment.`,
  commentPlaceholder: "Write a comment…",
  sendComment: "Send",
  you: "You",
  fromOwner: "Carlo",
  commentRefusedBody: "A comment needs some text, and at most 2000 characters.",
  commentRefusedTooMany: "That's a lot of comments at once. Try again in a little while.",
  commentRefusedUnavailable: "This comment could not be added.",
};

const it: Strings = {
  localeTag: "it-IT",
  siteName: "Journey",
  sharedWith: (name) => `Condiviso con ${name}`,
  untitledEntry: "Voce senza titolo",
  noStories: "Non ci sono ancora racconti condivisi.",
  noOlderStories: "Non ci sono voci precedenti.",
  olderEntries: "Voci precedenti",
  backToNewest: "Torna alle più recenti",
  allEntries: "Tutte le voci",
  returnToJournal: "Torna al diario",
  invitationUnavailable: "Invito non disponibile",
  invitationUnavailableLede:
    "Questo invito non è valido o non è più attivo. Apri di nuovo il link dell'invito per iniziare a leggere.",
  invitationWithdrawn: "Questo invito è stato revocato",
  invitationWithdrawnLede:
    "Non dà più accesso al diario. Se pensi che sia un errore, chiedi un nuovo link a chi te l'ha condiviso.",
  entryUnavailable: "Voce non disponibile",
  entryUnavailableLede: "Questa voce non è disponibile con l'invito attuale.",
  homeEyebrow: "Diario di viaggio",
  homeLede:
    "Luoghi, foto e le storie che li accompagnano — scritti in viaggio, e condivisi solo con chi è invitato a leggerli.",
  homeNote: "Se hai ricevuto un link d'invito, aprilo per iniziare a leggere.",
  openMedia: "Apri a schermo intero",
  closeMedia: "Chiudi",
  photoAlt: (index) => `Foto ${index} del diario`,
  videoAlt: (index) => `Video ${index} del diario`,
  videoUnsupported: "Il tuo browser non può riprodurre questo video.",
  switchToEnglish: "Read in English",
  switchToItalian: "Leggi in italiano",
  filters: "Filtra",
  search: "Cerca",
  searchPlaceholder: "Parole, un luogo, un tag…",
  searchAction: "Cerca",
  allTags: "Tutto",
  when: "Quando",
  lastWeek: "Ultima settimana",
  lastMonth: "Ultimo mese",
  allTime: "Sempre",
  clearFilters: "Azzera i filtri",
  showingCount: (matching, total) =>
    matching === total
      ? `${total} voci`
      : `${matching} di ${total} voci`,
  noMatches: "Nessuna voce corrisponde a questi filtri.",
  sourceOnGitHub: "Codice su GitHub",
  moreMedia: (count) => `+${count}`,
  seeAllMedia: (count) => `Vedi tutte le ${count} foto e video`,
  readEntry: "Leggi questa voce",
  builtBy: (year) => `© ${year} Carlo Pascoli`,
  conversation: "Commenti",
  noComments: (inviteName) => `${inviteName}, aggiungi un commento.`,
  commentPlaceholder: "Scrivi un commento…",
  sendComment: "Invia",
  you: "Tu",
  fromOwner: "Carlo",
  commentRefusedBody: "Un commento deve avere del testo, e al massimo 2000 caratteri.",
  commentRefusedTooMany: "Troppi commenti in una volta. Riprova tra poco.",
  commentRefusedUnavailable: "Non è stato possibile aggiungere il commento.",
};

const BY_LANGUAGE: Record<Language, Strings> = { en, it };

export function stringsFor(language: Language): Strings {
  return BY_LANGUAGE[language];
}

/** The day as the writer saw it, formatted in the reader's language. */
export function formatDay(day: string, language: Language): string {
  return new Intl.DateTimeFormat(stringsFor(language).localeTag, {
    dateStyle: "long",
    timeZone: "UTC",
  }).format(new Date(`${day}T12:00:00Z`));
}
