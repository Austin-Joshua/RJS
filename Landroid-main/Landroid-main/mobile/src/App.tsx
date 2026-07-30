import React, { useState } from "react";
import { Pressable, SafeAreaView, Text, View } from "react-native";

import { bootstrapParcel } from "./api/client";
import { RoleGate } from "./components/RoleGate";
import { translations } from "./i18n/translations";
import { AuthScreen } from "./screens/AuthScreen";
import { DashboardScreen } from "./screens/DashboardScreen";
import { MapScreen } from "./screens/MapScreen";
import { SettingsScreen } from "./screens/SettingsScreen";
import type { Session } from "./types";

type Tab = "map" | "dashboard" | "settings";

export default function App() {
  const [locale, setLocale] = useState<"en" | "ta">("en");
  const [tab, setTab] = useState<Tab>("map");
  const [session, setSession] = useState<Session | null>(null);

  if (!session) {
    return <AuthScreen onAuthenticated={setSession} />;
  }

  const switchRole = async () => {
    const next = session.role === "consultant"
      ? { token: "demo-owner", role: "landowner" as const, uid: "owner-1" }
      : { token: "demo-consultant", role: "consultant" as const, uid: "consultant-1" };
    setSession(next);
  };

  const createParcel = async () => {
    if (session.role !== "consultant") {
      return;
    }
    await bootstrapParcel(session);
  };

  return (
    <SafeAreaView style={{ flex: 1 }}>
      <View style={{ flexDirection: "row", justifyContent: "space-around", padding: 8 }}>
        <Pressable onPress={() => setTab("map")}><Text>{translations[locale].map}</Text></Pressable>
        <Pressable onPress={() => setTab("dashboard")}><Text>{translations[locale].dashboard}</Text></Pressable>
        <Pressable onPress={() => setTab("settings")}><Text>{translations[locale].settings}</Text></Pressable>
      </View>
      <View style={{ flexDirection: "row", justifyContent: "space-around", padding: 8 }}>
        <Pressable onPress={switchRole}><Text>{session.role}</Text></Pressable>
        <Pressable onPress={() => setLocale(locale === "en" ? "ta" : "en")}><Text>{locale.toUpperCase()}</Text></Pressable>
        <Pressable onPress={createParcel}><Text>Create Parcel</Text></Pressable>
      </View>
      {tab === "map" && <MapScreen locale={locale} />}
      {tab === "dashboard" && <DashboardScreen locale={locale} session={session} />}
      {tab === "settings" && (
        <RoleGate required="consultant" current={session.role} locale={locale}>
          <SettingsScreen locale={locale} />
        </RoleGate>
      )}
    </SafeAreaView>
  );
}
