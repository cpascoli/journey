"use client";

import { useActionState } from "react";

import { saveEntryText, type EditTextState } from "@/app/owner/actions";

export type EditableText = {
  id: string;
  title: string;
  notes: string;
  narrative: string;
  translation_language: string;
  translated_title: string;
  translated_notes: string;
  translated_narrative: string;
};

const initialState: EditTextState = {};

/**
 * Corrects an entry's text, in both languages, side by side.
 *
 * Readers see the story; where an entry has no story they see the notes, so
 * both are editable rather than hiding the one that happens to be showing.
 */
export function EditTextForm({ entry }: { entry: EditableText }) {
  const [state, action, pending] = useActionState(saveEntryText, initialState);

  return (
    <form action={action} className="edit-text">
      <input name="id" type="hidden" value={entry.id} />

      <div className="edit-columns">
        <fieldset>
          <legend>As written</legend>
          <label htmlFor="title">Title</label>
          <input defaultValue={entry.title} id="title" maxLength={300} name="title" />
          <label htmlFor="narrative">Story</label>
          <textarea defaultValue={entry.narrative} id="narrative" name="narrative" rows={8} />
          <label htmlFor="notes">Notes</label>
          <textarea defaultValue={entry.notes} id="notes" name="notes" rows={4} />
        </fieldset>

        <fieldset>
          <legend>Translation</legend>
          <label htmlFor="translation_language">Language</label>
          <select
            defaultValue={entry.translation_language}
            id="translation_language"
            name="translation_language"
          >
            <option value="">No translation</option>
            <option value="it">Italian</option>
            <option value="en">English</option>
          </select>
          <label htmlFor="translated_title">Title</label>
          <input
            defaultValue={entry.translated_title}
            id="translated_title"
            maxLength={300}
            name="translated_title"
          />
          <label htmlFor="translated_narrative">Story</label>
          <textarea
            defaultValue={entry.translated_narrative}
            id="translated_narrative"
            name="translated_narrative"
            rows={8}
          />
          <label htmlFor="translated_notes">Notes</label>
          <textarea
            defaultValue={entry.translated_notes}
            id="translated_notes"
            name="translated_notes"
            rows={4}
          />
        </fieldset>
      </div>

      <p className="panel-note">
        Readers see the story, or the notes when there is no story. A reader
        gets the translation when it is in their language, and the original
        otherwise.
      </p>
      <p className="panel-note warning">
        The iPhone app is the source of truth. If you tap <strong>Update Website</strong> on
        this entry there — or rename a tag, which republishes — the app&apos;s text replaces
        whatever you save here.
      </p>

      {state.error && <p className="form-error" role="alert">{state.error}</p>}
      {state.saved && <p className="form-saved" role="status">Saved.</p>}
      <button disabled={pending} type="submit">{pending ? "Saving…" : "Save text"}</button>
    </form>
  );
}
