/** Client-chosen media key: the app sends a hash of the Photos identifier, which contains slashes. */
export const MEDIA_KEY_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/** Netlify functions accept request bodies up to 6 MB; photos are resized well below this. */
export const MAX_PHOTO_BYTES = 5 * 1024 * 1024;

export function mediaStoragePath(entryId: string, key: string): string {
  return `entries/${entryId}/${key}.jpg`;
}

export function isJpeg(bytes: Uint8Array): boolean {
  return bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
}

export type PhotoMetadata = "exif" | "xmp" | "app1" | "iptc";

function startsWith(bytes: Uint8Array, offset: number, text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    if (bytes[offset + i] !== text.charCodeAt(i)) return false;
  }
  return true;
}

/**
 * Metadata segments that can carry a location, found by walking the JPEG's
 * marker segments up to the image data. EXIF holds GPS coordinates, XMP can
 * repeat them, and IPTC can name the place. The app must strip all of them:
 * the server refuses a photo that still has any. ICC colour profiles (APP2)
 * are fine and are kept.
 */
export function findPhotoMetadata(bytes: Uint8Array): PhotoMetadata[] {
  const found = new Set<PhotoMetadata>();
  let i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] !== 0xff) break;
    // Markers may be preceded by any number of 0xFF fill bytes.
    while (bytes[i + 1] === 0xff && i + 2 < bytes.length) i++;
    const marker = bytes[i + 1]!;
    if (marker === 0xd9 || marker === 0xda) break; // end of image, or start of image data
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) {
      i += 2; // markers without a length
      continue;
    }
    const length = (bytes[i + 2]! << 8) | bytes[i + 3]!;
    if (length < 2) break;
    const body = i + 4;
    if (marker === 0xe1) {
      if (startsWith(bytes, body, "Exif\0")) found.add("exif");
      else if (startsWith(bytes, body, "http://ns.adobe.com/xap/")) found.add("xmp");
      else found.add("app1");
    } else if (marker === 0xed) {
      found.add("iptc");
    }
    i += 2 + length;
  }
  return [...found];
}
