// runner/assertions.mjs

export function assertRowCount(actual, expected, id) {
  if (expected === undefined || expected === null) return;
  if (typeof expected === "number") {
    if (actual !== expected) throw new Error(`[${id}] expected exactly ${expected} rows, got ${actual}`);
    return;
  }
  if (typeof expected === "string") {
    const m = expected.match(/^(>=|<=|>|<|=)\s*(\d+)$/);
    if (!m) throw new Error(`[${id}] invalid expect.rowCount: ${expected}`);
    const [, op, nStr] = m;
    const n = parseInt(nStr, 10);
    const cmp = { ">=": actual >= n, "<=": actual <= n, ">": actual > n, "<": actual < n, "=": actual === n }[op];
    if (!cmp) throw new Error(`[${id}] expected rowCount ${expected}, got ${actual}`);
    return;
  }
  throw new Error(`[${id}] invalid expect.rowCount type: ${typeof expected}`);
}

export function assertFirstRow(actual, expected, id) {
  if (!expected || expected === "*") return;
  if (!actual) throw new Error(`[${id}] expected first row matching ${JSON.stringify(expected)}, got no rows`);
  for (const [k, v] of Object.entries(expected)) {
    const actualV = k.split(".").reduce((o, p) => o?.[p], actual);
    if (actualV !== v) {
      throw new Error(`[${id}] expected first.${k} = ${JSON.stringify(v)}, got ${JSON.stringify(actualV)}`);
    }
  }
}
