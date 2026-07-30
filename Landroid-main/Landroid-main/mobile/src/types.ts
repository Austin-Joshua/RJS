export type Role = "consultant" | "landowner";

export type Session = {
  token: string;
  role: Role;
  uid: string;
};
