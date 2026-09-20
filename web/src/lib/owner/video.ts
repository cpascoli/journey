/**
 * Video equivalent of findPhotoMetadata: the server refuses a video that still
 * carries a location, and never strips one itself.
 *
 * The app exports with `AVAssetExportSession.metadata = []`, which drops the
 * location atoms, and with `shouldOptimizeForNetworkUse = true`, which moves
 * `moov` (where all metadata lives) ahead of the media data. That second flag
 * is what makes verification cheap: the server reads only the head of the
 * object and refuses anything whose `moov` is not in it, so a file can never
 * be accepted on the strength of a part nobody looked at.
 */

/** Videos are uploaded straight to the object store, so this is not a request-body limit. */
export const MAX_VIDEO_BYTES = 60 * 1024 * 1024;
export const VIDEO_CONTENT_TYPE = "video/mp4";

/**
 * How much of the object the server reads to verify it. A fast-start `moov`
 * for a 3-minute 720p clip is a few hundred KB; 8 MB is generous enough that
 * a rejection means the file really is not fast-start.
 */
export const VIDEO_HEAD_BYTES = 8 * 1024 * 1024;

export type VideoMetadata =
  | "quicktime-location"
  | "3gpp-location"
  | "apple-location-key"
  | "gps-track";

type Box = { type: string; bodyStart: number; end: number };

/** Boxes whose bodies are a list of further boxes. */
const CONTAINERS = new Set([
  "moov", "trak", "udta", "mdia", "minf", "stbl", "edts", "ilst", "moof", "traf",
]);

function readUint32(bytes: Uint8Array, offset: number): number {
  return (
    ((bytes[offset]! << 24) >>> 0) +
    (bytes[offset + 1]! << 16) +
    (bytes[offset + 2]! << 8) +
    bytes[offset + 3]!
  );
}

function readType(bytes: Uint8Array, offset: number): string {
  return String.fromCharCode(
    bytes[offset]!, bytes[offset + 1]!, bytes[offset + 2]!, bytes[offset + 3]!,
  );
}

/** A 4-character box type is printable ASCII; © (0xA9) is the one legal exception. */
function isPlausibleType(bytes: Uint8Array, offset: number): boolean {
  if (offset + 4 > bytes.length) return false;
  for (let i = offset; i < offset + 4; i++) {
    const byte = bytes[i]!;
    if (byte !== 0xa9 && (byte < 0x20 || byte > 0x7e)) return false;
  }
  return true;
}

/**
 * Walks the boxes between `start` and `end`, stopping at the first malformed
 * header. `end` is the box's *declared* end, which may run past the bytes on
 * hand: that is how a truncated box is told apart from a complete one.
 */
function* boxes(bytes: Uint8Array, start: number, end: number): Generator<Box> {
  let offset = start;
  while (offset + 8 <= end) {
    const declared = readUint32(bytes, offset);
    const type = readType(bytes, offset + 4);
    let bodyStart = offset + 8;
    let size = declared;
    if (declared === 1) {
      // 64-bit size. Anything above 2^32 is past what we read anyway.
      if (offset + 16 > end) return;
      const high = readUint32(bytes, offset + 8);
      const low = readUint32(bytes, offset + 12);
      if (high > 0) return;
      size = low;
      bodyStart = offset + 16;
    } else if (declared === 0) {
      size = end - offset; // extends to the end of the file
    }
    if (size < bodyStart - offset) return;
    yield { type, bodyStart, end: offset + size };
    offset += size;
  }
}

/**
 * `meta` is a full box in ISO BMFF (4 bytes of version and flags before its
 * children) but a plain container in QuickTime, and iOS writes both. Decide by
 * looking at which offset a plausible child header actually starts at.
 */
function metaChildStart(bytes: Uint8Array, bodyStart: number): number {
  return isPlausibleType(bytes, bodyStart + 4) ? bodyStart : bodyStart + 4;
}

function walk(bytes: Uint8Array, start: number, end: number, visit: (box: Box) => void): void {
  const limit = Math.min(end, bytes.length);
  for (const box of boxes(bytes, start, limit)) {
    visit(box);
    // A declared end may run past the bytes on hand; never read beyond them.
    const childEnd = Math.min(box.end, limit);
    if (CONTAINERS.has(box.type)) {
      walk(bytes, box.bodyStart, childEnd, visit);
    } else if (box.type === "meta") {
      walk(bytes, metaChildStart(bytes, box.bodyStart), childEnd, visit);
    }
  }
}

function indexOfAscii(bytes: Uint8Array, text: string, start: number, end: number): number {
  const first = text.charCodeAt(0);
  outer: for (let i = start; i + text.length <= end; i++) {
    if (bytes[i] !== first) continue;
    for (let j = 1; j < text.length; j++) {
      if (bytes[i + j] !== text.charCodeAt(j)) continue outer;
    }
    return i;
  }
  return -1;
}

/** The `moov` box, or null when it is not within the bytes provided. */
export function findMoov(bytes: Uint8Array): { bodyStart: number; end: number } | null {
  for (const box of boxes(bytes, 0, bytes.length)) {
    if (box.type === "moov") {
      // Truncated because the head cut it short: treat as not found.
      return box.end > bytes.length ? null : { bodyStart: box.bodyStart, end: box.end };
    }
  }
  return null;
}

/**
 * Location metadata inside `moov`. `©xyz` is what QuickTime writes, `loci` is
 * the 3GPP equivalent, and modern iOS additionally names the value through the
 * `mdta` key mechanism, which is a string rather than a box type.
 */
export function findVideoMetadata(bytes: Uint8Array): VideoMetadata[] {
  const moov = findMoov(bytes);
  if (!moov) return [];
  const found = new Set<VideoMetadata>();

  walk(bytes, moov.bodyStart, moov.end, (box) => {
    if (box.type === "©xyz") found.add("quicktime-location");
    else if (box.type === "loci") found.add("3gpp-location");
    else if (box.type === "gpmd") found.add("gps-track");
  });

  if (indexOfAscii(bytes, "com.apple.quicktime.location", moov.bodyStart, moov.end) >= 0) {
    found.add("apple-location-key");
  }
  return [...found];
}

export type VideoShape = {
  width: number;
  height: number;
  durationSeconds: number | null;
};

function fixed1616(bytes: Uint8Array, offset: number): number {
  return readUint32(bytes, offset) / 65536;
}

/**
 * Display dimensions from the video track's `tkhd`, and duration from `mvhd`.
 * A portrait clip is stored landscape with a rotation matrix, so the matrix
 * decides whether the stored width and height are swapped for display.
 */
export function readVideoShape(bytes: Uint8Array): VideoShape | null {
  const moov = findMoov(bytes);
  if (!moov) return null;

  let durationSeconds: number | null = null;
  let width = 0;
  let height = 0;

  walk(bytes, moov.bodyStart, moov.end, (box) => {
    if (box.type === "mvhd") {
      const version = bytes[box.bodyStart]!;
      const base = box.bodyStart + 4 + (version === 1 ? 16 : 8);
      if (base + 8 > box.end) return;
      const timescale = readUint32(bytes, base);
      // A version-1 duration is 64-bit; its high word is zero for any real clip.
      const duration = version === 1 ? readUint32(bytes, base + 8) : readUint32(bytes, base + 4);
      if (timescale > 0) durationSeconds = duration / timescale;
      return;
    }
    if (box.type !== "tkhd") return;

    const version = bytes[box.bodyStart]!;
    // version+flags, creation, modification, track id, reserved, duration,
    // 8 reserved, layer, alternate group, volume, reserved, then the matrix.
    const timeFields = version === 1 ? 8 : 4;
    const matrixStart = box.bodyStart + 4 + timeFields * 2 + 4 + 4 + timeFields + 8 + 8;
    const dimensionsStart = matrixStart + 36;
    if (dimensionsStart + 8 > box.end) return;

    const trackWidth = fixed1616(bytes, dimensionsStart);
    const trackHeight = fixed1616(bytes, dimensionsStart + 4);
    // Audio and metadata tracks carry zeroes here.
    if (trackWidth <= 0 || trackHeight <= 0) return;

    const a = fixed1616(bytes, matrixStart);
    const d = fixed1616(bytes, matrixStart + 16);
    const rotatedQuarterTurn = a === 0 && d === 0;
    width = Math.round(rotatedQuarterTurn ? trackHeight : trackWidth);
    height = Math.round(rotatedQuarterTurn ? trackWidth : trackHeight);
  });

  if (width <= 0 || height <= 0) return null;
  return { width, height, durationSeconds };
}
