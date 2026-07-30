import auth from "@react-native-firebase/auth";

export async function sendOtp(phoneNumber: string) {
  return auth().signInWithPhoneNumber(phoneNumber);
}

export async function verifyOtp(confirmation: any, code: string) {
  const credential = await confirmation.confirm(code);
  return credential.user;
}

export async function signInWithGoogleIdToken(idToken: string) {
  const credential = auth.GoogleAuthProvider.credential(idToken);
  return auth().signInWithCredential(credential);
}
