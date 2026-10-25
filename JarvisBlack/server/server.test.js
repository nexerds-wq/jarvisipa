const test = require("node:test");
const assert = require("node:assert/strict");
const { textFromResponse } = require("./server");

test("extracts readable response text", () => {
  assert.equal(textFromResponse({
    output: [{ type: "message", content: [{ type: "output_text", text: "Hello, Richard." }] }]
  }), "Hello, Richard.");
});

test("does not accidentally speak non-text results", () => {
  assert.equal(textFromResponse({ output: [{ type: "reasoning", summary: [] }] }), "");
});
