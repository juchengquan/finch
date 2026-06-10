import type { Metadata, Viewport } from 'next';
import { Inter, JetBrains_Mono } from 'next/font/google';
import './globals.css';
import { ThemeProvider } from '@/components/theme-provider';
import { I18nProvider } from '@/components/i18n-provider';
import { LedgerProvider } from '@/components/ledger-provider';
import { StoreHydration } from '@/components/store-hydration';
import { SqliteBackupProvider } from '@/components/sqlite-backup-provider';
import { TransactionDialogProvider } from '@/components/transaction-dialog';
import { EditTransactionDialogProvider } from '@/components/edit-transaction-dialog';
import { AddExpenseDialogProvider } from '@/components/add-expense-dialog';
import { MerchantPickerDialogProvider } from '@/components/merchant-picker-dialog';
import { CommandPaletteProvider } from '@/components/command-palette';
import { Toaster } from '@/components/ui/sonner';

const inter = Inter({
  subsets: ['latin'],
  weight: ['400', '500', '600'],
  style: ['normal', 'italic'],
  variable: '--font-inter',
});

const jetbrainsMono = JetBrains_Mono({
  subsets: ['latin'],
  weight: ['400', '500'],
  variable: '--font-jetbrains-mono',
});

export const metadata: Metadata = {
  title: 'Finch · Money for grown-ups',
  description: 'Personal expense tracker with multi-currency support',
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  // Shrink the layout viewport when the on-screen keyboard appears so that
  // `dvh` / `vh` measurements exclude it. Without this, the add-expense bottom
  // sheet (h-[92dvh]) keeps its full pre-keyboard height on iOS, hiding the
  // submit button behind the keyboard.
  interactiveWidget: 'resizes-content',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      data-scroll-behavior="smooth"
      suppressHydrationWarning
      className={`${inter.variable} ${jetbrainsMono.variable}`}
    >
      <body className="min-h-screen font-sans antialiased">
        <ThemeProvider attribute="class" defaultTheme="light" enableSystem disableTransitionOnChange>
          <I18nProvider>
          <LedgerProvider>
            <StoreHydration />
            <SqliteBackupProvider>
              <MerchantPickerDialogProvider>
                {/* Edit must wrap Transaction: TransactionDialogProvider renders
                    TransactionDetail (which calls useEditTransaction) in its own
                    subtree, not among its children. */}
                <EditTransactionDialogProvider>
                  <TransactionDialogProvider>
                    <AddExpenseDialogProvider>
                      <CommandPaletteProvider>
                        {children}
                        <Toaster />
                      </CommandPaletteProvider>
                    </AddExpenseDialogProvider>
                  </TransactionDialogProvider>
                </EditTransactionDialogProvider>
              </MerchantPickerDialogProvider>
            </SqliteBackupProvider>
          </LedgerProvider>
          </I18nProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
