import type { Exec } from '../../core/repo';
import { I18nError } from '@/lib/i18n-error';

export async function resolveTemplateLedger(exec: Exec, templateId: string): Promise<string> {
  const rows = await exec('SELECT ledger_id FROM scheduled_templates WHERE id = ?', [templateId]);
  if (!rows.length) throw new I18nError('error.notFound.template', {}, 'Template not found');
  return String(rows[0].ledger_id);
}
