import React from "react";

interface ToggleSwitchProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  size?: "sm" | "md";
  ariaLabel?: string;
  className?: string;
}

export const ToggleSwitch: React.FC<ToggleSwitchProps> = ({
  checked,
  onChange,
  disabled = false,
  size = "md",
  ariaLabel,
  className = "",
}) => {
  const isSm = size === "sm";

  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={ariaLabel}
      disabled={disabled}
      onClick={(e) => {
        e.stopPropagation();
        if (!disabled) {
          onChange(!checked);
        }
      }}
      className={`relative inline-flex flex-shrink-0 items-center rounded-full transition-colors duration-200 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-[#87B996]/60 ${
        isSm ? "w-8 h-[18px]" : "w-10 h-[22px]"
      } ${
        disabled
          ? "opacity-35 cursor-not-allowed bg-white/10 border-white/5"
          : checked
          ? "bg-[#5D6658] border border-[#727d6c]/60 shadow-[0_0_10px_rgba(93,102,88,0.25)] hover:bg-[#667061]"
          : "bg-white/[0.08] hover:bg-white/[0.14] border border-white/10"
      } ${className}`}
    >
      <span
        aria-hidden="true"
        className={`pointer-events-none inline-block rounded-full bg-white shadow-sm transition-transform duration-200 ease-in-out ${
          isSm ? "w-3.5 h-3.5" : "w-4 h-4"
        } ${
          isSm
            ? checked
              ? "translate-x-[15px]"
              : "translate-x-[2px]"
            : checked
            ? "translate-x-[19px]"
              : "translate-x-[2px]"
        }`}
      />
    </button>
  );
};
