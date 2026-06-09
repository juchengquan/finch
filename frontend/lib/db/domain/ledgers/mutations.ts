import type { Exec } from '../../core/repo';
import type { ActionName, Args } from '../_args';
import { I18nError } from '@/lib/i18n-error';
import { ensureSystemCategories } from '../../core/entries';
import { getAppState, setAppState } from '../_app/appState';
import { unlinkAttachmentFiles } from '../_shared/attachment-cleanup';
import {
  createLedger as qCreateLedger,
  updateLedger as qUpdateLedger,
  setDefaultLedger as qSetDefaultLedger,
  deleteLedger as qDeleteLedger,
  recomputeAmountBases,
} from './queries';

type Handler<A extends ActionName> = (exec: Exec, args: Args[A]) => Promise<void>;

const str = (v: unknown) => String(v);

export const handlers = {
  createLedger: async (exec, args: Args['createLedger']) => {
    const id = str(args.id);
    const name = str(args.name).trim();
    const base = str(args.base).trim().toUpperCase();
    if (!id) throw new I18nError('error.required.id', {}, 'id is required');
    if (!name) throw new I18nError('error.required.name', {}, 'Name is required');
    if (!/^[A-Z]{3}$/.test(base)) throw new I18nError('error.ledger.baseISO', {}, 'base must be a 3-letter ISO code');
    const collide = await exec('SELECT id FROM ledgers WHERE id = ?', [id]);
    if (collide.length) throw new I18nError('error.ledger.duplicateId', {}, 'Ledger id already exists');
    const color = args.color == null ? null : String(args.color);
    const tagline = args.tagline == null ? null : String(args.tagline);
    await qCreateLedger(exec, { id, name, base, color, tagline });
    await ensureSystemCategories(exec, id);
  },
  updateLedger: async (exec, args: Args['updateLedger']) => {
    const id = str(args.id);
    if (!id) throw new I18nError('error.required.id', {}, 'id is required');
    const patch = (args.patch ?? {}) as { name?: string; color?: string | null; tagline?: string | null };
    if (patch.name !== undefined && !String(patch.name).trim()) {
      throw new I18nError('error.ledger.nameEmpty', {}, 'Name cannot be empty');
    }
    await qUpdateLedger(exec, id, {
      ...(patch.name !== undefined ? { name: String(patch.name).trim() } : {}),
      ...(patch.color !== undefined ? { color: patch.color == null ? null : String(patch.color) } : {}),
      ...(patch.tagline !== undefined ? { tagline: patch.tagline == null ? null : String(patch.tagline) } : {}),
    });
  },
  setDefaultLedger: async (exec, args: Args['setDefaultLedger']) => {
    const id = str(args.id);
    if (!id) throw new I18nError('error.required.id', {}, 'id is required');
    const exists = await exec('SELECT id FROM ledgers WHERE id = ?', [id]);
    if (!exists.length) throw new I18nError('error.notFound.ledger', {}, 'Ledger not found');
    await qSetDefaultLedger(exec, id);
  },
  deleteLedger: async (exec, args: Args['deleteLedger']) => {
    const id = str(args.id);
    if (!id) throw new I18nError('error.required.id', {}, 'id is required');
    const { relPaths } = await qDeleteLedger(exec, id);
    const raw = await getAppState(exec, 'displayCurrencyByLedger');
    if (raw) {
      try {
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === 'object' && !Array.isArray(parsed) && id in parsed) {
          delete (parsed as Record<string, unknown>)[id];
          await setAppState(exec, 'displayCurrencyByLedger', JSON.stringify(parsed));
        }
      } catch {
        /* malformed — leave it */
      }
    }
    await unlinkAttachmentFiles(relPaths);
  },
  changeLedgerBase: async (exec, args: Args['changeLedgerBase']) => {
    const ledgerId = str(args.ledgerId);
    const newBase = str(args.newBase).trim().toUpperCase();
    if (!ledgerId) throw new I18nError('error.required.ledgerId', {}, 'ledgerId is required');
    if (!/^[A-Z]{3}$/.test(newBase)) throw new I18nError('error.ledger.newBaseISO', {}, 'newBase must be a 3-letter ISO code');
    const [row] = await exec('SELECT base_currency FROM ledgers WHERE id = ?', [ledgerId]);
    if (!row) throw new I18nError('error.notFound.ledger', {}, 'Ledger not found');
    if (String(row.base_currency) === newBase) return;
    await recomputeAmountBases(exec, ledgerId, newBase);
  },
} satisfies Partial<{ [K in ActionName]: Handler<K> }>;
