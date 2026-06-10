'use client';

import { useParams, useRouter } from 'next/navigation';
import { ScreenHeader } from '@/components/ui/screen-header';
import { TransactionDetail } from '@/components/transaction-detail';

export default function TxDetailPage() {
  const params = useParams();
  const router = useRouter();
  const txId = params.id as string;

  return (
    <div className="px-5 pb-[120px]">
      <ScreenHeader title="" back backHref="/activity" />
      <TransactionDetail txId={txId} onDeleted={() => router.back()} />
    </div>
  );
}
