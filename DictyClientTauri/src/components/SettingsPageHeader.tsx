import React from "react";
import { FeatureHelpButton, FeatureHelpTopic } from "./FeatureHelpModal";

interface SettingsPageHeaderProps {
  title: string;
  description?: string;
  helpTopic?: FeatureHelpTopic;
  children?: React.ReactNode;
}

export const SettingsPageHeader: React.FC<SettingsPageHeaderProps> = ({
  title,
  description,
  helpTopic,
  children,
}) => {
  return (
    <div className="mb-4 sm:mb-6 space-y-1 min-w-0 flex-1">
      <div className="flex items-center gap-2.5">
        <h1 className="text-xl sm:text-2xl font-bold tracking-tight text-white font-sans truncate">
          {title}
        </h1>
        {helpTopic && (
          <FeatureHelpButton topic={helpTopic} label={title} />
        )}
      </div>
      {description && (
        <p className="text-xs sm:text-sm text-white/55 leading-relaxed break-words">
          {description}
        </p>
      )}
      {children}
    </div>
  );
};
