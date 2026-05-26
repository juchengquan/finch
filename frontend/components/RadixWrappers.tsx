'use client';

import { ReactNode, forwardRef } from 'react';
import * as Accordion from '@radix-ui/react-accordion';
import * as Toggle from '@radix-ui/react-toggle';
import * as ToggleGroup from '@radix-ui/react-toggle-group';
import { Slot } from '@radix-ui/react-slot';
import { Icon } from './primitives';
import styles from './RadixWrappers.module.css';

/* ============================================
   Accordion
   ============================================ */

interface FinchAccordionProps {
  children: ReactNode;
  type?: 'single' | 'multiple';
  defaultValue?: string | string[];
  collapsible?: boolean;
  className?: string;
}

export function FinchAccordion({
  children,
  type = 'single',
  defaultValue,
  collapsible = true,
  className,
}: FinchAccordionProps) {
  if (type === 'single') {
    return (
      <Accordion.Root
        type="single"
        defaultValue={defaultValue as string | undefined}
        collapsible={collapsible}
        className={className}
        dir="ltr"
      >
        {children}
      </Accordion.Root>
    );
  }
  return (
    <Accordion.Root
      type="multiple"
      defaultValue={defaultValue as string[] | undefined}
      className={className}
      dir="ltr"
    >
      {children}
    </Accordion.Root>
  );
}

interface FinchAccordionItemProps {
  children: ReactNode;
  value: string;
  className?: string;
}

export function FinchAccordionItem({ children, value, className }: FinchAccordionItemProps) {
  return (
    <Accordion.Item value={value} className={`${styles.accordionItem} ${className ?? ''}`}>
      {children}
    </Accordion.Item>
  );
}

interface FinchAccordionTriggerProps {
  children: ReactNode;
  className?: string;
  asChild?: boolean;
}

export const FinchAccordionTrigger = forwardRef<HTMLButtonElement, FinchAccordionTriggerProps>(
  ({ children, className, asChild = false }, forwardedRef) => {
    const content = (
      <Accordion.Trigger className={`${styles.accordionTrigger} ${className ?? ''}`} ref={forwardedRef}>
        <span>{children}</span>
        <span>
          <Icon name="chev-d" size={12}/>
        </span>
      </Accordion.Trigger>
    );

    if (asChild) {
      return <Slot>{content}</Slot>;
    }
    return content;
  }
);

FinchAccordionTrigger.displayName = 'FinchAccordionTrigger';

interface FinchAccordionContentProps {
  children: ReactNode;
  className?: string;
}

export function FinchAccordionContent({ children, className }: FinchAccordionContentProps) {
  return (
    <Accordion.Content className={`${styles.accordionContent} ${className ?? ''}`}>
      <div className={styles.accordionContentInner}>
        <span dir="ltr" style={{ direction: 'ltr', textAlign: 'left', display: 'block' }}>{children}</span>
      </div>
    </Accordion.Content>
  );
}

/* ============================================
   Toggle
   ============================================ */

interface FinchToggleProps {
  pressed: boolean;
  onPressedChange: (pressed: boolean) => void;
  children?: ReactNode;
  className?: string;
  size?: 'small' | 'medium' | 'large';
  disabled?: boolean;
}

export function FinchToggle({
  pressed,
  onPressedChange,
  children,
  className,
  size = 'medium',
  disabled = false,
}: FinchToggleProps) {
  const sizeClass = {
    small: styles.toggleSmall,
    medium: styles.toggleMedium,
    large: styles.toggleLarge,
  }[size];

  return (
    <Toggle.Root
      pressed={pressed}
      onPressedChange={onPressedChange}
      disabled={disabled}
      className={`${styles.toggle} ${sizeClass} ${pressed ? styles.toggleOn : ''} ${className ?? ''}`}
    >
      {children ?? (
        <span className={`${styles.toggleThumb} ${pressed ? styles.toggleThumbOn : ''}`}/>
      )}
    </Toggle.Root>
  );
}

/* ============================================
   Toggle Group (for palette selector)
   ============================================ */

interface FinchToggleGroupProps {
  children: ReactNode;
  value: string;
  onValueChange: (value: string) => void;
  className?: string;
}

export function FinchToggleGroup({
  children,
  value,
  onValueChange,
  className,
}: FinchToggleGroupProps) {
  return (
    <ToggleGroup.Root
      type="single"
      value={value}
      onValueChange={onValueChange}
      className={`${styles.toggleGroup} ${className ?? ''}`}
    >
      {children}
    </ToggleGroup.Root>
  );
}

interface FinchToggleGroupItemProps {
  children: ReactNode;
  value: string;
  className?: string;
  disabled?: boolean;
}

export function FinchToggleGroupItem({
  children,
  value,
  className,
  disabled = false,
}: FinchToggleGroupItemProps) {
  return (
    <ToggleGroup.Item value={value} disabled={disabled} className={className}>
      {children}
    </ToggleGroup.Item>
  );
}

