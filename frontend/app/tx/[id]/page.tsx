'use client';

import { useParams, useRouter } from 'next/navigation';
import { ScreenHeader } from '@/components/MobileComponents';
import { TransactionDetail, TransactionActionsMenu } from '@/components/transaction-detail';

export default function TxDetailPage() {
  const params = useParams();
  const router = useRouter();
  const txId = params.id as string;

  return (
    <div className="px-5 pb-[120px]">
      <ScreenHeader
        title=""
        back
        trailing={<TransactionActionsMenu txId={txId} onDeleted={() => router.back()} />}
      />
      <TransactionDetail txId={txId} />
    </div>
  );
}
