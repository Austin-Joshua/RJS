import React from "react";
import { Text, View } from "react-native";

import type { Role } from "../types";
import { translations } from "../i18n/translations";

type Props = {
  required: Role;
  current: Role;
  locale: "en" | "ta";
  children: React.ReactNode;
};

export function RoleGate({ required, current, locale, children }: Props) {
  if (required !== current) {
    return (
      <View style={{ padding: 16 }}>
        <Text style={{ fontSize: 14 }}>{translations[locale].roleBlocked}</Text>
      </View>
    );
  }
  return <>{children}</>;
}
