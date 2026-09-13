import { describe, expect, it } from "vitest";

import { shareLocation } from "./location";

const watArun = {
  placeName: "Wat Arun",
  locality: "Bangkok",
  latitude: 13.743712,
  longitude: 100.488921,
};

describe("shareLocation", () => {
  it("keeps everything at exact precision", () => {
    expect(shareLocation(watArun, "exact")).toEqual({
      placeName: "Wat Arun",
      latitude: 13.743712,
      longitude: 100.488921,
    });
  });

  it("rounds to about a kilometre at neighborhood precision", () => {
    expect(shareLocation(watArun, "neighborhood")).toEqual({
      placeName: "Wat Arun",
      latitude: 13.74,
      longitude: 100.49,
    });
  });

  it("keeps only the city and coarse coordinates at city precision", () => {
    expect(shareLocation(watArun, "city")).toEqual({
      placeName: "Bangkok",
      latitude: 13.7,
      longitude: 100.5,
    });
  });

  it("does not fall back to the specific place name at city precision", () => {
    expect(shareLocation({ placeName: "Wat Arun" }, "city").placeName).toBeNull();
  });

  it("shares nothing when hidden", () => {
    expect(shareLocation(watArun, "hidden")).toEqual({
      placeName: null,
      latitude: null,
      longitude: null,
    });
  });

  it("ignores partial or non-finite coordinates", () => {
    expect(shareLocation({ latitude: 13.7 }, "exact").latitude).toBeNull();
    expect(shareLocation({ latitude: Number.NaN, longitude: 100 }, "city").longitude).toBeNull();
  });
});
