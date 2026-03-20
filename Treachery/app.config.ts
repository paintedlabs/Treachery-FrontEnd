import { ExpoConfig, ConfigContext } from "expo/config";

const environment = process.env.EXPO_PUBLIC_ENVIRONMENT ?? "development";

const appNameSuffix: Record<string, string> = {
  production: "",
  staging: " (STG)",
  development: " (DEV)",
};

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: `Treachery${appNameSuffix[environment] ?? " (DEV)"}`,
  slug: "Treachery",
  version: "1.0.0",
  orientation: "portrait",
  icon: "./assets/icon.png",
  userInterfaceStyle: "dark",
  scheme: "treachery",
  splash: {
    image: "./assets/splash-icon.png",
    resizeMode: "contain",
    backgroundColor: "#0d0b1a",
  },
  ios: {
    supportsTablet: true,
    bundleIdentifier: "com.PaintedLabs.Treachery",
  },
  android: {
    adaptiveIcon: {
      backgroundColor: "#0d0b1a",
      foregroundImage: "./assets/android-icon-foreground.png",
      backgroundImage: "./assets/android-icon-background.png",
      monochromeImage: "./assets/android-icon-monochrome.png",
    },
    package: "com.paintedlabs.treachery",
  },
  web: {
    favicon: "./assets/favicon.png",
    bundler: "metro",
  },
  plugins: ["expo-router", "expo-sharing"],
});
