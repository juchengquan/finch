import type { Sqlite3Static } from '@sqlite.org/sqlite-wasm';
import type { Exec } from './repo';

type InitOptions = { print?: () => void; printErr?: () => void; locateFile?: (path: string) => string };
// The published types declare the init function as taking no arguments, but the
// runtime accepts a config object — re-type it to the slice we use.
type InitFn = (opts?: InitOptions) => Promise<Sqlite3Static>;

// Load the sqlite-wasm init function as a runtime import (webpackIgnore keeps
// the bundler out of it). In the browser we fetch the worker-free ESM build we
// copied to /public — the npm package can't be bundled because it contains a
// dynamic Worker URL we never use. In Node/bun (tests) we resolve the package.
async function loadInit(): Promise<InitFn> {
  if (typeof window !== 'undefined') {
    const browserUrl = '/sqlite3.mjs';
    const mod = await import(/* webpackIgnore: true */ browserUrl);
    return mod.default as InitFn;
  }
  const pkg = '@sqlite.org/sqlite-wasm';
  const mod = await import(/* webpackIgnore: true */ pkg);
  return mod.default as InitFn;
}

let _sqlite3: Promise<Sqlite3Static> | null = null;
export function getSqlite3(): Promise<Sqlite3Static> {
  if (!_sqlite3) {
    _sqlite3 = loadInit().then((init) => {
      const opts: InitOptions = { print: () => {}, printErr: () => {} };
      // Browser loads the wasm we copied to /public; Node/bun resolves its own.
      if (typeof window !== 'undefined') opts.locateFile = () => '/sqlite3.wasm';
      return init(opts);
    });
  }
  return _sqlite3;
}

export type OO1DB = { exec: (opts: unknown) => void; close: () => void; pointer?: number };

export function execFor(db: OO1DB): Exec {
  return async (sql, bind) => {
    const rows: Record<string, unknown>[] = [];
    db.exec({ sql, bind: bind ?? [], rowMode: 'object', resultRows: rows });
    return rows;
  };
}
