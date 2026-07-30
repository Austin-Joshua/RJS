# Architecture Overview

```mermaid
flowchart TD
  consultant[LandConsultantApp] -->|CreateParcel| backend[FastAPIBackend]
  landowner[LandownerApp] -->|ViewOwnParcelOnly| backend
  backend --> parcelSvc[ParcelService]
  backend --> aiSvc[AIServices]
  parcelSvc --> geo[BoundaryGeoJSON]
  aiSvc --> soil[ISRICSoilGrids]
  aiSvc --> osm[OSMOverpassNominatim]
  aiSvc --> planetary[PlanetaryComputer]
  aiSvc --> health[LandHealthModule]
  aiSvc --> zones[PlantZoneModule]
  aiSvc --> valuation[ValuationModule]
```

## Responsibilities

- Mobile app: role-based UI, map view, confidence display, clear cache action.
- Backend: token gate, role checks, parcel authorization, AI computation orchestration.
- Evidence docs: mandatory/desirable judge-proof checklist and runbook.
