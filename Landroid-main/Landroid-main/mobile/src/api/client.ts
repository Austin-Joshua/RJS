import type { Session } from "../types";

const API_BASE_URL = "http://10.0.2.2:8000/api/v1";

const parcelId = "parcel-1";

async function request(path: string, session: Session) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    headers: {
      Authorization: `Bearer ${session.token}`,
      "Content-Type": "application/json"
    }
  });
  if (!response.ok) {
    throw new Error(`Request failed: ${response.status}`);
  }
  return response.json();
}

export async function bootstrapParcel(session: Session) {
  return fetch(`${API_BASE_URL}/parcels`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${session.token}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      name: "Kallapuram Parcel",
      owner_user_id: "owner-1",
      boundary_geojson_path: "../data/Boundary.geojson"
    })
  }).then((res) => res.json());
}

export const aiApi = {
  soilProbe: (session: Session) => request(`/ai/${parcelId}/soil`, session),
  landHealth: (session: Session) => request(`/ai/${parcelId}/land-health`, session),
  plantZones: (session: Session) => request(`/ai/${parcelId}/plant-zones`, session),
  valuation: (session: Session) => request(`/ai/${parcelId}/valuation`, session)
};
