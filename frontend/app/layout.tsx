import type { Metadata, Viewport } from "next";
import "./globals.css";
import { TweaksProvider } from "@/components/TweaksContext";

export const metadata: Metadata = {
  title: "Finch · Money for grown-ups",
  description: "Personal expense tracker with multi-currency support",
};

export const viewport: Viewport = {
  width: "device-width",
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
    <html lang="en" data-scroll-behavior="smooth" suppressHydrationWarning>
      <body style={{ margin: 0, minHeight: '100vh' }}>
        <TweaksProvider>{children}</TweaksProvider>
      </body>
    </html>
  );
}