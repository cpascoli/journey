"use client";

import Link from "next/link";
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
  previewLimit,
  moreHref,
}: {
  entryId: string;
  media: Media[];
  language: Language;
  compact?: boolean;
  /** Show at most this many; the rest are reached through `moreHref`. */
  previewLimit?: number;
  moreHref?: string;
}) {
  const strings = stringsFor(language);
  const [openIndex, setOpenIndex] = useState<number | null>(null);
  const dialogRef = useRef<HTMLDialogElement>(null);

  const shownCount = previewLimit === undefined ? media.length : Math.min(previewLimit, media.length);
  const close = useCallback(() => setOpenIndex(null), []);
  const step = useCallback(
    (by: number) =>
      setOpenIndex((current) =>
        current === null ? null : (current + by + shownCount) % shownCount,
      ),
    [shownCount],
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
  // A summary shows a taste, not the whole entry: thirty thumbnails on a
  // listing is a page nobody asked to load.
  const shown = previewLimit === undefined ? media : media.slice(0, previewLimit);
  const hidden = media.length - shown.length;
  const source = (item: Media) => `/media/${entryId}/${encodeURIComponent(item.key)}`;
  // The grid shows the small copy; opening an item loads the original. Media
  // published before thumbnails existed falls back to the original here.
  const preview = (item: Media) => `${source(item)}?size=thumb`;
  const open = openIndex === null ? null : shown[openIndex];
  const label = (item: Media, index: number) =>
    item.kind === "video" ? strings.videoAlt(index + 1) : strings.photoAlt(index + 1);

  return (
    <>
      <div className={`photo-grid${compact ? " compact-photos" : ""}`}>
        {shown.map((item, index) => (
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
                decoding="async"
                height={item.height ?? undefined}
                loading="lazy"
                src={preview(item)}
                width={item.width ?? undefined}
              />
            )}
          </button>
        ))}
        {hidden > 0 && moreHref && (
          <Link aria-label={strings.seeAllMedia(media.length)} className="media-more" href={moreHref}>
            {strings.moreMedia(hidden)}
          </Link>
        )}
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
            {shown.length > 1 && (
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
