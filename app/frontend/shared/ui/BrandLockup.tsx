import classes from './BrandLockup.module.css';
import { Logo } from './Logo';

type BrandSize = 'sm' | 'md' | 'lg';

interface BrandLockupProps {
  size?: BrandSize;
  /** Pins the mark's scheme. Leave unset on a card that keeps its own scheme. */
  colorScheme?: 'dark' | 'light';
  className?: string;
}

const MARK_WIDTH: Record<BrandSize, number> = { sm: 76, md: 96, lg: 124 };

/**
 * The product's name: the Aixle mark and the word Flow, set together. The mark
 * on its own is the company, not this product, so anywhere a visitor is being
 * told what they are signing up to gets the pair.
 */
export const BrandLockup = ({ size = 'md', colorScheme, className }: BrandLockupProps) => (
  <span className={`${classes.root} ${classes[size]} ${className ?? ''}`}>
    <Logo width={MARK_WIDTH[size]} colorScheme={colorScheme} />
    <span className={classes.word}>Flow</span>
  </span>
);
