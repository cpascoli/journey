import type { Metadata } from "next";
import Link from "next/link";

import { EXPERIENCE, SITE, SKILLS } from "../_personal/content";
import { personalFonts } from "../_personal/fonts";
import styles from "../_personal/personal.module.css";
import { PrintButton } from "../_personal/PrintButton";

export const metadata: Metadata = {
  title: "Carlo Pascoli — CV",
  description: "Career history of Carlo Pascoli: engineering leadership, Bitcoin and DeFi, mobile.",
  metadataBase: new URL(SITE),
};

export default function Cv() {
  return (
    <main className={`${styles.page} ${styles.cv} ${personalFonts}`} lang="en">
      <div className={styles.column}>
        <header className={styles.header}>
          <div className={`${styles.topline} ${styles.facts} ${styles.noPrint}`}>
            <Link href="/">← ashone.me</Link>
            <span>CV</span>
          </div>
          <h1 className={styles.cvName}>Carlo Pascoli</h1>
          <p className={styles.about}>
            Technologist with a career across backend, mobile and blockchain engineering, and a
            decade of hiring and leading teams. Focused on Bitcoin and decentralised finance since
            2018.
          </p>
          <PrintButton />
        </header>

        <section className={styles.section}>
          <div className={styles.sectionHead}>
            <h2>Experience</h2>
          </div>
          {EXPERIENCE.map((job) => (
            <div className={styles.job} key={job.years}>
              <span className={styles.facts}>{job.years}</span>
              <h3>{job.title}</h3>
              <p>{job.summary}</p>
              {job.stack ? <p className={styles.stack}>{job.stack}</p> : null}
            </div>
          ))}
        </section>

        <section className={styles.section}>
          <div className={styles.sectionHead}>
            <h2>Skills</h2>
          </div>
          <div className={styles.notes}>
            {SKILLS.map((skill) => (
              <p key={skill.area}>
                <strong>{skill.area}</strong> {skill.detail}
              </p>
            ))}
          </div>
        </section>

        <section className={styles.section}>
          <div className={styles.sectionHead}>
            <h2>Education and languages</h2>
          </div>
          <div className={styles.notes}>
            <p>Degree in Computer Engineering (BSc + MSc equivalent), Università Roma Tre.</p>
            <p>Italian (native), English (fluent), Spanish (beginner).</p>
            <p>Away from work: music, travel, retro computing, sailing, football, skiing.</p>
          </div>
        </section>

        <footer className={`${styles.footer} ${styles.facts} ${styles.noPrint}`}>
          <Link href="/">← Back to projects</Link>
          <span>ashone.me/cv</span>
        </footer>
      </div>
    </main>
  );
}
