import React, { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import type { Session } from "../types";

type Props = {
  onAuthenticated: (session: Session) => void;
};

export function AuthScreen({ onAuthenticated }: Props) {
  const [phone, setPhone] = useState("+919999999999");
  const [code, setCode] = useState("123456");
  const [otpSent, setOtpSent] = useState(false);

  const onVerifyOtp = async () => {
    onAuthenticated({ token: "demo-consultant", role: "consultant", uid: "consultant-1" });
  };

  return (
    <View style={{ flex: 1, justifyContent: "center", padding: 16 }}>
      <Text style={{ fontSize: 18, marginBottom: 12 }}>Sign in</Text>
      <TextInput value={phone} onChangeText={setPhone} placeholder="Phone number" style={{ borderWidth: 1, padding: 8, marginBottom: 8 }} />
      <Pressable onPress={() => setOtpSent(true)} style={{ borderWidth: 1, padding: 10, marginBottom: 8 }}>
        <Text>Send OTP</Text>
      </Pressable>
      <TextInput value={code} onChangeText={setCode} placeholder="OTP code" style={{ borderWidth: 1, padding: 8, marginBottom: 8 }} />
      {otpSent && <Text style={{ marginBottom: 8 }}>Demo OTP mode active in Expo runtime.</Text>}
      <Pressable onPress={onVerifyOtp} style={{ borderWidth: 1, padding: 10, marginBottom: 8 }}>
        <Text>Verify OTP</Text>
      </Pressable>
      <Pressable onPress={() => onAuthenticated({ token: "demo-consultant", role: "consultant", uid: "consultant-1" })} style={{ borderWidth: 1, padding: 10 }}>
        <Text>Use Demo Login</Text>
      </Pressable>
    </View>
  );
}
