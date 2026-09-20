"use client";

import { useCallback, useEffect, useRef, useState } from "react";

import type { Language } from "@/lib/domain/language";
import { stringsFor } from "@/lib/i18n/strings";

type Media = {
  key: string;
  kind: "photo" | "video";
  width: number | null;
  height: number | null;
  durationSeconds: number | null;
};

/**
 * Photos and videos share one source: /media/[entryId]/[key] re-checks who is
 * asking and redirects to a short-lived signed URL. Videos are never embedded
 * from a third party, so a clip is reachable only while the invite that can
 * read its entry still can.
 *
 * Tapping an item opens it in a modal `<dialog>`, which is full screen on a
 * phone and an overlay on a wider screen. Using the native element rather than
 * a div means Escape, focus trapping and inertness come from the browser.
 */
export function MediaGrid({
  entryId,
  media,
  language,
  compact = false,
}: {
  entryId: string;
  media: Media[];
  language: Language;
  compact?: boolean;
}) {
  const strings = stringsFor(language);
  const [openIndex, setOpenIndex] = useState<number | null>(null);
  const dialogRef = useRef<HTMLDialogElement>(null);

  const close = useCallback(() => setOpenIndex(null), []);
  const step = useCallback(
    (by: number) =>
      setOpenIndex((current) =>
        current === null ? null : (current + by + media.length) % media.length,
      ),
    [media.length],
  );

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) return;
    if (openIndex === null) {
      if (dialog.open) dialog.close();
      return;
    }
    if (!dialog.open) dialog.showModal();
  }, [openIndex]);

  useEffect(() => {
    if (openIndex === null) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "ArrowRight") step(1);
      if (event.key === "ArrowLeft") step(-1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [openIndex, step]);

  if (media.length === 0) return null;
  const source = (item: Media) => `/media/${entryId}/${encodeURIComponent(item.key)}`;
  const open = openIndex === null ? null : media[openIndex];
  const label = (item: Media, index: number) =>
    item.kind === "video" ? strings.videoAlt(index + 1) : strings.photoAlt(index + 1);

  return (
    <>
      <div className={`photo-grid${compact ? " compact-photos" : ""}`}>
        {media.map((item, index) => (
          <button
            aria-label={`${label(item, index)} — ${strings.openMedia}`}
            className="media-item"
            key={item.key}
            onClick={() => setOpenIndex(index)}
            type="button"
          >
            {item.kind === "video" ? (
              <>
                {/* Muted and controlless in the grid: the first frame stands in
                    for a poster, and tapping opens it rather than playing it. */}
                <video height={item.height ?? undefined} muted playsInline preload="metadata" width={item.width ?? undefined}>
                  <source src={source(item)} type="video/mp4" />
                </video>
                <span aria-hidden="true" className="play-badge" />
              </>
            ) : (
              <img
                alt={label(item, index)}
                height={item.height ?? undefined}
                loading="lazy"
                src={source(item)}
                width={item.width ?? undefined}
              />
            )}
          </button>
        ))}
      </div>

      <dialog
        className="media-viewer"
        onClick={(event) => {
          // Clicking the backdrop closes; clicking the media itself must not.
          if (event.target === dialogRef.current) close();
        }}
        onClose={close}
        ref={dialogRef}
      >
        {open && (
          <>
            <button aria-label={strings.closeMedia} className="viewer-close" onClick={close} type="button">
              ×
            </button>
            {media.length > 1 && (
              <>
                <button aria-label="‹" className="viewer-step previous" onClick={() => step(-1)} type="button">
                  ‹
                </button>
                <button aria-label="›" className="viewer-step next" onClick={() => step(1)} type="button">
                  ›
                </button>
              </>
            )}
            {open.kind === "video" ? (
              <video autoPlay controls key={open.key} playsInline>
                <source src={source(open)} type="video/mp4" />
                {strings.videoUnsupported}
              </video>
            ) : (
              <img alt={label(open, openIndex ?? 0)} key={open.key} src={source(open)} />
            )}
          </>
        )}
      </dialog>
    </>
  );
}
