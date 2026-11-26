"use client";

import { useRef } from "react";

import styles from "./personal.module.css";

/**
 * The corner button that puts this page's QR code on the whole screen, for
 * someone across a table to scan. A native <dialog>, so Escape and the focus
 * trap come from the browser.
 */
export function QrButton() {
  const dialog = useRef<HTMLDialogElement>(null);
  return (
    <>
      <button
        aria-label="Show the QR code for this page"
        className={styles.iconButton}
        onClick={() => dialog.current?.showModal()}
        type="button"
      >
        <svg
          aria-hidden="true"
          fill="none"
          height="22"
          stroke="currentColor"
          strokeLinecap="round"
          strokeLinejoin="round"
          strokeWidth="2"
          viewBox="0 0 24 24"
          width="22"
        >
          <rect height="7" rx="1" width="7" x="3" y="3" />
          <rect height="7" rx="1" width="7" x="14" y="3" />
          <rect height="7" rx="1" width="7" x="3" y="14" />
          <path d="M14 14h3v3h-3zM21 14v.01M21 21v-3M17 21h.01" />
        </svg>
      </button>
      <dialog aria-label="QR code for ashone.me" className={styles.qr} ref={dialog}>
        <div className={styles.qrBody}>
          <h2>Carlo Pascoli</h2>
          {/* A static file: the code never changes, so nothing draws it at run time. */}
          <img alt="QR code that opens ashone.me" height="320" src="/personal/qr.svg" width="320" />
          <p className={styles.qrAddress}>ashone.me</p>
          <p className={styles.qrHint}>Point your camera at the code.</p>
          <button className={styles.pill} onClick={() => dialog.current?.close()} type="button">
            Close
          </button>
        </div>
      </dialog>
    </>
  );
}
