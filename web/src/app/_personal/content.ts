/**
 * What the personal home page and the CV say. Kept apart from the markup so a
 * new project or job is one entry here, not a block of JSX.
 */

export const SITE = "https://ashone.me";

export const CONTACT = {
  telegram: "https://t.me/mad4sats",
  linkedin: "https://www.linkedin.com/in/carlopascoli",
  github: "https://github.com/cpascoli",
  email: "mailto:carlo.pascoli@gmail.com",
  vcard: "/personal/carlo-pascoli.vcf",
};

export type Project = {
  track: string;
  name: string;
  line: string;
  href: string;
  image: string;
  alt: string;
  /** Site screenshots are landscape; app screenshots are cropped square. */
  shape: "wide" | "square";
};

export const SIDE_A: Project[] = [
  {
    track: "A1",
    name: "Power Fund",
    line: "A research desk for the machine age, staffed by agents.",
    href: "https://powerfund.finance",
    image: "/personal/powerfund.jpg",
    alt: "Power Fund home page",
    shape: "wide",
  },
  {
    track: "A2",
    name: "CoinStrat",
    line: "Tells you when to stack sats, and how hard.",
    href: "https://coinstrat.xyz",
    image: "/personal/coinstrat.jpg",
    alt: "CoinStrat home page",
    shape: "wide",
  },
  {
    track: "A3",
    name: "Power Wallet",
    line: "Bitcoin accumulation on autopilot, keys in your hands.",
    href: "https://powerwallet.finance",
    image: "/personal/powerwallet.jpg",
    alt: "Power Wallet home page",
    shape: "wide",
  },
  {
    track: "A4",
    name: "HashStrat",
    line: "Self-driving crypto portfolios, with no custodian. The DeFi protocol I founded in 2022.",
    href: "https://hashstrat.com",
    image: "/personal/hashstrat.jpg",
    alt: "HashStrat home page",
    shape: "wide",
  },
];

export const SIDE_B: Project[] = [
  {
    track: "B1",
    name: "Where Are They?",
    line: "Connecting the dots on UAP disclosure.",
    href: "https://wherearethey.info",
    image: "/personal/wherearethey.jpg",
    alt: "Where Are They home page with its knowledge graph",
    shape: "wide",
  },
  {
    track: "B2",
    name: "Journey",
    line: "An invite-only travel journey where you control who gets to read each entry.",
    href: "https://github.com/cpascoli/journey",
    image: "/personal/journey.jpg",
    alt: "Journey day view",
    shape: "square",
  },
  {
    track: "B3",
    name: "Walkman",
    line: "YouTube as a tape deck: paste, record, wind onto your own tapes.",
    href: "https://github.com/cpascoli/walkman",
    image: "/personal/walkman.jpg",
    alt: "Walkman cassette deck screen",
    shape: "square",
  },
  {
    track: "B4",
    name: "MyTube",
    line: "YouTube as a podcast app. No Shorts, no feed, no recommendations.",
    href: "https://github.com/cpascoli/my-tube",
    image: "/personal/mytube.jpg",
    alt: "MyTube player screen",
    shape: "square",
  },
  {
    track: "B5",
    name: "Fittr",
    line: "A gym companion that lives on your phone. Your health data never leaves it.",
    href: "https://github.com/cpascoli/fittr",
    image: "/personal/fittr.jpg",
    alt: "Fittr workout screen",
    shape: "square",
  },
];

export const LINER_NOTES: { where: string; what: string }[] = [
  {
    where: "TruFin Labs.",
    what: "Joined as a senior smart contract engineer, promoted to Head of Engineering. Liquid staking contracts securing more than $300M.",
  },
  {
    where: "Thomson Reuters.",
    what: "Director of Eikon mobile. Brought development in-house and rebuilt the iOS app.",
  },
  { where: "Betfair.", what: "Built the first betting app Apple approved on the App Store." },
  { where: "Shazam.", what: "Conceived and built its first music recommendation engine." },
];

export type Job = { years: string; title: string; summary: string; stack?: string };

export const EXPERIENCE: Job[] = [
  {
    years: "2023 – present",
    title: "Head of Engineering, TruFin Labs",
    summary:
      "Joined as Senior Smart Contract Engineer in 2023 and was promoted to Head of Engineering in 2025. Lead the team behind TruFin's liquid staking protocol for institutional clients. Delivered staking on Aptos, NEAR, Injective and Solana, securing more than $300M in assets.",
    stack: "Solidity · Rust · Move · Foundry",
  },
  {
    years: "2022 – 2023",
    title: "Founder, HashStrat",
    summary:
      "Designed and built a non-custodial DeFi protocol that automates digital asset portfolios: on-chain strategies, liquidity pools, staking and a revenue-sharing DAO.",
    stack: "Solidity · Hardhat · React · TypeScript",
  },
  {
    years: "2019 – 2021",
    title: "Senior Software Engineer, AlphaSights",
    summary:
      "Tech lead in Finance and Business Intelligence. Built data pipelines and financial microservices.",
    stack: "Kotlin · Postgres · Airflow · event sourcing",
  },
  {
    years: "2018 – 2019",
    title: "Co-founder and CTO, Cognitochain",
    summary:
      "Led Loanbase, a peer-to-peer lending platform on the Dharma protocol, and blockchain work for microfinance in the Indian state of Telangana.",
    stack: "Solidity · Java · Node · React · AWS",
  },
  {
    years: "2016 – 2018",
    title: "Engineering Manager, Mobile, Capital One",
    summary:
      "Hired and managed a cross-functional team of seven iOS, Android and quality engineers. Owned architecture and releases for the Capital One apps.",
  },
  {
    years: "2013 – 2016",
    title: "Director, Eikon Mobile, Thomson Reuters",
    summary:
      "Brought mobile development in-house for Eikon, the company's $2B-a-year financial platform. Hired the team and delivered a full rebuild of the iOS app.",
  },
  {
    years: "2011 – 2013",
    title: "Senior iOS Developer, IG Group",
    summary: "Built IG's iPhone and iPad trading apps: live prices, charting, dealing.",
  },
  {
    years: "2007 – 2011",
    title: "Research Engineer, then Senior Engineer, Betfair",
    summary:
      "Prototyped distributed systems in Betfair Research, then built Betfair for iPhone, the first betting app Apple approved, and started the native mobile team. Appy Award 2010; Totally Gaming Award 2012.",
  },
  {
    years: "2004 – 2006",
    title: "Software Engineer, Shazam",
    summary:
      "Lead developer of the web portal in Shazam's startup years. Conceived and built its first music recommendation engine.",
  },
  {
    years: "2000 – 2003",
    title: "Technical Manager, Deepend",
    summary: "Web developer, then technical manager, in the Rome office of the London design agency.",
  },
];

export const SKILLS: { area: string; detail: string }[] = [
  {
    area: "Leadership.",
    detail: "Hiring, people management, architecture, agile and continuous delivery.",
  },
  { area: "Blockchain.", detail: "Solidity, Rust, Move, EVM, DeFi protocol design." },
  {
    area: "Distributed systems.",
    detail: "TypeScript, Kotlin, Java, React, Micro Services, Event Sourcing, AWS.",
  },
  { area: "Mobile.", detail: "Swift and Objective-C on iOS since the first iPhone SDK." },
];
