import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./hooks/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        // AXIOM dark game theme
        bg: {
          primary:   "#0D1117",
          secondary: "#161B22",
          tertiary:  "#21262D",
        },
        border: {
          subtle:  "#21262D",
          default: "#30363D",
          strong:  "#484F58",
        },
        text: {
          primary:   "#E6EDF3",
          secondary: "#8B949E",
          muted:     "#484F58",
        },
        accent: {
          blue:   "#58A6FF",
          green:  "#56D364",
          purple: "#D2A8FF",
          amber:  "#E3B341",
          red:    "#F78166",
          teal:   "#39D353",
        },
        civ: {
          territory: "#1F6FEB",
          enemy:     "#F85149",
          neutral:   "#30363D",
          fog:       "#0D1117",
        },
      },
      fontFamily: {
        mono: ["JetBrains Mono", "Fira Code", "monospace"],
        sans: ["Inter", "system-ui", "sans-serif"],
      },
      animation: {
        "pulse-slow": "pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite",
        "float":      "float 6s ease-in-out infinite",
        "glow":       "glow 2s ease-in-out infinite alternate",
        "scan":       "scan 2s linear infinite",
      },
      keyframes: {
        float: {
          "0%, 100%": { transform: "translateY(0px)" },
          "50%":      { transform: "translateY(-8px)" },
        },
        glow: {
          "0%":   { boxShadow: "0 0 5px #58A6FF40" },
          "100%": { boxShadow: "0 0 20px #58A6FF80, 0 0 40px #58A6FF40" },
        },
        scan: {
          "0%":   { transform: "translateY(-100%)" },
          "100%": { transform: "translateY(100vh)" },
        },
      },
      backgroundImage: {
        "grid-pattern": "linear-gradient(rgba(88,166,255,0.05) 1px, transparent 1px), linear-gradient(90deg, rgba(88,166,255,0.05) 1px, transparent 1px)",
        "hero-gradient": "radial-gradient(ellipse at top, #1F6FEB20 0%, transparent 60%)",
      },
      backgroundSize: {
        "grid": "40px 40px",
      },
    },
  },
  plugins: [],
};

export default config;