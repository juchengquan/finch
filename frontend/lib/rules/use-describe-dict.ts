'use client';

import { useTranslations } from 'next-intl';
import type { DescribeDict } from '@/lib/rules/describe';

/** React hook that assembles a `DescribeDict` from the active translation
 *  catalog. Pass the result into `describeCondition` / `describeActions`
 *  so the /rules list rows, RuleDetailSheet, and rule-builder preview
 *  read in the user's language. */
export function useDescribeDict(): DescribeDict {
  const tWeekday = useTranslations('ruleDescribe.weekdays');
  const tField = useTranslations('ruleDescribe.fields');
  const tOp = useTranslations('ruleDescribe.ops');
  const tCond = useTranslations('ruleDescribe.conditions');
  const tAct = useTranslations('ruleDescribe.actions');

  return {
    weekdays: [tWeekday('0'), tWeekday('1'), tWeekday('2'), tWeekday('3'), tWeekday('4'), tWeekday('5'), tWeekday('6')],
    fields: {
      merchant: tField('merchant'),
      amount: tField('amount'),
      account_id: tField('account_id'),
      category_id: tField('category_id'),
      counterparty_id: tField('counterparty_id'),
      currency: tField('currency'),
      date_dow: tField('date_dow'),
      date_dom: tField('date_dom'),
      kind: tField('kind'),
      tag_id: tField('tag_id'),
      note: tField('note'),
    },
    ops: {
      is: tOp('is'),
      isEmpty: tOp('isEmpty'),
      contains: tOp('contains'),
      startsWith: tOp('startsWith'),
      between: tOp('between'),
      weekday: tOp('weekday'),
      hasTag: tOp('hasTag'),
      hasAnyTag: tOp('hasAnyTag'),
      hasAllTags: tOp('hasAllTags'),
      noteContains: tOp('noteContains'),
    },
    conditions: {
      always: tCond('always'),
      never: tCond('never'),
      and: tCond('and'),
      or: tCond('or'),
      not: tCond('not'),
    },
    actions: {
      clearCategory: tAct('clearCategory'),
      setCategory: tAct('setCategory'),
      clearCounterparty: tAct('clearCounterparty'),
      setCounterparty: tAct('setCounterparty'),
      renameMerchant: tAct('renameMerchant'),
      setNote: tAct('setNote'),
      setKind: tAct('setKind'),
      addTag: tAct('addTag'),
      removeTag: tAct('removeTag'),
      markReviewed: tAct('markReviewed'),
      split: tAct('split'),
      uncategorized: tAct('uncategorized'),
      noActions: tAct('noActions'),
      separator: tAct('separator'),
    },
  };
}
