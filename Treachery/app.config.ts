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
  // SDK 57 dropped the top-level `splash` key; native splash config now lives
  // in the expo-splash-screen plugin. expo-status-bar also ships a plugin as of
  // SDK 57 and `expo install --fix` asks for it to be registered here.
  plugins: [
    "expo-router",
    "expo-sharing",
    "expo-status-bar",
    [
      "expo-splash-screen",
      {
        image: "./assets/splash-icon.png",
        resizeMode: "contain",
        backgroundColor: "#0d0b1a",
      },
    ],
  ],
});
