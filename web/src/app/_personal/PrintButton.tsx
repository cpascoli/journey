"use client";

import styles from "./personal.module.css";

/** The CV's PDF is the page itself, printed: one source, never out of date. */
export function PrintButton() {
  return (
    <button className={`${styles.primary} ${styles.noPrint}`} onClick={() => window.print()} type="button">
      Save as PDF
    </button>
  );
}
