/** Invitees see one text version, never notes alongside a narrative. */
export function readerText(narrative: string, notes: string): string {
  return narrative.trim().length > 0 ? narrative : notes;
}

