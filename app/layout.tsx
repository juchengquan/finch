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
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com"/>
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous"/>
        <link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet"/>
      </head>
      <body style={{ margin: 0, minHeight: '100vh' }}>
        <TweaksProvider>{children}</TweaksProvider>
      </body>
    </html>
  );
}