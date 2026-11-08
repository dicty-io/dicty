/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  darkMode: "class",
  theme: {
    extend: {
      colors: {
        sageGreen: {
          DEFAULT: "var(--app-accent-active, #5D6658)",
          light: "var(--app-accent, #87B996)",
          dark: "var(--app-accent-active, #41493E)",
        },
        stylishGreen: {
          DEFAULT: "#278C40",
          light: "#38B573",
        },
        warmAmber: "#E8924E",
        mutedSlate: "#82A0B9",
        dictyDark: "#121418",
        dictySecondary: "rgba(255, 255, 255, 0.55)",
      },
      fontFamily: {
        sans: [
          "-apple-system",
          "BlinkMacSystemFont",
          '"Segoe UI"',
          "Roboto",
          "Helvetica",
          "Arial",
          "sans-serif",
        ],
      },
      boxShadow: {
        glass: "0 16px 40px rgba(0, 0, 0, 0.45)",
        card: "0 4px 20px rgba(0, 0, 0, 0.2)",
      },
    },
  },
  plugins: [],
};
