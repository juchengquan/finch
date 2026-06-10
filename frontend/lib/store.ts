// frontend/lib/store.ts — DEPRECATED. Re-exports from lib/store/index.ts.
// This file is kept for backward compat with any imports that resolve
// lib/store.ts directly. It will be deleted in a follow-up commit
// (PR 2 Task 7). New consumers should import from `@/lib/store` (which
// resolves to lib/store/index.ts via the `@/*` alias and TypeScript's
// "folder wins over file" module resolution).

export * from './store/index';
