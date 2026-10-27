import React, { useId } from 'react';

interface AgentSpurLogoProps {
  size?: number;
  variant?: 'squircle' | 'glyph';
  className?: string;
}

/**
 * Featherlight Fluid AgentSpur Brand Mark:
 * Airy sunlit porcelain-sky squircle housing a fluid droplet Master core
 * and a delicate orbital Spur arc + Sub-Agent satellite node.
 */
export const AgentSpurLogo: React.FC<AgentSpurLogoProps> = ({
  size = 18,
  variant = 'squircle',
  className = '',
}) => {
  const uid = useId();
  const glassId = `${uid}-glass`;
  const coreId = `${uid}-core`;
  const orbitId = `${uid}-orbit`;

  if (variant === 'glyph') {
    return (
      <svg
        width={size}
        height={size}
        viewBox="0 0 24 24"
        fill="none"
        aria-hidden="true"
        className={`shrink-0 ${className}`}
      >
        <defs>
          <linearGradient
            id={coreId}
            x1="8.5"
            y1="6"
            x2="15.5"
            y2="17.5"
            gradientUnits="userSpaceOnUse"
          >
            <stop offset="0%" stopColor="#38BDF8" />
            <stop offset="100%" stopColor="#0284C7" />
          </linearGradient>
        </defs>
        <path
          d="M5.2 14.8A7.4 7.4 0 1 1 16.2 18.1"
          stroke="#38BDF8"
          strokeWidth="1.6"
          strokeLinecap="round"
        />
        <circle cx="18.2" cy="7.6" r="1.55" fill="#0EA5E9" />
        <path
          d="M12 6.3C12 6.3 15.8 10.3 15.8 13.15C15.8 15.28 14.1 17 12 17C9.9 17 8.2 15.28 8.2 13.15C8.2 10.3 12 6.3 12 6.3Z"
          fill={`url(#${coreId})`}
        />
        <circle cx="10.85" cy="12.5" r="1.05" fill="#FFFFFF" fillOpacity="0.9" />
      </svg>
    );
  }

  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
      className={`shrink-0 ${className}`}
    >
      <defs>
        <linearGradient
          id={glassId}
          x1="2"
          y1="2"
          x2="22"
          y2="22"
          gradientUnits="userSpaceOnUse"
        >
          <stop offset="0%" stopColor="#FFFFFF" />
          <stop offset="55%" stopColor="#F0F9FF" />
          <stop offset="100%" stopColor="#E0F2FE" />
        </linearGradient>
        <linearGradient
          id={coreId}
          x1="9"
          y1="6.5"
          x2="15.5"
          y2="17"
          gradientUnits="userSpaceOnUse"
        >
          <stop offset="0%" stopColor="#38BDF8" />
          <stop offset="100%" stopColor="#0284C7" />
        </linearGradient>
        <linearGradient
          id={orbitId}
          x1="5"
          y1="6"
          x2="18.5"
          y2="17.5"
          gradientUnits="userSpaceOnUse"
        >
          <stop offset="0%" stopColor="#7DD3FC" stopOpacity="0.45" />
          <stop offset="100%" stopColor="#0EA5E9" stopOpacity="0.9" />
        </linearGradient>
      </defs>
      <rect
        x="1.5"
        y="1.5"
        width="21"
        height="21"
        rx="6"
        fill={`url(#${glassId})`}
        stroke="#BAE6FD"
        strokeWidth="1"
      />
      <path
        d="M5.9 14.5A6.75 6.75 0 1 1 15.8 17.55"
        stroke={`url(#${orbitId})`}
        strokeWidth="1.45"
        strokeLinecap="round"
      />
      <circle cx="17.65" cy="8.15" r="1.4" fill="#0EA5E9" />
      <path
        d="M12 6.9C12 6.9 15.45 10.55 15.45 13.15C15.45 15.08 13.9 16.65 12 16.65C10.1 16.65 8.55 15.08 8.55 13.15C8.55 10.55 12 6.9 12 6.9Z"
        fill={`url(#${coreId})`}
      />
      <circle cx="10.95" cy="12.55" r="1" fill="#FFFFFF" fillOpacity="0.9" />
    </svg>
  );
};
