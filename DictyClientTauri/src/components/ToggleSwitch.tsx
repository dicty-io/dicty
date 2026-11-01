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
      style={{
        backgroundColor: disabled ? undefined : checked ? "var(--app-accent-active, #5D6658)" : undefined,
        borderColor: disabled ? undefined : checked ? "rgba(var(--app-accent-rgb, 135, 185, 150), 0.45)" : undefined,
        boxShadow: disabled || !checked ? undefined : "0 0 10px rgba(var(--app-accent-glow, 93, 102, 88), 0.3)",
      }}
      className={`relative inline-flex flex-shrink-0 items-center rounded-full transition-all duration-200 ease-in-out focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--app-accent,#87B996)]/60 ${
        isSm ? "w-8 h-[18px]" : "w-10 h-[22px]"
      } ${
        disabled
          ? "opacity-35 cursor-not-allowed bg-white/10 border-white/5"
          : checked
          ? "border hover:brightness-110"
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
