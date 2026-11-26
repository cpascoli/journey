"use client";

import { useState, type ReactNode } from "react";

import styles from "./personal.module.css";

type Side = "A" | "B";

const SIDES: { side: Side; name: string; count: string }[] = [
  { side: "A", name: "Bitcoin and investing", count: "4 projects" },
  { side: "B", name: "Built for myself, with agents", count: "5 projects" },
];

function CassetteFace({ side, name, back }: { side: Side; name: string; back?: boolean }) {
  return (
    <span className={`${styles.cassette} ${back ? styles.back : ""}`}>
      <span className={styles.label}>
        <span className={styles.labelTitle}>
          <span>CARLO PASCOLI</span>
          <span>SIDE {side}</span>
        </span>
        <span className={styles.window}>
          <span className={styles.reel} />
          <span className={styles.tape} />
          <span className={styles.reel} />
        </span>
      </span>
      <span className={styles.sides}>
        <span>{name}</span>
        <span>tap to flip</span>
      </span>
    </span>
  );
}

/**
 * The projects, one side at a time, and the thing you tap to change sides:
 * a cassette that turns over in the light theme, two chained blocks in the
 * dark one. Both switches are rendered and the stylesheet shows the one that
 * belongs to the theme. The tracklists arrive already rendered by the server.
 */
export function Deck({ sideA, sideB }: { sideA: ReactNode; sideB: ReactNode }) {
  const [side, setSide] = useState<Side>("A");
  const other: Side = side === "A" ? "B" : "A";

  return (
    <section aria-label="Projects" className={styles.deck}>
      <div>
        <button
          aria-label={`Flip the tape to side ${other}`}
          className={styles.cassetteButton}
          onClick={() => setSide(other)}
          type="button"
        >
          <span aria-hidden="true" className={`${styles.flipper} ${side === "B" ? styles.flipped : ""}`}>
            <CassetteFace name="Bitcoin and investing" side="A" />
            <CassetteFace back name="Built for myself" side="B" />
          </span>
        </button>

        <div aria-label="Choose a block of projects" className={styles.blocks} role="group">
          {SIDES.map((entry, index) => (
            <span key={entry.side} style={{ display: "contents" }}>
              {index > 0 ? <span aria-hidden="true" className={styles.chain} /> : null}
              <button
                aria-pressed={side === entry.side}
                className={styles.block}
                onClick={() => setSide(entry.side)}
                type="button"
              >
                <span className={styles.blockLetter}>{entry.side}</span>
                <span className={styles.blockName}>{entry.name}</span>
                <span className={styles.blockCount}>{entry.count}</span>
              </button>
            </span>
          ))}
        </div>
      </div>

      {SIDES.map((entry) => (
        <div className={`${styles.section} ${styles.side}`} hidden={side !== entry.side} key={entry.side}>
          <div className={styles.sectionHead}>
            <h2>
              <span className={styles.lightOnly}>Side {entry.side}</span>
              <span className={styles.darkOnly}>Block {entry.side}</span>
            </h2>
            <span className={styles.facts}>{entry.name}</span>
          </div>
          {entry.side === "A" ? sideA : sideB}
        </div>
      ))}
    </section>
  );
}
