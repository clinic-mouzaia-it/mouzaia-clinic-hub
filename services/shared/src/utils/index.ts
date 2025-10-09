export function env(name: string, defaultValue?: string): string {
  const v = process.env[name];
  if (v == null || v === "") {
    if (defaultValue !== undefined) return defaultValue;
    throw new Error(`Missing required env var: ${name}`);
  }
  return v;
}

// very lightweight log that can be swapped later
export function log(...args: unknown[]) {
  // eslint-disable-next-line no-console
  console.log(...args);
}
