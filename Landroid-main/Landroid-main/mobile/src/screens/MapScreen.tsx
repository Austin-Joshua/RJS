import React from "react";
import { Text, View } from "react-native";

import { translations } from "../i18n/translations";

type Props = {
  locale: "en" | "ta";
};

export function MapScreen({ locale }: Props) {
  return (
    <View style={{ flex: 1, padding: 12 }}>
      <Text style={{ fontSize: 18, padding: 12 }}>{translations[locale].map}</Text>
      <View style={{ borderWidth: 1, borderRadius: 8, padding: 12 }}>
        <Text>Expo-safe map placeholder</Text>
        <Text style={{ marginTop: 8 }}>Boundary overlay pipeline is active in backend parcel APIs.</Text>
      </View>
    </View>
  );
}
