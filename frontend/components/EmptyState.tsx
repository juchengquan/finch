export function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="text-muted-foreground px-5 pt-10 pb-28 text-center">
      <div className="font-serif text-2xl italic">{title}</div>
      <div className="mt-2 text-[13px]">{body}</div>
    </div>
  );
}
