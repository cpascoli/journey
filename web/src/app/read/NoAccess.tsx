import Link from "next/link";

/**
 * A revoked invitation is not the same as a broken link, and saying so saves
 * the reader from chasing a problem that isn't theirs. Neither message reveals
 * whether any particular entry or journal exists.
 */
export function NoAccess({ status, entry = false }: { status: "none" | "revoked"; entry?: boolean }) {
  if (status === "revoked") {
    return (
      <main className="page compact">
        <p className="eyebrow">Journey</p>
        <h1>This invitation was withdrawn</h1>
        <p className="lede">
          It no longer opens the journal. If you think that&apos;s a mistake, ask whoever shared it
          with you for a new link.
        </p>
      </main>
    );
  }
  return (
    <main className="page compact">
      <p className="eyebrow">Journey</p>
      <h1>{entry ? "Entry unavailable" : "Invitation unavailable"}</h1>
      <p className="lede">
        {entry
          ? "This entry is not available with the current invitation."
          : "This invitation is invalid or is no longer active. Open your invitation link again to start reading."}
      </p>
      {entry && <Link href="/read">Return to the journal</Link>}
    </main>
  );
}
