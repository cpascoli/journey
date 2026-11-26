"use client";

import styles from "./personal.module.css";
import { THEME_KEY } from "./theme";

/**
 * Switches between the dark (Bitcoin) and light (mixtape) themes. The theme
 * is an attribute on <html> rather than React state: the stylesheet does all
 * the work, and the button's icon follows it in CSS, so nothing here can
 * disagree with what the server rendered.
 */
export function ThemeToggle() {
  function toggle() {
    const root = document.documentElement;
    const light = root.dataset.personalTheme !== "light";
    if (light) root.dataset.personalTheme = "light";
    else delete root.dataset.personalTheme;
    try {
      localStorage.setItem(THEME_KEY, light ? "light" : "dark");
    } catch {
      // Private browsing may refuse storage; the theme still switches.
    }
  }

  return (
    <button
      aria-label="Switch between the dark and light themes"
      className={styles.iconButton}
      onClick={toggle}
      type="button"
    >
      {/* Sun while dark (tap for light), moon while light. */}
      <svg
        aria-hidden="true"
        className={styles.darkOnly}
        fill="none"
        height="22"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="2"
        viewBox="0 0 24 24"
        width="22"
      >
        <circle cx="12" cy="12" r="4" />
        <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
      </svg>
      <svg
        aria-hidden="true"
        className={styles.lightOnly}
        fill="none"
        height="22"
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="2"
        viewBox="0 0 24 24"
        width="22"
      >
        <path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z" />
      </svg>
    </button>
  );
}
