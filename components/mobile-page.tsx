'use client';

interface MobilePageProps {
  children: React.ReactNode;
  header?: React.ReactNode;
  contentPadding?: string;
}

export function MobilePage({ children, header, contentPadding }: MobilePageProps) {
  return (
    <>
      {header}
      {contentPadding !== undefined ? <div style={{ padding: contentPadding }}>{children}</div> : children}
    </>
  );
}
