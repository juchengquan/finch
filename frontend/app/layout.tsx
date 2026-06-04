import type { Metadata, Viewport } from 'next';
import { Inter, JetBrains_Mono } from 'next/font/google';
import './globals.css';
import { ThemeProvider } from '@/components/theme-provider';
import { LedgerProvider } from '@/components/ledger-provider';
import { StoreHydration } from '@/components/store-hydration';
import { SqliteBackupProvider } from '@/components/sqlite-backup-provider';
import { TransactionSheetProvider } from '@/components/transaction-sheet';
import { AddExpenseSheetProvider } from '@/components/add-expense-sheet';
import { MerchantPickerSheetProvider } from '@/components/merchant-picker-sheet';
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
          <LedgerProvider>
            <StoreHydration />
            <SqliteBackupProvider>
              <MerchantPickerSheetProvider>
                <TransactionSheetProvider>
                  <AddExpenseSheetProvider>
                    <CommandPaletteProvider>
                      {children}
                      <Toaster />
                    </CommandPaletteProvider>
                  </AddExpenseSheetProvider>
                </TransactionSheetProvider>
              </MerchantPickerSheetProvider>
            </SqliteBackupProvider>
          </LedgerProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
