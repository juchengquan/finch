import { redirect } from 'next/navigation';

// Settings is split into two surfaces (Account / Ledger); land on Account.
export default function SettingsPage() {
  redirect('/settings/account');
}
