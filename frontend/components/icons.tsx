// frontend/components/icons.tsx — barrel re-exporting lucide-react components
// with the same short names that the old <Icon name="..."> shim used. Each
// import has the form `export { LucideName as ShortName } from 'lucide-react'`
// so consumers can do `import { ChevU } from '@/components/icons'` and get
// the PascalCase-cased component.
//
// The barrel is the SOLE entry point for lucide icons in this codebase. Pages,
// dialogs, and primitives all import from here. lucide-react is the upstream
// dep; the barrel is the local typed surface.

export { Utensils as Fork } from 'lucide-react';
export { Home as Home } from 'lucide-react';
export { Car as Car } from 'lucide-react';
export { ShoppingBag as Bag } from 'lucide-react';
export { Film as Film } from 'lucide-react';
export { Heart as Heart } from 'lucide-react';
export { RefreshCw as Sync } from 'lucide-react';
export { MoreHorizontal as Dots } from 'lucide-react';
export { Plus as Plus } from 'lucide-react';
export { Search as Search } from 'lucide-react';
export { SlidersHorizontal as Filter } from 'lucide-react';
export { ChevronRight as Chev } from 'lucide-react';
export { ChevronLeft as ChevL } from 'lucide-react';
export { ChevronDown as ChevD } from 'lucide-react';
export { ChevronUp as ChevU } from 'lucide-react';
export { ArrowRight as ArrowR } from 'lucide-react';
export { ArrowLeft as ArrowL } from 'lucide-react';
export { ArrowUp as ArrowU } from 'lucide-react';
export { ArrowDown as ArrowD } from 'lucide-react';
export { ArrowDownLeft as ArrowDl } from 'lucide-react';
export { ArrowUpRight as ArrowUr } from 'lucide-react';
export { Menu as Menu } from 'lucide-react';
export { Bell as Bell } from 'lucide-react';
export { Wallet as Wallet } from 'lucide-react';
export { ChartColumn as Chart } from 'lucide-react';
export { Settings as Cog } from 'lucide-react';
export { FileText as Doc } from 'lucide-react';
export { Target as Target } from 'lucide-react';
export { Tag as Tag } from 'lucide-react';
export { Tags as Tags } from 'lucide-react';
export { Split as Split } from 'lucide-react';
export { Pencil as Edit } from 'lucide-react';
export { Pencil as Pencil } from 'lucide-react';
export { Check as Check } from 'lucide-react';
export { X as X } from 'lucide-react';
export { Calendar as Calendar } from 'lucide-react';
export { Mic as Mic } from 'lucide-react';
export { Camera as Cam } from 'lucide-react';
export { Sparkles as Sparkle } from 'lucide-react';
export { Clock as Clock } from 'lucide-react';
export { Download as Download } from 'lucide-react';
export { Upload as Upload } from 'lucide-react';
export { ArrowRightLeft as Swap } from 'lucide-react';
export { Coins as Coins } from 'lucide-react';
export { Trash2 as Trash } from 'lucide-react';
export { Bookmark as Bookmark } from 'lucide-react';
export { Paperclip as Paperclip } from 'lucide-react';
export { Image as ImageIcon } from 'lucide-react';
export { Banknote as Banknote } from 'lucide-react';
export { ShieldCheck as ShieldCheck } from 'lucide-react';
