import type { Metadata } from "next";
import Link from "next/link";

import { CONTACT, LINER_NOTES, SIDE_A, SIDE_B, SITE, type Project } from "./_personal/content";
import { Deck } from "./_personal/Deck";
import { personalFonts } from "./_personal/fonts";
import styles from "./_personal/personal.module.css";
import { QrButton } from "./_personal/QrButton";
import { THEME_SCRIPT } from "./_personal/theme";
import { ThemeToggle } from "./_personal/ThemeToggle";

/**
 * The site's front door is Carlo's personal page; the journal lives behind
 * its invitation links (/i/…, /read) and does not depend on this page.
 */
export const metadata: Metadata = {
  title: "Carlo Pascoli",
  description:
    "Engineering leader who loves to ship. Projects, contacts and CV of Carlo Pascoli.",
  metadataBase: new URL(SITE),
  openGraph: { title: "Carlo Pascoli", description: "Engineering leader who loves to ship.", url: SITE },
};

function Tracks({ projects }: { projects: Project[] }) {
  return (
    <ul className={styles.tracks}>
      {projects.map((project) => (
        <li className={styles.track} key={project.track}>
          <a href={project.href} rel="noopener">
            <span className={styles.trackNumber}>{project.track}</span>
            <div className={styles.trackText}>
              <h3>{project.name}</h3>
              <p>{project.line}</p>
            </div>
            {/* Small fixed thumbnails, already sized on disk. */}
            <img
              alt={project.alt}
              className={`${styles.thumb} ${project.shape === "wide" ? styles.wide : styles.square}`}
              height={56}
              loading="lazy"
              src={project.image}
              width={project.shape === "wide" ? 84 : 56}
            />
          </a>
        </li>
      ))}
    </ul>
  );
}

export default function Home() {
  return (
    <main className={`${styles.page} ${styles.home} ${personalFonts}`} lang="en">
      <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      <div className={styles.column}>
        <header className={styles.header}>
          <div className={`${styles.topline} ${styles.facts}`}>
            <span>ashone.me · Bangkok</span>
            <div className={styles.tools}>
              <ThemeToggle />
              <QrButton />
            </div>
          </div>

          <h1 className={styles.name}>Carlo Pascoli</h1>
          <p className={styles.lede}>
            Engineering leader who loves to innovate. From Shazam&rsquo;s recommendation engine to{" "}
            <em>Bitcoin</em>.
          </p>
          <p className={styles.about}>
            A hands-on builder who understands financial products and turns ambiguous ideas at the
            intersection of AI, digital assets, markets and distributed systems into working
            solutions.
          </p>
        </header>

        <nav aria-label="Contact" className={styles.contact}>
          <a className={styles.primary} download href={CONTACT.vcard}>
            Save my contact
          </a>
          <div className={styles.contactGrid}>
            <a className={styles.pill} href={CONTACT.telegram} rel="noopener">
              Telegram
            </a>
            <a className={styles.pill} href={CONTACT.linkedin} rel="noopener">
              LinkedIn
            </a>
            <a className={styles.pill} href={CONTACT.github} rel="noopener">
              GitHub
            </a>
            <a className={styles.pill} href={CONTACT.email}>
              Email
            </a>
          </div>
        </nav>

        <Deck sideA={<Tracks projects={SIDE_A} />} sideB={<Tracks projects={SIDE_B} />} />

        <section className={styles.section}>
          <div className={styles.sectionHead}>
            <h2>
              <span className={styles.lightOnly}>Liner notes</span>
              <span className={styles.darkOnly}>Career highlights</span>
            </h2>
            <span className={styles.facts}>2004 – today</span>
          </div>
          <div className={styles.notes}>
            {LINER_NOTES.map((note) => (
              <p key={note.where}>
                <strong>{note.where}</strong> {note.what}
              </p>
            ))}
            <p className={styles.facts}>
              Also: Capital One, IG Group, AlphaSights, Cognitochain, HashStrat.
            </p>
            <Link className={styles.pill} href="/cv">
              Read the full CV
            </Link>
          </div>
        </section>

        <footer className={`${styles.footer} ${styles.facts}`}>
          <span>ashone.me</span>
          <span>Carlo Pascoli</span>
        </footer>
      </div>
    </main>
  );
}
