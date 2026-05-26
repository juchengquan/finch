'use client';

import { useRouter } from 'next/navigation';
import { ScreenHeader, MobilePage } from '@/components/MobileComponents';
import { AddExpenseForm } from '@/components/add-expense-form';

export default function AddExpensePage() {
  const router = useRouter();

  return (
    <MobilePage header={<ScreenHeader back title="Add expense" />}>
      <AddExpenseForm className="pb-[120px]" onSaved={() => router.push('/activity')} />
    </MobilePage>
  );
}
