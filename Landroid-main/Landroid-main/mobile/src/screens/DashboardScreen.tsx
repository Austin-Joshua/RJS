import React, { useEffect, useState } from "react";
import { ScrollView, Text, View } from "react-native";

import { aiApi } from "../api/client";
import { translations } from "../i18n/translations";
import type { Session } from "../types";

type Props = {
  locale: "en" | "ta";
  session: Session;
};

export function DashboardScreen({ locale, session }: Props) {
  const [landHealth, setLandHealth] = useState<any>(null);
  const [plantZones, setPlantZones] = useState<any>(null);
  const [valuation, setValuation] = useState<any>(null);

  useEffect(() => {
    aiApi.landHealth(session).then(setLandHealth).catch(() => null);
    aiApi.plantZones(session).then(setPlantZones).catch(() => null);
    aiApi.valuation(session).then(setValuation).catch(() => null);
  }, [session]);

  return (
    <ScrollView style={{ flex: 1, padding: 12 }}>
      <Text style={{ fontSize: 18 }}>{translations[locale].dashboard}</Text>
      <View style={{ marginTop: 12, padding: 12, borderWidth: 1, borderRadius: 8 }}>
        <Text>{translations[locale].landHealth}</Text>
        <Text>Score: {landHealth?.land_health?.score ?? "-"}</Text>
        <Text>
          {translations[locale].confidence}: {landHealth?.land_health?.confidence ?? "-"}%
        </Text>
      </View>
      <View style={{ marginTop: 12, padding: 12, borderWidth: 1, borderRadius: 8 }}>
        <Text>{translations[locale].plantZones}</Text>
        <Text>
          {translations[locale].confidence}: {plantZones?.plant_zones?.confidence ?? "-"}%
        </Text>
      </View>
      <View style={{ marginTop: 12, padding: 12, borderWidth: 1, borderRadius: 8 }}>
        <Text>{translations[locale].valuation}</Text>
        <Text>Band: {valuation?.valuation?.low_per_acre_inr ?? "-"} - {valuation?.valuation?.high_per_acre_inr ?? "-"}</Text>
        <Text>
          {translations[locale].confidence}: {valuation?.valuation?.confidence ?? "-"}%
        </Text>
      </View>
    </ScrollView>
  );
}
