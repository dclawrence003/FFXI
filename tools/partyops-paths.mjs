import path from 'node:path';

export function explicitRoot(value, variable) {
  if (typeof value !== 'string' || !path.isAbsolute(value)) {
    throw new Error(`Supply an absolute path through ${variable} or the tool's positional argument.`);
  }
  return path.resolve(value);
}
