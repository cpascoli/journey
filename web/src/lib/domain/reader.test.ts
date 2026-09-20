import { describe, expect, it } from "vitest";

import { readerText } from "./reader";

describe("readerText", () => {
  it("shows narrative without also showing notes", () => {
    expect(readerText("The shared story", "Private drafting notes")).toBe("The shared story");
  });

  it("falls back to notes only when narrative is empty", () => {
    expect(readerText("  \n", "Trip notes")).toBe("Trip notes");
  });
});

