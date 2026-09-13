/** How precisely an entry's location is shared. Mirrors the app's LocationPrecision. */
export type LocationPrecision = "exact" | "neighborhood" | "city" | "hidden";

export type LocationInput = {
  /** The specific place, e.g. "Wat Arun". */
  placeName?: string | null;
  /** The town or city, e.g. "Bangkok". */
  locality?: string | null;
  latitude?: number | null;
  longitude?: number | null;
};

export type SharedLocation = {
  placeName: string | null;
  latitude: number | null;
  longitude: number | null;
};

// Decimal places kept per precision: 2 ≈ 1 km, 1 ≈ 11 km.
const DECIMALS: Record<"neighborhood" | "city", number> = { neighborhood: 2, city: 1 };

function round(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

/**
 * Reduces a location to what may be shared. Applied on the server before
 * storing, so a coarser precision never leaves the precise value behind.
 * At city precision the specific place name is dropped too, since a name like
 * "Wat Arun" pinpoints the spot as well as coordinates would.
 */
export function shareLocation(input: LocationInput, precision: LocationPrecision): SharedLocation {
  const hasCoordinates =
    typeof input.latitude === "number" &&
    typeof input.longitude === "number" &&
    Number.isFinite(input.latitude) &&
    Number.isFinite(input.longitude);

  switch (precision) {
    case "hidden":
      return { placeName: null, latitude: null, longitude: null };
    case "exact":
      return {
        placeName: input.placeName ?? input.locality ?? null,
        latitude: hasCoordinates ? input.latitude! : null,
        longitude: hasCoordinates ? input.longitude! : null,
      };
    case "neighborhood":
    case "city": {
      const decimals = DECIMALS[precision];
      return {
        placeName:
          precision === "neighborhood"
            ? (input.placeName ?? input.locality ?? null)
            : (input.locality ?? null),
        latitude: hasCoordinates ? round(input.latitude!, decimals) : null,
        longitude: hasCoordinates ? round(input.longitude!, decimals) : null,
      };
    }
  }
}
