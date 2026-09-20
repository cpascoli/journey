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
 */
export function MediaGrid({
  entryId,
  media,
  compact = false,
}: {
  entryId: string;
  media: Media[];
  compact?: boolean;
}) {
  if (media.length === 0) return null;
  return (
    <div className={`photo-grid${compact ? " compact-photos" : ""}`}>
      {media.map((item, index) => {
        const source = `/media/${entryId}/${encodeURIComponent(item.key)}`;
        if (item.kind === "video") {
          return (
            <video
              controls
              height={item.height ?? undefined}
              key={item.key}
              // metadata only: a grid of clips should not pull every one down.
              preload="metadata"
              playsInline
              width={item.width ?? undefined}
            >
              <source src={source} type="video/mp4" />
              Your browser cannot play this video.
            </video>
          );
        }
        return (
          <img
            alt={`Journey photo ${index + 1}`}
            height={item.height ?? undefined}
            key={item.key}
            loading="lazy"
            src={source}
            width={item.width ?? undefined}
          />
        );
      })}
    </div>
  );
}
