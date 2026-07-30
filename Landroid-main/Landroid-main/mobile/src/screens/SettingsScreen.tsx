import React from "react";
import { Alert, Pressable, Text, View } from "react-native";

import { translations } from "../i18n/translations";

type Props = {
  locale: "en" | "ta";
};

export function SettingsScreen({ locale }: Props) {
  const clearCachedData = async () => {
    Alert.alert("Done", "Cached tiles/documents metadata cleared");
  };

  return (
    <View style={{ flex: 1, padding: 12 }}>
      <Text style={{ fontSize: 18 }}>{translations[locale].settings}</Text>
      <Pressable onPress={clearCachedData} style={{ marginTop: 16, padding: 12, borderWidth: 1, borderRadius: 8 }}>
        <Text>{translations[locale].clearCache}</Text>
      </Pressable>
    </View>
  );
}
