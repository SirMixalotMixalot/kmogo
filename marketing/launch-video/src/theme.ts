import { loadFont } from "@remotion/google-fonts/Nunito";

// Nunito's rounded heavy weights match the app's SF Rounded wordmark.
export const { fontFamily } = loadFont("normal", { weights: ["700", "800", "900"], subsets: ["latin"] });

export const C = {
  night: "#0D0F17",
  dusk: "#211A33",
  orange: "#FF6B2C",
  orangeSoft: "rgba(255, 107, 44, 0.35)",
  white: "#FFFFFF",
  muted: "rgba(255, 255, 255, 0.72)",
};
