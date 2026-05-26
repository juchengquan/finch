import styles from './EmptyState.module.css';

export function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className={styles.wrap}>
      <div className={styles.title}>{title}</div>
      <div className={styles.body}>{body}</div>
    </div>
  );
}
