import React from "react";

interface DictyLogoProps {
  className?: string;
  size?: number;
}

export const DictyLogo: React.FC<DictyLogoProps> = ({
  className = "w-7 h-7",
  size = 28,
}) => {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 1024 1024"
      width={size}
      height={size}
      className={className}
    >
      <rect width="1024" height="1024" rx="230" ry="230" fill="#506658" />
      <g
        fill="none"
        stroke="#ffffff"
        strokeWidth="70"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        {/* Left Bracket */}
        <path d="M 360 360 L 210 512 L 360 664" />
        {/* Right Bracket */}
        <path d="M 664 360 L 814 512 L 664 664" />
        {/* Audio Waveform Bars */}
        <path d="M 426 410 L 426 614" />
        <path d="M 512 330 L 512 694" />
        <path d="M 598 410 L 598 614" />
      </g>
    </svg>
  );
};
