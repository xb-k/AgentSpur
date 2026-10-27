import React from 'react';

interface FeatherSwitchProps {
  checked: boolean;
  onChange: () => void;
  ariaLabel?: string;
  title?: string;
  size?: 'sm' | 'md';
}

/**
 * Unified Featherlight macOS Light Mode Switch:
 * Soft translucent sky-mist active track, delicate frosted neutral inactive track,
 * and smooth compositor-only thumb motion.
 */
export const FeatherSwitch: React.FC<FeatherSwitchProps> = ({
  checked,
  onChange,
  ariaLabel,
  title,
  size = 'md',
}) => {
  const isSmall = size === 'sm';

  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={ariaLabel}
      title={title}
      onClick={onChange}
      className={`relative inline-flex shrink-0 items-center rounded-full border transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-sky-400/50 cursor-pointer ${
        isSmall ? 'h-[16px] w-[28px]' : 'h-[19px] w-[34px]'
      } ${
        checked
          ? 'border-sky-400/50 bg-sky-400/85 hover:bg-sky-500/85'
          : 'border-slate-300/70 bg-slate-200/75 hover:bg-slate-300/70'
      }`}
    >
      <span
        className={`inline-block rounded-full bg-white shadow-[0_1px_2.5px_rgba(15,23,42,0.16)] transition-transform duration-200 ease-out ${
          isSmall
            ? `h-3 w-3 ${checked ? 'translate-x-[13px]' : 'translate-x-[1px]'}`
            : `h-3.5 w-3.5 ${checked ? 'translate-x-[16px]' : 'translate-x-[1.5px]'}`
        }`}
      />
    </button>
  );
};
